import AppKit
import CoreGraphics

/// Shifts each display's white point by scaling its gamma (transfer) tables.
///
/// The baseline table is whatever ColorSync loaded (so calibrated external
/// monitors keep their calibration); we multiply each channel by the RGB of the
/// target colour temperature, normalised so 6500 K (D65) == no change, and by
/// the white level. Quartz drops these tables when the process exits, so the
/// app must stay running for the effect to persist.
final class WhitePointController {
    private struct Baseline {
        var r: [CGGammaValue]
        var g: [CGGammaValue]
        var b: [CGGammaValue]
    }

    private var baselines: [CGDirectDisplayID: Baseline] = [:]
    private(set) var kelvin = 6500.0
    private(set) var level = 1.0
    private var applied = false
    private var timer: Timer?

    var isNeutral: Bool { abs(kelvin - 6500) < 1 && level >= 0.999 }

    init() {
        recaptureBaselines()

        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
            let me = Unmanaged<WhitePointController>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { me.displaysChanged() }
        }, Unmanaged.passUnretained(self).toOpaque())

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.displaysChanged()
            }
        }

        // Other software (Night Shift, display reconnects, games) can stomp on
        // gamma tables; cheaply re-assert ours.
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.reapply()
        }
    }

    func set(kelvin: Double, level: Double) {
        self.kelvin = kelvin
        self.level = level
        reapply()
    }

    func reapply() {
        if isNeutral {
            if applied {
                CGDisplayRestoreColorSyncSettings()
                applied = false
            }
            return
        }

        let (r, g, b) = Self.channelScale(forKelvin: kelvin)
        let sr = Float(r * level), sg = Float(g * level), sb = Float(b * level)

        for display in Self.activeDisplays() {
            if baselines[display] == nil, let base = Self.readTable(display) {
                baselines[display] = base
            }
            if let base = baselines[display], !base.r.isEmpty {
                let rr = base.r.map { $0 * sr }
                let gg = base.g.map { $0 * sg }
                let bb = base.b.map { $0 * sb }
                CGSetDisplayTransferByTable(display, UInt32(rr.count), rr, gg, bb)
            } else {
                CGSetDisplayTransferByFormula(display, 0, sr, 1, 0, sg, 1, 0, sb, 1)
            }
        }
        applied = true
    }

    private func displaysChanged() {
        recaptureBaselines()
        reapply()
    }

    private func recaptureBaselines() {
        CGDisplayRestoreColorSyncSettings()
        applied = false
        baselines.removeAll()
        for display in Self.activeDisplays() {
            if let base = Self.readTable(display) { baselines[display] = base }
        }
    }

    // MARK: - Helpers

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private static func readTable(_ display: CGDirectDisplayID) -> Baseline? {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0 else { return nil }
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = [CGGammaValue](repeating: 0, count: Int(capacity))
        var b = [CGGammaValue](repeating: 0, count: Int(capacity))
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &r, &g, &b, &sampleCount) == .success,
              sampleCount > 1 else { return nil }
        let n = Int(sampleCount)
        return Baseline(r: Array(r.prefix(n)), g: Array(g.prefix(n)), b: Array(b.prefix(n)))
    }

    /// Per-channel multipliers for a colour temperature, normalised to 6500 K.
    static func channelScale(forKelvin k: Double) -> (Double, Double, Double) {
        let ref = blackbodyRGB(6500)
        let c = blackbodyRGB(k)
        return (min(1, c.0 / ref.0), min(1, c.1 / ref.1), min(1, c.2 / ref.2))
    }

    /// Tanner Helland's blackbody approximation (1000–40000 K), 0…1 per channel.
    private static func blackbodyRGB(_ kelvin: Double) -> (Double, Double, Double) {
        let t = min(max(kelvin, 1000), 40000) / 100
        let r, g, b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
        }
        if t >= 66 {
            b = 255
        } else if t <= 19 {
            b = 0
        } else {
            b = 138.5177312231 * log(t - 10) - 305.0447927307
        }
        func clamp(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        return (clamp(r), clamp(g), max(clamp(b), 0.001))
    }
}
