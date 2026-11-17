import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    private enum Keys {
        static let kelvin = "kelvin"
        static let whiteLevel = "whiteLevel"
        static let intensity = "grayscaleIntensity"
    }

    static let neutralKelvin = 6500.0
    static let kelvinRange: ClosedRange<Double> = 2000...10000
    static let whiteLevelRange: ClosedRange<Double> = 0.3...1.0

    let whitePoint = WhitePointController()
    let filters = ColorFilterBridge.shared

    private let defaults = UserDefaults.standard
    private var syncing = false
    private var intensityWork: DispatchWorkItem?

    // MARK: White point (gamma-table based, applied while the app runs)

    @Published var kelvin: Double {
        didSet {
            guard !syncing else { return }
            defaults.set(kelvin, forKey: Keys.kelvin)
            applyWhitePoint()
        }
    }

    @Published var whiteLevel: Double {
        didSet {
            guard !syncing else { return }
            defaults.set(whiteLevel, forKey: Keys.whiteLevel)
            applyWhitePoint()
        }
    }

    // MARK: Grayscale color filter (system Accessibility setting)

    @Published var grayscaleEnabled: Bool {
        didSet {
            guard !syncing else { return }
            filters.setGrayscale(enabled: grayscaleEnabled)
            if grayscaleEnabled { scheduleIntensityWrite() }
        }
    }

    @Published var grayscaleIntensity: Double {
        didSet {
            guard !syncing else { return }
            defaults.set(grayscaleIntensity, forKey: Keys.intensity)
            scheduleIntensityWrite()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !syncing, launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("WhitePointBar: launch-at-login change failed: \(error)")
                syncing = true
                launchAtLogin = SMAppService.mainApp.status == .enabled
                syncing = false
            }
        }
    }

    var menuBarSymbol: String {
        if grayscaleEnabled { return "circle.lefthalf.filled" }
        if !whitePoint.isNeutral { return "sun.max.fill" }
        return "sun.max"
    }

    private init() {
        defaults.register(defaults: [
            Keys.kelvin: Self.neutralKelvin,
            Keys.whiteLevel: 1.0,
            Keys.intensity: 1.0,
        ])
        kelvin = defaults.double(forKey: Keys.kelvin)
        whiteLevel = defaults.double(forKey: Keys.whiteLevel)
        grayscaleEnabled = ColorFilterBridge.shared.isGrayscaleEnabled()
        grayscaleIntensity = ColorFilterBridge.shared.readIntensity()
            ?? defaults.double(forKey: Keys.intensity)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        applyWhitePoint()
    }

    /// Pull current state from the system (e.g. if changed in System Settings).
    func refreshFromSystem() {
        syncing = true
        defer { syncing = false }
        if filters.isAvailable { grayscaleEnabled = filters.isGrayscaleEnabled() }
        if let v = filters.readIntensity() { grayscaleIntensity = v }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func resetWhitePoint() {
        kelvin = Self.neutralKelvin
        whiteLevel = 1.0
    }

    private func applyWhitePoint() {
        whitePoint.set(kelvin: kelvin, level: whiteLevel)
        objectWillChange.send() // menu bar icon depends on neutrality
    }

    private func scheduleIntensityWrite() {
        intensityWork?.cancel()
        let value = grayscaleIntensity
        let enabled = grayscaleEnabled
        let work = DispatchWorkItem { [filters] in
            filters.setIntensity(value, refreshEnabled: enabled)
        }
        intensityWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
}
