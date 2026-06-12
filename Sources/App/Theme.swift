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

    /// Cor própria dos outputs de bulk actions (✨, chips, fundos).
    static var output: Color {
        if let hex = UserDefaults.standard.string(forKey: PrefKey.outputColorHex),
           let color = Color(hex: hex) {
            return color
        }
        return accent
    }

    static var outputIntensity: Double {
        let value = UserDefaults.standard.double(forKey: PrefKey.outputIntensity)
        return (0.35...1.5).contains(value) ? value : 1.0
    }

    static func outputTint(_ base: Double) -> Color {
        output.opacity(min(1, base * outputIntensity))
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
/// Observa as preferências por conta própria (independente do AppState).
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var tick = 0

    private init() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in ThemeStore.shared.bump() }
        }
    }

    func bump() {
        tick &+= 1
    }
}

/// Fundo de pílula "liquid glass": material fino + tinta de destaque.
struct GlassCapsule: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    var tint: Double = 0.6

    var body: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Theme.tint(tint))
        }
    }
}

/// Carta holográfica (estilo carta de Pokémon): indica output de bulk
/// action no deck, com brilho varrendo continuamente.
struct HoloCardBadge: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 2.6) / 2.6)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Theme.outputTint(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.white.opacity(0.75),
                                    Color.cyan.opacity(0.5),
                                    Color.purple.opacity(0.45),
                                    .clear,
                                ],
                                startPoint: UnitPoint(x: phase * 2.4 - 1.4, y: phase * 2.4 - 1.4),
                                endPoint: UnitPoint(x: phase * 2.4 - 0.4, y: phase * 2.4 - 0.4)
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8)
                )
                .frame(width: width, height: height)
                .shadow(color: Theme.output.opacity(0.55), radius: 3)
        }
    }
}

/// Brilho holográfico sutil para sobrepor chips/fundos (outputs).
struct HoloShimmer: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 2.8) / 2.8)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.28),
                            Color.cyan.opacity(0.18),
                            Color.purple.opacity(0.16),
                            .clear,
                        ],
                        startPoint: UnitPoint(x: phase * 2.4 - 1.4, y: 0.2),
                        endPoint: UnitPoint(x: phase * 2.4 - 0.4, y: 0.8)
                    )
                )
                .allowsHitTesting(false)
        }
    }
}

/// Efeito mágico no lugar do título enquanto a IA nomeia a ficha.
struct MagicNamePlaceholder: View {
    let scale: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.6) / 1.6)
            HStack(spacing: 4 * scale) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(Theme.accent)
                    .opacity(0.45 + 0.55 * abs(sin(t * 3.5)))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.08),
                                Theme.tint(0.55),
                                Color.primary.opacity(0.08),
                            ],
                            startPoint: UnitPoint(x: phase * 2.2 - 1.2, y: 0.5),
                            endPoint: UnitPoint(x: phase * 2.2 - 0.2, y: 0.5)
                        )
                    )
                    .frame(width: 88 * scale, height: 9 * scale)
            }
        }
        .help("Nomeando com IA…")
    }
}

/// Botão circular mínimo em vidro tingido (estilo do botão de limpeza,
/// com a cor de destaque das configurações) — só o ícone, sem texto.
struct GlassIconButton: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    let icon: String
    let scale: CGFloat
    var tint: Color?
    var help: String = ""
    var action: () -> Void

    init(
        icon: String,
        scale: CGFloat,
        tint: Color? = nil,
        help: String = "",
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.scale = scale
        self.tint = tint
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22 * scale, height: 22 * scale)
        }
        .buttonStyle(.borderless)
        .background(
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(tint ?? Theme.tint(0.65))
            }
        )
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .help(help)
    }
}
