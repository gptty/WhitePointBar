import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    private let presets: [(String, Double)] = [
        ("D50", 5000), ("D55", 5500), ("D65", 6500), ("D75", 7500),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("White point") {
                valueRow("Temperature", "\(Int(model.kelvin)) K")
                Slider(value: $model.kelvin, in: AppModel.kelvinRange, step: 50)
                HStack(spacing: 6) {
                    ForEach(presets, id: \.0) { name, k in
                        Button(name) { model.kelvin = k }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(abs(model.kelvin - k) < 1 ? Color.accentColor : nil)
                    }
                    Spacer()
                    Button("Reset") { model.resetWhitePoint() }
                        .controlSize(.small)
                        .disabled(model.whitePoint.isNeutral)
                }
                valueRow("White level", "\(Int((model.whiteLevel * 100).rounded()))%")
                Slider(value: $model.whiteLevel, in: AppModel.whiteLevelRange)
            }

            Divider()

            section("Grayscale filter") {
                Toggle("Enabled", isOn: $model.grayscaleEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                valueRow("Intensity", "\(Int((model.grayscaleIntensity * 100).rounded()))%")
                Slider(value: $model.grayscaleIntensity, in: 0...1)
                    .disabled(!model.grayscaleEnabled)
                if !model.filters.isAvailable {
                    Text("Color-filter API not found on this macOS; using preference fallback.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            HStack {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                    .controlSize(.small)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { model.refreshFromSystem() }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
