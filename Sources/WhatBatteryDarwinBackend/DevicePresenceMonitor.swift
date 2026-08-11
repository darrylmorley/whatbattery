import Foundation
import os

/// Tells you the moment a device attaches or detaches, instead of finding out at
/// the next poll.
///
/// `AMDeviceNotificationSubscribe` is how Finder knows. Measured against the
/// tab's five second poll on a Mac with an iPad on USB and an iPhone on WiFi:
/// the poll trailed a real event by a median of 2.3 seconds and by as much as
/// 4.95, bounded by its own interval. Everything that had to be inferred from
/// that lag (how long to keep an unplugged device's figures, how long to wait
/// before believing a device is gone) is answered exactly by an event.
///
/// The same run showed the framework reporting attach and detach for a WiFi
/// device that `AMDCreateDeviceList` never returned at any sample, so a poll can
/// miss a device entirely that this sees.
public final class DevicePresenceMonitor: @unchecked Sendable {
    /// What happened, and to which device.
    public enum Change: Sendable, Equatable {
        case attached(udid: String, interface: Int32)
        case detached(udid: String, interface: Int32)

        /// The interface this change is about, which for a detach is the one
        /// whose loss made the device absent. That is not necessarily the one
        /// the device was last read over: a device that is cabled AND
        /// WiFi-paired is usually read over the cable, so a caller deciding
        /// "was this a cable pull" from its last reading gets the wrong answer
        /// for the WiFi drop that follows an unplug.
        public var interface: Int32 {
            switch self {
            case .attached(_, let interface), .detached(_, let interface): return interface
            }
        }

        /// Whether this change is about a cable, which is what decides if the
        /// tab acts on a departure at once or waits out a grace. The numbering
        /// lives in `MobileDeviceInterface` because the read path classifies
        /// the same interfaces and the two must not drift apart.
        public var isCable: Bool { MobileDeviceInterface.isCable(interface) }
    }

    private static let logger = Logger(subsystem: "app.whatbattery", category: "presence")

    /// Every interface each device is currently attached on. A device cabled and
    /// WiFi-paired attaches twice, so it is only really gone when the last one
    /// detaches.
    private var interfaces: [String: Set<Int32>] = [:]
    private let lock = NSLock()
    /// Touched only on the main queue, which `start` and `stop` both assert.
    private var handle: UnsafeMutableRawPointer?
    /// The retained self-reference handed to the framework, released when the
    /// subscription is confirmed gone.
    private var context: UnsafeMutableRawPointer?
    /// Read from the callback on the framework's thread and written by
    /// start/stop on the main queue, so it lives under the lock with
    /// `interfaces` rather than beside it.
    private var onChange: (@Sendable (Change) -> Void)?

    public init() {}

    /// No `deinit { stop() }`.
    ///
    /// While a subscription is live the framework holds a retain taken in
    /// `start`, so this object cannot be deallocated out from under an
    /// in-flight callback: deinit can only run once `stop` has succeeded and
    /// released it. That is the point of the retain. A deinit that called
    /// `stop` would be unreachable while subscribed and, if it somehow ran,
    /// would be the exact use-after-free it looked like it was preventing.
    ///
    /// The cost, stated plainly: a caller that never calls `stop` leaks this
    /// object and its subscription for the life of the process. That is a
    /// deliberate trade against a use-after-free, not an oversight, and it is
    /// why `IDeviceView` stops on leaving the tab as well as on disappear
    /// rather than relying on either one firing.

    /// True when the framework and the notification symbols are available.
    public static var isAvailable: Bool { Symbols.shared != nil }

    /// The UDIDs currently attached, by any interface.
    public var attachedUDIDs: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(interfaces.keys)
    }

    /// Start watching. The callback arrives on the run loop the subscription was
    /// made on, so callers hopping to the main actor should do so themselves.
    ///
    /// Returns false when the framework is unavailable, which leaves the caller
    /// on its poll and no worse off than before.
    @discardableResult
    public func start(onChange: @escaping @Sendable (Change) -> Void) -> Bool {
        precondition(Thread.isMainThread, "presence subscription lifecycle is main-thread only")
        guard let symbols = Symbols.shared else { return false }
        // Never stack a second subscription on top of one the framework has
        // refused to remove: the first would stay live and unreachable, still
        // delivering events to a handler the caller thinks it has replaced.
        guard stop() else { return false }

        lock.lock()
        self.onChange = onChange
        lock.unlock()

        // The callback is a C function pointer and cannot capture, so the
        // instance travels through the context pointer the framework passes
        // back. Retained, and balanced only when the framework has confirmed
        // the subscription is gone: an unretained context is a pointer into
        // memory the last release can free while a callback is already on its
        // way, and the callback has no way to notice.
        let context = Unmanaged.passRetained(self).toOpaque()
        var newHandle: UnsafeMutableRawPointer?
        let rc = symbols.subscribe(Self.callback, 0, 0, context, &newHandle)
        // Both, not just the return code. A success that left the handle nil
        // would give us nothing to unsubscribe with, so the retain below could
        // never be balanced and the monitor would be pinned for the life of
        // the process.
        guard rc == 0, newHandle != nil else {
            Self.logger.notice("presence subscription refused (rc \(rc, privacy: .public)); staying on the poll")
            Unmanaged<DevicePresenceMonitor>.fromOpaque(context).release()
            lock.lock()
            self.onChange = nil
            lock.unlock()
            return false
        }
        handle = newHandle
        self.context = context
        return true
    }

    /// Unsubscribe, and say whether the framework agreed.
    ///
    /// The handle is kept on failure. Dropping it and subscribing again would
    /// leave the old subscription live and unreachable, still holding a context
    /// pointer nothing can ever balance.
    @discardableResult
    public func stop() -> Bool {
        precondition(Thread.isMainThread, "presence subscription lifecycle is main-thread only")
        // Only ask the framework to unsubscribe from something it has not
        // already ended itself. That call would fail, and a failure keeps the
        // handle, so the retain would never be balanced and the subscription
        // could never be cleaned up.
        if let handle, let symbols = Symbols.shared, !frameworkEndedSubscription {
            let rc = symbols.unsubscribe(handle)
            guard rc == 0 else {
                Self.logger.error("presence unsubscribe refused (rc \(rc, privacy: .public)); keeping the subscription")
                return false
            }
        }
        // Past this point no further callback can arrive, either because the
        // framework confirmed the unsubscribe or because it ended the
        // subscription itself, so the retain taken in start() is balanced here
        // rather than inside the branch above.
        if let context { Unmanaged<DevicePresenceMonitor>.fromOpaque(context).release() }
        handle = nil
        context = nil
        lock.lock()
        onChange = nil
        interfaces = [:]
        endedByFramework = false
        lock.unlock()
        return true
    }

    /// Fold one raw event into the interface map and report it only when it
    /// changes whether the device is present at all.
    ///
    /// A device attaching on its second interface is not news, and a device
    /// detaching from one of two is not gone. Reporting either would put the
    /// caller back in the business of guessing which entry means what, which is
    /// the confusion this exists to remove.
    func record(attached: Bool, udid: String, interface: Int32) -> Change? {
        guard !udid.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        var present = interfaces[udid] ?? []
        let wasPresent = !present.isEmpty
        if attached { present.insert(interface) } else { present.remove(interface) }
        if present.isEmpty { interfaces[udid] = nil } else { interfaces[udid] = present }
        let isPresent = !present.isEmpty
        guard wasPresent != isPresent else { return nil }
        return isPresent ? .attached(udid: udid, interface: interface)
                         : .detached(udid: udid, interface: interface)
    }

    // MARK: - The C callback

    /// `AMDeviceNotification`: the device pointer, then the action. 1 attached,
    /// 2 detached, 3 the subscription itself going away.
    private static let callback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = {
        info, context in
        guard let info, let context, let symbols = Symbols.shared else { return }
        let device = info.load(as: UnsafeMutableRawPointer?.self)
        let action = info.load(fromByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        // Action 3 is the subscription itself going away. If the framework
        // ends it on its own (usbmuxd restarting, say) the handle is already
        // dead, so it is noted rather than acted on: releasing the retain from
        // here could deallocate the monitor while this very callback is
        // running, which is the use-after-free the retain exists to prevent.
        // `stop` does the release, on the main thread, and skips an unsubscribe
        // that would only fail.
        if action == 3 {
            Unmanaged<DevicePresenceMonitor>.fromOpaque(context)
                .takeUnretainedValue()
                .noteFrameworkEndedSubscription()
            return
        }
        guard let device, action == 1 || action == 2 else { return }
        let monitor = Unmanaged<DevicePresenceMonitor>.fromOpaque(context).takeUnretainedValue()

        let udid = symbols.copyID(device)?.takeRetainedValue() as String? ?? ""
        let interface = symbols.interfaceType(device)
        guard let change = monitor.record(attached: action == 1, udid: udid, interface: interface) else { return }
        // Copied under the lock and invoked outside it: holding the lock across
        // a caller's closure invites a deadlock if it ever calls back in.
        guard let deliver = monitor.currentHandler() else { return }
        deliver(change)
    }

    private func currentHandler() -> (@Sendable (Change) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return onChange
    }

    /// The framework says it has ended the subscription itself.
    func noteFrameworkEndedSubscription() {
        lock.lock()
        endedByFramework = true
        lock.unlock()
        Self.logger.notice("presence subscription ended by the framework; staying on the poll until restarted")
    }

    private var endedByFramework = false

    private var frameworkEndedSubscription: Bool {
        lock.lock()
        defer { lock.unlock() }
        return endedByFramework
    }

    // MARK: - Symbols

    /// Separate from `MobileDeviceBridge`'s set, which is deliberately the
    /// minimum needed to read a battery. A missing symbol here degrades to the
    /// poll rather than to no devices at all.
    private struct Symbols {
        /// The first argument is the callback itself, typed here rather than as
        /// a raw pointer so the compiler checks the shape.
        typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        typealias FnSubscribe = @convention(c) (
            Callback, Int32, Int32, UnsafeMutableRawPointer?,
            UnsafeMutablePointer<UnsafeMutableRawPointer?>
        ) -> Int32
        typealias FnUnsubscribe = @convention(c) (UnsafeMutableRawPointer) -> Int32
        typealias FnCopyID = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFString>?
        typealias FnDevInt = @convention(c) (UnsafeMutableRawPointer) -> Int32

        let subscribe: FnSubscribe
        let unsubscribe: FnUnsubscribe
        let copyID: FnCopyID
        let interfaceType: FnDevInt

        static let shared: Symbols? = {
            let path = "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"
            guard let handle = dlopen(path, RTLD_NOW) else { return nil }
            func bind<T>(_ name: String, _ type: T.Type) -> T? {
                guard let pointer = dlsym(handle, name) else { return nil }
                return unsafeBitCast(pointer, to: T.self)
            }
            guard
                let subscribe = bind("AMDeviceNotificationSubscribe", FnSubscribe.self),
                let unsubscribe = bind("AMDeviceNotificationUnsubscribe", FnUnsubscribe.self),
                let copyID = bind("AMDeviceCopyDeviceIdentifier", FnCopyID.self),
                let interfaceType = bind("AMDeviceGetInterfaceType", FnDevInt.self)
            else {
                // Nothing here will be called again, so let the framework go
                // rather than keeping it mapped for the life of the process.
                dlclose(handle)
                return nil
            }
            return Symbols(
                subscribe: subscribe, unsubscribe: unsubscribe,
                copyID: copyID, interfaceType: interfaceType
            )
        }()
    }
}
