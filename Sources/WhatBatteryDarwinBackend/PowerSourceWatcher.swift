import Foundation
import IOKit.ps

/// Fires a callback whenever the system power source changes (plug, unplug,
/// charge-level change). This is the event-driven half of the refresh strategy:
/// the app gets instant updates instead of waiting for the next poll tick.
///
/// The callback is delivered on the main run loop, so it is safe to update
/// main-actor UI state directly from it.
public final class PowerSourceWatcher {
    private var runLoopSource: CFRunLoopSource?
    private let onChange: () -> Void

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        guard runLoopSource == nil else { return }
        // Pass `self` to the C callback as an opaque context pointer. The
        // callback itself captures nothing, so it converts cleanly to a C
        // function pointer.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { rawContext in
            guard let rawContext else { return }
            let watcher = Unmanaged<PowerSourceWatcher>.fromOpaque(rawContext).takeUnretainedValue()
            watcher.onChange()
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
    }
}
