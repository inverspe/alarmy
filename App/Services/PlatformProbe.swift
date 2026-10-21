import Foundation

/// Read-only checks of how iOS sees this app, written to the troubleshooting log.
/// Uses private LaunchServices / Security symbols looked up at runtime; every lookup
/// is guarded, so a missing symbol only produces "unavailable".
enum PlatformProbe {
    static let criticalAlerts = "com.apple.developer.usernotifications.critical-alerts"

    /// What LaunchServices recorded for this app at install time.
    static func launchServicesRecord() -> String {
        guard let id = Bundle.main.bundleIdentifier,
              let type = NSClassFromString("LSApplicationProxy") as? NSObject.Type else { return "LS: unavailable" }
        let selector = NSSelectorFromString("applicationProxyForIdentifier:")
        guard type.responds(to: selector),
              let proxy = type.perform(selector, with: id)?.takeUnretainedValue() as? NSObject else { return "LS: no record" }
        var parts: [String] = []
        for key in ["applicationType", "teamID", "profileValidated"] where proxy.responds(to: NSSelectorFromString(key)) {
            parts.append("\(key)=\(proxy.value(forKey: key).map { "\($0)" } ?? "nil")")
        }
        if proxy.responds(to: NSSelectorFromString("entitlements")) {
            let entitlements = proxy.value(forKey: "entitlements") as? [String: Any]
            parts.append("entitlements=[\(entitlements?.keys.sorted().joined(separator: ", ") ?? "nil")]")
        }
        return "LS: " + parts.joined(separator: " ")
    }

    /// Whether the running process's code signature carries `key`.
    static func runtimeEntitlement(_ key: String) -> String {
        typealias Create = @convention(c) (CFAllocator?) -> UnsafeRawPointer?
        typealias Copy = @convention(c) (UnsafeRawPointer, CFString, UnsafeMutableRawPointer?) -> UnsafeRawPointer?
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let createSymbol = dlsym(defaultHandle, "SecTaskCreateFromSelf"),
              let copySymbol = dlsym(defaultHandle, "SecTaskCopyValueForEntitlement") else { return "runtime: unavailable" }
        let create = unsafeBitCast(createSymbol, to: Create.self)
        let copy = unsafeBitCast(copySymbol, to: Copy.self)
        guard let task = create(nil) else { return "runtime: no task" }
        defer { Unmanaged<AnyObject>.fromOpaque(task).release() }
        guard let value = copy(task, key as CFString, nil) else { return "runtime: \(key) absent" }
        return "runtime: \(key)=\(Unmanaged<AnyObject>.fromOpaque(value).takeRetainedValue())"
    }
}
