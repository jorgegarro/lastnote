import AppKit
import SwiftUI

/// Transparency / tint / theme controls. Used both in the status-bar popover and in Settings.
struct AppearanceControls: View {
    @ObservedObject var settings = AppSettings.shared

    private let presets: [String] = ["#1B1F27", "#000000", "#FFFFFF", "#0B3D91", "#1E5631", "#5B2A86", "#8B1E3F", "#C06C00", "#2F4F4F"]

    private var tint: Binding<Color> {
        Binding(get: { Color(nsColor: settings.tintColor) },
                set: { settings.tintColor = NSColor($0).usingColorSpace(.sRGB) ?? NSColor($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Transparent window", isOn: $settings.transparencyEnabled)
                .toggleStyle(.switch)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Opacity")
                        .frame(width: 70, alignment: .leading)
                    Slider(value: $settings.opacity, in: 0.1...1.0)
                    Text("\(Int((settings.opacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("Tint")
                        .frame(width: 70, alignment: .leading)
                    ColorPicker("", selection: tint, supportsOpacity: false)
                        .labelsHidden()
                    ForEach(presets, id: \.self) { hex in
                        let color = NSColor(hex: hex)!
                        Button {
                            settings.tintColor = color
                        } label: {
                            Circle()
                                .fill(Color(nsColor: color))
                                .overlay(Circle().stroke(Color.secondary.opacity(0.6), lineWidth: settings.tintColor.hexString == hex ? 2 : 0.5))
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .help(hex)
                    }
                }
                Toggle("Blur what's behind the window (frosted glass)", isOn: $settings.blurEnabled)
            }
            .disabled(!settings.transparencyEnabled)
            .opacity(settings.transparencyEnabled ? 1 : 0.45)

            Divider()

            HStack {
                Toggle("Glow around the focused area", isOn: $settings.focusGlowEnabled)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: settings.effectiveFocusGlowColor) },
                    set: { settings.focusGlowColor = NSColor($0).usingColorSpace(.sRGB) ?? NSColor($0) }),
                    supportsOpacity: false)
                    .labelsHidden()
                    .disabled(!settings.focusGlowEnabled)
                if settings.focusGlowColor != nil {
                    Button("Auto") { settings.focusGlowColor = nil }
                        .controlSize(.small)
                        .help("White with dark text colours, blue with light")
                }
            }
            HStack {
                Text("Glow strength")
                    .frame(width: 100, alignment: .leading)
                Slider(value: $settings.focusGlowOpacity, in: 0.1...1.0)
                Text("\(Int((settings.focusGlowOpacity * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            .disabled(!settings.focusGlowEnabled)
            .opacity(settings.focusGlowEnabled ? 1 : 0.45)

            Picker("Text colours", selection: $settings.theme) {
                ForEach(ThemeKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if settings.transparencyEnabled && (settings.theme == .dark) == (settings.tintColor.luminance > 0.6) {
                Text("Tip: with a \(settings.tintColor.luminance > 0.6 ? "light" : "dark") tint, the \(settings.theme == .dark ? "Light" : "Dark") text colours are easier to read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EditorSettingsControls: View {
    @ObservedObject var settings = AppSettings.shared

    private static let monospacedFamilies: [String] = NSFontManager.shared.availableFontFamilies.filter { family in
        guard let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12) else { return false }
        return font.isFixedPitch || family.localizedCaseInsensitiveContains("mono")
    }

    var body: some View {
        Form {
            Picker("Font", selection: $settings.fontName) {
                ForEach(Self.monospacedFamilies.contains(settings.fontName) ? Self.monospacedFamilies : [settings.fontName] + Self.monospacedFamilies, id: \.self) {
                    Text($0).tag($0)
                }
            }
            Stepper("Editor size: \(Int(settings.fontSize)) pt", value: $settings.fontSize, in: 8...36)
            Stepper("Console size: \(Int(settings.consoleFontSize)) pt", value: $settings.consoleFontSize, in: 8...36)
            Stepper("Tab width: \(settings.tabWidth)", value: $settings.tabWidth, in: 1...12)
            Toggle("Insert spaces instead of tabs", isOn: $settings.useSpaces)
            Toggle("Word wrap", isOn: $settings.wordWrap)
            Toggle("Show whitespace", isOn: $settings.showWhitespace)
            Toggle("Show line endings", isOn: $settings.showLineEndings)
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceControls()
                .padding(20)
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            EditorSettingsControls()
                .padding(20)
                .tabItem { Label("Editor", systemImage: "text.alignleft") }
        }
        .frame(width: 520, height: 370)
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
