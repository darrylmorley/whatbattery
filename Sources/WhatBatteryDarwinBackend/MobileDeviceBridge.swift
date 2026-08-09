import Foundation

/// Native bridge to Apple's private `MobileDevice.framework` for reading a
/// tethered/WiFi iPhone or iPad's battery. This is the shipping path: it needs no
/// Python (`pymobiledevice3`) and no bundled libraries. The framework is present
/// on every Mac and is the same one Xcode and Finder use; the device's battery
/// is read over the `com.apple.mobile.diagnostics_relay` service.
///
/// We `dlopen` the framework and `dlsym` each function rather than link it, so a
/// missing or renamed private symbol degrades to "no devices" instead of failing
/// to launch. Allowed for Developer ID / notarised distribution (our model), not
/// the Mac App Store.
///
/// Caveat: the diagnostics relay is a private interface that can change across
/// iOS versions, so a shipping feature must still gate on a per-iOS-version
/// compatibility check before trusting the parsed fields.
enum MobileDeviceBridge {
    /// One device's identity plus its raw `AppleSmartBattery` dictionary (nil if
    /// the battery read failed for that device).
    struct RawDevice {
        let udid: String
        let productType: String
        let productVersion: String
        let deviceName: String
        let serial: String           // the device's hardware serial (lockdown "SerialNumber")
        let connectionType: String   // "USB", "Network", or ""
        /// Connect AND a lockdown session both succeeded, so the diagnostics
        /// relay was actually available. Reported rather than inferred: the
        /// caller used to guess this from an empty product type, which is a
        /// side effect of a different call and not something this code
        /// guarantees. `AMDeviceCopyValue("ProductType")` answering without a
        /// validated session would have made a locked device report "reached
        /// but silent", which is the wrong advice for the commonest cause.
        let reached: Bool
        let batteryDictionary: [String: Any]?
    }

    // MARK: - Symbol binding

    private typealias FnCreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias FnDevInt = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias FnCopyID = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFString>?
    private typealias FnCopyValue = @convention(c) (UnsafeMutableRawPointer, CFString?, CFString?) -> Unmanaged<CFTypeRef>?
    private typealias FnSecureStart = @convention(c) (UnsafeMutableRawPointer, CFString, CFDictionary?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    private typealias FnSend = @convention(c) (UnsafeMutableRawPointer, CFTypeRef, CFPropertyListFormat) -> Int32
    private typealias FnReceive = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>, UnsafeMutablePointer<CFPropertyListFormat>) -> Int32

    private struct Symbols {
        let createList: FnCreateList
        let connect: FnDevInt
        let validate: FnDevInt
        let startSession: FnDevInt
        let stopSession: FnDevInt
        let disconnect: FnDevInt
        let interfaceType: FnDevInt
        let copyID: FnCopyID
        let copyValue: FnCopyValue
        let secureStart: FnSecureStart
        let send: FnSend
        let receive: FnReceive
        let invalidate: FnDevInt    // AMDServiceConnectionInvalidate (return ignored)
        let getSocket: FnDevInt     // AMDServiceConnectionGetSocket -> fd
    }

    /// One diagnostics session may be open per process at a time. MobileDevice's
    /// thread-safety for concurrent connect/session on the same device is
    /// undocumented, so serialize the whole read path.
    private static let lock = NSLock()

    private static let symbols: Symbols? = {
        let path = "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"
        guard let handle = dlopen(path, RTLD_NOW) else { return nil }
        func bind<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard
            let createList = bind("AMDCreateDeviceList", FnCreateList.self),
            let connect = bind("AMDeviceConnect", FnDevInt.self),
            let validate = bind("AMDeviceValidatePairing", FnDevInt.self),
            let startSession = bind("AMDeviceStartSession", FnDevInt.self),
            let stopSession = bind("AMDeviceStopSession", FnDevInt.self),
            let disconnect = bind("AMDeviceDisconnect", FnDevInt.self),
            let interfaceType = bind("AMDeviceGetInterfaceType", FnDevInt.self),
            let copyID = bind("AMDeviceCopyDeviceIdentifier", FnCopyID.self),
            let copyValue = bind("AMDeviceCopyValue", FnCopyValue.self),
            let secureStart = bind("AMDeviceSecureStartService", FnSecureStart.self),
            let send = bind("AMDServiceConnectionSendMessage", FnSend.self),
            let receive = bind("AMDServiceConnectionReceiveMessage", FnReceive.self),
            let invalidate = bind("AMDServiceConnectionInvalidate", FnDevInt.self),
            let getSocket = bind("AMDServiceConnectionGetSocket", FnDevInt.self)
        else {
            dlclose(handle)
            return nil
        }
        return Symbols(
            createList: createList, connect: connect, validate: validate,
            startSession: startSession, stopSession: stopSession, disconnect: disconnect,
            interfaceType: interfaceType, copyID: copyID, copyValue: copyValue,
            secureStart: secureStart, send: send, receive: receive,
            invalidate: invalidate, getSocket: getSocket
        )
    }()

    /// True when the framework and all required symbols loaded.
    static var isAvailable: Bool { symbols != nil }

    // MARK: - Read

    /// Read every connected/paired device's identity and battery in one pass.
    /// Returns an empty array if the framework is unavailable or no device is
    /// connected. Never throws: a per-device failure yields a `RawDevice` with a
    /// nil `batteryDictionary` so identity is still reported.
    static func readAll() -> [RawDevice] {
        lock.lock()
        defer { lock.unlock() }
        guard let s = symbols, let listUM = s.createList() else { return [] }
        let list = listUM.takeRetainedValue()
        let count = CFArrayGetCount(list)
        guard count > 0 else { return [] }

        // Identity first, then group, then read. One physical device can be
        // listed twice: a phone that is plugged in AND WiFi-paired appears once
        // per interface with the same UDID (observed on a Mac with a single
        // iPhone 15, interface types 1 and 2). Reading both meant two lockdown
        // sessions and two diagnostics relays for one device, and the duplicate
        // reached the GUI, where the picker keys on UDID and a repeated id is
        // not something SwiftUI can render sensibly.
        var candidates: [(udid: String, interface: Int32, device: UnsafeMutableRawPointer)] = []
        for i in 0..<count {
            guard let dev = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, i)) else { continue }
            let udid = s.copyID(dev)?.takeRetainedValue() as String? ?? ""
            candidates.append((udid: udid, interface: s.interfaceType(dev), device: dev))
        }

        // `withExtendedLifetime`, because the device handles above are owned by
        // `list` and are used after the loop that reads them out of it. ARC
        // releases a strong local at its last apparent use, not at end of scope,
        // and after that loop nothing mentions `list` again. Releasing it there
        // would free every element the array retained, and the reads below would
        // be operating on dead handles. The previous version read each device
        // inside the same loop, which kept the array alive by accident; splitting
        // discovery from reading is what put that at risk.
        return withExtendedLifetime(list) {
            interfacesPerDevice(candidates).compactMap { read(anyOf: $0, symbols: s) }
        }
    }

    /// Read a device, trying each of its interfaces until one answers.
    ///
    /// Preferring USB and discarding the rest was wrong: if the USB entry is
    /// stale (a cable half out, a device mid-reconnect) the network entry that
    /// would have worked was thrown away before anything was attempted, turning a
    /// readable device unreadable. Preference decides the ORDER, not the only
    /// candidate.
    ///
    /// When every interface fails, the most informative attempt is reported: one
    /// that reached the device says more about why than one that never got there.
    private static func read(anyOf interfaces: [UnsafeMutableRawPointer], symbols s: Symbols) -> RawDevice? {
        var best: RawDevice?
        for dev in interfaces {
            let attempt = read(device: dev, symbols: s)
            if attempt.batteryDictionary != nil { return attempt }
            if best == nil || (attempt.reached && !(best?.reached ?? false)) { best = attempt }
        }
        return best
    }

    /// The interfaces of each physical device, grouped by UDID, USB first.
    ///
    /// USB leads because the relay read is blocking I/O and a cabled device
    /// answers it more reliably than one over WiFi. Groups keep the order the
    /// framework gave, so the device list does not reshuffle under the user. A
    /// device with an empty UDID gets its own group: two devices that failed to
    /// identify are not evidence of being the same device.
    static func interfacesPerDevice<T>(_ candidates: [(udid: String, interface: Int32, device: T)]) -> [[T]] {
        var groupIndexByUDID: [String: Int] = [:]
        var groups: [[(interface: Int32, device: T)]] = []
        for candidate in candidates {
            let entry = (interface: candidate.interface, device: candidate.device)
            guard !candidate.udid.isEmpty else { groups.append([entry]); continue }
            if let existing = groupIndexByUDID[candidate.udid] {
                groups[existing].append(entry)
            } else {
                groupIndexByUDID[candidate.udid] = groups.count
                groups.append([entry])
            }
        }
        // Stable sort by preference: `enumerated` keeps equal elements in the
        // order the framework listed them, which a bare `sorted(by:)` would not.
        return groups.map { group in
            group.enumerated()
                .sorted { lhs, rhs in
                    let lhsUSB = lhs.element.interface == usbInterface
                    let rhsUSB = rhs.element.interface == usbInterface
                    return lhsUSB == rhsUSB ? lhs.offset < rhs.offset : lhsUSB
                }
                .map(\.element.device)
        }
    }

    private static let usbInterface: Int32 = 1

    private static func read(device dev: UnsafeMutableRawPointer, symbols s: Symbols) -> RawDevice {
        let udid = s.copyID(dev)?.takeRetainedValue() as String? ?? ""
        let connection = connectionLabel(s.interfaceType(dev))

        // Connect + open a session before any value/service read.
        guard s.connect(dev) == 0 else {
            return RawDevice(udid: udid, productType: "", productVersion: "", deviceName: "",
                             serial: "", connectionType: connection, reached: false,
                             batteryDictionary: nil)
        }
        defer { _ = s.disconnect(dev) }

        _ = s.validate(dev)
        let sessionOK = s.startSession(dev) == 0
        defer { if sessionOK { _ = s.stopSession(dev) } }

        let productType = copyString(s, dev, "ProductType")
        let productVersion = copyString(s, dev, "ProductVersion")
        let deviceName = copyString(s, dev, "DeviceName")
        let serial = copyString(s, dev, "SerialNumber")

        let battery = sessionOK ? readBatteryDictionary(s, dev) : nil

        return RawDevice(
            udid: udid,
            productType: productType,
            productVersion: productVersion,
            deviceName: deviceName,
            serial: serial,
            connectionType: connection,
            // A session is what the diagnostics relay needs, so without one the
            // device was not reached in any sense that matters here, however
            // much of its identity it was willing to hand over.
            reached: sessionOK,
            batteryDictionary: battery
        )
    }

    private static func readBatteryDictionary(_ s: Symbols, _ dev: UnsafeMutableRawPointer) -> [String: Any]? {
        var conn: UnsafeMutableRawPointer? = nil
        let svcRC = s.secureStart(dev, "com.apple.mobile.diagnostics_relay" as CFString, nil, &conn)
        guard svcRC == 0, let conn else { return nil }
        // Always tear the relay connection down: leaking it exhausts lockdown
        // resources and makes later reads fail or hang.
        defer { _ = s.invalidate(conn) }

        // Bound the read: if the device disconnects mid-read or the relay never
        // replies, a socket-level timeout makes ReceiveMessage fail instead of
        // blocking the caller forever. The SSL read rides this underlying socket.
        let fd = s.getSocket(conn)
        if fd >= 0 {
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }

        let request: [String: Any] = ["Request": "IORegistry", "EntryClass": "AppleSmartBattery"]
        guard s.send(conn, request as CFDictionary, .xmlFormat_v1_0) == 0 else { return nil }

        var respUM: Unmanaged<CFTypeRef>? = nil
        var fmt: CFPropertyListFormat = .xmlFormat_v1_0
        guard s.receive(conn, &respUM, &fmt) == 0,
              let resp = respUM?.takeRetainedValue() as? [String: Any] else { return nil }

        // The relay nests the entry under Diagnostics.IORegistry on success.
        guard (resp["Status"] as? String) == "Success",
              let diag = resp["Diagnostics"] as? [String: Any],
              let io = diag["IORegistry"] as? [String: Any] else { return nil }
        return io
    }

    // MARK: - Helpers

    private static func copyString(_ s: Symbols, _ dev: UnsafeMutableRawPointer, _ key: String) -> String {
        s.copyValue(dev, nil, key as CFString)?.takeRetainedValue() as? String ?? ""
    }

    private static func connectionLabel(_ type: Int32) -> String {
        switch type {
        case 1: return "USB"
        case 2, 3: return "Network"
        default: return ""
        }
    }
}
