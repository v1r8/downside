import SwiftUI
import AppKit

/// Cor e intensidade dos destaques do app, ajustáveis nas
/// configurações. `tint(x)` substitui os antigos `accentColor.opacity(x)`
/// respeitando a intensidade escolhida.
enum Theme {
    static var accent: Color {
        if let hex = UserDefaults.standard.string(forKey: PrefKey.accentColorHex),
           let color = Color(hex: hex) {
            return color
        }
        return .accentColor
    }

    static var intensity: Double {
        let value = UserDefaults.standard.double(forKey: PrefKey.accentIntensity)
        return (0.35...1.0).contains(value) ? value : 1.0
    }

    static func tint(_ base: Double) -> Color {
        accent.opacity(min(1, base * intensity))
    }
}

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "%02X%02X%02X",
            Int(color.redComponent * 255),
            Int(color.greenComponent * 255),
            Int(color.blueComponent * 255)
        )
    }
}

/// Notifica as views quando cor/intensidade dos destaques mudam —
/// Theme.tint é estático, então sem isto a UI só atualizava ao reabrir.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var tick = 0

    func bump() {
        tick &+= 1
    }
}

/// Fundo de pílula "liquid glass": material fino + tinta de destaque.
struct GlassCapsule: View {
    var tint: Double = 0.6

    var body: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Theme.tint(tint))
        }
    }
}
