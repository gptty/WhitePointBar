import Foundation

/// Bridge to the system Accessibility → Display → Color Filters setting.
///
/// Apple exposes no public API for this, so we resolve private symbols from
/// MediaAccessibility / UniversalAccess at runtime with dlsym. Every symbol is
/// optional: if one is missing on a given macOS version we fall back to writing
/// the `com.apple.mediaaccessibility` preferences directly.
///
/// Run `WhitePointBar --probe` (or scripts/probe.sh) to see what resolved.
final class ColorFilterBridge {
    static let shared = ColorFilterBridge()

    static let domain = "com.apple.mediaaccessibility" as CFString
    /// Category 1 = the user-facing "Color Filters" filter.
    static let systemCategory: Int32 = 1
    /// Filter type bitmask: 1 grayscale, 2 red/green, 4 green/red, 8 blue/yellow, 16 tint.
    static let grayscaleType: Int32 = 1

    private enum PrefKey {
        static let enabled = "__Color__-MADisplayFilterCategoryEnabled"
        static let type = "__Color__-MADisplayFilterType"
    }

    /// Preference keys tried for filter intensity. Override with:
    ///   defaults write <bundle id> GrayscaleIntensityKey "<key>"
    /// (scripts/probe.sh --diff tells you the exact key on your macOS version.)
    static let defaultIntensityKeys = [
        "__Color__-MADisplayFilterIntensity",
        "__Color__-MADisplayFilterGrayscaleIntensity",
    ]

    private typealias GetEnabledFn = @convention(c) (Int32) -> Bool
    private typealias SetEnabledFn = @convention(c) (Int32, Bool) -> Void
    private typealias GetTypeFn = @convention(c) (Int32) -> Int32
    private typealias SetTypeFn = @convention(c) (Int32, Int32) -> Void
    private typealias UAStartFn = @convention(c) (Int32) -> Void

    private let getEnabled: GetEnabledFn?
    private let setEnabled: SetEnabledFn?
    private let getType: GetTypeFn?
    private let setType: SetTypeFn?
    private let uaStart: UAStartFn?

    var isAvailable: Bool { setEnabled != nil && setType != nil }

    private init() {
        let ma = dlopen("/System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility", RTLD_NOW)
        let ua = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess", RTLD_NOW)
        getEnabled = Self.symbol(ma, "MADisplayFilterPrefGetCategoryEnabled")
        setEnabled = Self.symbol(ma, "MADisplayFilterPrefSetCategoryEnabled")
        getType = Self.symbol(ma, "MADisplayFilterPrefGetType")
        setType = Self.symbol(ma, "MADisplayFilterPrefSetType")
        uaStart = Self.symbol(ua, "_UniversalAccessDStart")
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle, let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }

    // MARK: - Grayscale on/off

    func isGrayscaleEnabled() -> Bool {
        let on = getEnabled?(Self.systemCategory) ?? readPref(PrefKey.enabled).map { $0 != 0 } ?? false
        let type = getType?(Self.systemCategory) ?? readPref(PrefKey.type).map { Int32($0) } ?? 0
        return on && type == Self.grayscaleType
    }

    func setGrayscale(enabled: Bool) {
        if let setType, let setEnabled {
            if enabled { setType(Self.systemCategory, Self.grayscaleType) }
            setEnabled(Self.systemCategory, enabled)
        } else {
            if enabled { writePref(PrefKey.type, Double(Self.grayscaleType)) }
            writePref(PrefKey.enabled, enabled ? 1 : 0)
        }
        commit()
    }

    // MARK: - Intensity

    func intensityKeys() -> [String] {
        if let override = UserDefaults.standard.string(forKey: "GrayscaleIntensityKey"), !override.isEmpty {
            return [override]
        }
        var keys = Self.defaultIntensityKeys
        // Prefer any grayscale-specific intensity key the system already uses.
        if let existing = CFPreferencesCopyKeyList(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] {
            for k in existing
            where k.localizedCaseInsensitiveContains("intensity")
                && k.localizedCaseInsensitiveContains("gray")
                && !keys.contains(k) {
                keys.insert(k, at: 0)
            }
        }
        return keys
    }

    func readIntensity() -> Double? {
        for key in intensityKeys() {
            if let v = readPref(key) { return min(max(v, 0), 1) }
        }
        return nil
    }

    func setIntensity(_ value: Double, refreshEnabled: Bool) {
        let v = min(max(value, 0), 1)
        for key in intensityKeys() { writePref(key, v) }
        // Re-asserting the enabled state nudges the filter to re-read prefs.
        if refreshEnabled, let setEnabled { setEnabled(Self.systemCategory, true) }
        commit()
    }

    // MARK: - Prefs plumbing

    private func readPref(_ key: String) -> Double? {
        (CFPreferencesCopyAppValue(key as CFString, Self.domain) as? NSNumber)?.doubleValue
    }

    private func writePref(_ key: String, _ value: Double) {
        CFPreferencesSetAppValue(key as CFString, value as CFNumber, Self.domain)
    }

    private func commit() {
        CFPreferencesAppSynchronize(Self.domain)
        uaStart?(0)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in ["com.apple.mediaaccessibility.displayFilterSettingsChanged",
                     "com.apple.universalaccess.displayFilterSettingsChanged"] {
            CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
        }
    }

    // MARK: - Diagnostics

    func printProbe() {
        func mark(_ ok: Bool) -> String { ok ? "✓" : "✗" }
        print("WhitePointBar probe")
        print("  \(mark(getEnabled != nil)) MADisplayFilterPrefGetCategoryEnabled")
        print("  \(mark(setEnabled != nil)) MADisplayFilterPrefSetCategoryEnabled")
        print("  \(mark(getType != nil)) MADisplayFilterPrefGetType")
        print("  \(mark(setType != nil)) MADisplayFilterPrefSetType")
        print("  \(mark(uaStart != nil)) _UniversalAccessDStart")
        print("  grayscale enabled: \(isGrayscaleEnabled())")
        print("  intensity keys tried: \(intensityKeys())")
        print("  intensity read: \(readIntensity().map { String($0) } ?? "none")")
        if let keys = CFPreferencesCopyKeyList(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] {
            print("  \(Self.domain) keys:")
            for k in keys.sorted() { print("    \(k) = \(readPref(k).map { String($0) } ?? "…")") }
        }
    }
}
