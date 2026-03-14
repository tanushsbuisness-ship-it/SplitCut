import SwiftUI

// MARK: - Color presets

struct MaterialColorPreset: Identifiable {
    let id: String          // unique slug
    let name: String
    let hex: String         // base color stored on the model
    let grainHex: String?   // nil = no grain (MDF, melamine, custom)

    var color: Color      { Color(hex: hex) }
    var grainColor: Color? { grainHex.map { Color(hex: $0) } }
    var hasGrain: Bool    { grainHex != nil }
}

extension MaterialColorPreset {
    static let all: [MaterialColorPreset] = [
        .init(id: "birch",    name: "Birch",    hex: "#E8D5A3", grainHex: "#C4A96A"),
        .init(id: "maple",    name: "Maple",    hex: "#F0D9A0", grainHex: "#D4B870"),
        .init(id: "oak",      name: "Oak",      hex: "#C9A96B", grainHex: "#A07838"),
        .init(id: "pine",     name: "Pine",     hex: "#E6C880", grainHex: "#C4A040"),
        .init(id: "cherry",   name: "Cherry",   hex: "#B5603A", grainHex: "#8A3E20"),
        .init(id: "walnut",   name: "Walnut",   hex: "#6B3A1F", grainHex: "#3D200E"),
        .init(id: "mdf",      name: "MDF",      hex: "#C8C0A8", grainHex: nil),
        .init(id: "melamine", name: "Melamine", hex: "#F0EEE8", grainHex: nil),
    ]

    static func preset(for hex: String) -> MaterialColorPreset? {
        all.first { $0.hex.uppercased() == hex.uppercased() }
    }

    /// Default color hex (birch) — used as model property default
    static let defaultHex = "#E8D5A3"
}

// MARK: - Color ↔ hex helpers

extension Color {

    /// Create a Color from a 6-digit hex string like "#E8D5A3" or "E8D5A3".
    init(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else {
            self = .secondary; return
        }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }

    /// Convert to #RRGGBB hex string. Uses `getRed` which handles wide-gamut correctly.
    func toHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}

// MARK: - Picker view

/// Horizontal swatch row for picking a material color / texture.
/// Drop this inside a `Form` `Section` for consistent spacing.
struct MaterialColorPicker: View {

    @Binding var colorHex: String
    @State private var showingCustomPicker = false

    private var isCustom: Bool {
        MaterialColorPreset.preset(for: colorHex) == nil
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(MaterialColorPreset.all) { preset in
                    presetSwatch(preset)
                }
                customSwatch
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
    }

    // MARK: Preset swatch

    @ViewBuilder
    private func presetSwatch(_ preset: MaterialColorPreset) -> some View {
        let selected = colorHex.uppercased() == preset.hex.uppercased()
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(preset.color)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                // Grain hint overlay
                if let gc = preset.grainColor {
                    GrainIndicatorView(color: gc)
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                }
            }
            .overlay(
                Circle()
                    .stroke(selected ? Color.primary : Color.clear, lineWidth: 2.5)
                    .padding(-1)
            )
            Text(preset.name)
                .font(.system(size: 9, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .onTapGesture { colorHex = preset.hex }
        .accessibilityLabel(preset.name + (selected ? ", selected" : ""))
    }

    // MARK: Custom swatch

    private var customSwatch: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(isCustom ? Color(hex: colorHex) : Color(.systemGray4))
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                if !isCustom {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.systemGray))
                }
            }
            .overlay(
                Circle()
                    .stroke(isCustom ? Color.primary : Color.clear, lineWidth: 2.5)
                    .padding(-1)
            )
            .onTapGesture { showingCustomPicker = true }
            Text("Custom")
                .font(.system(size: 9, weight: isCustom ? .semibold : .regular))
                .foregroundStyle(isCustom ? .primary : .secondary)
        }
        .sheet(isPresented: $showingCustomPicker) {
            NavigationStack {
                Form {
                    ColorPicker("Pick a color", selection: Binding(
                        get: { Color(hex: colorHex) },
                        set: { colorHex = $0.toHex() }
                    ), supportsOpacity: false)
                }
                .navigationTitle("Custom Color")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingCustomPicker = false }
                    }
                }
            }
            .presentationDetents([.height(180)])
        }
    }
}

// MARK: - Grain indicator (tiny wavy lines for swatch preview)

/// Draws 5 subtle wavy horizontal lines to hint at wood grain.
struct GrainIndicatorView: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            for i in 0..<5 {
                let y = size.height * CGFloat(i) / 4
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addCurve(
                    to: CGPoint(x: size.width, y: y),
                    control1: CGPoint(x: size.width * 0.3, y: y - 1.5),
                    control2: CGPoint(x: size.width * 0.7, y: y + 1.5)
                )
                context.stroke(path, with: .color(color.opacity(0.55)), lineWidth: 0.8)
            }
        }
    }
}

#Preview("Color Picker") {
    Form {
        Section("Material Color") {
            MaterialColorPicker(colorHex: .constant("#C9A96B"))
        }
    }
}
