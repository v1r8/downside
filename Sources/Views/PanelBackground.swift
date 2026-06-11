import SwiftUI
import AppKit

/// Fundo do painel. No macOS Tahoe (compilando com Xcode 26+) usa o
/// Liquid Glass nativo; em sistemas/SDKs anteriores cai para o material
/// translúcido padrão de paineis do sistema.
struct PanelBackground: View {
    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            legacyMaterial
        }
        #else
        legacyMaterial
        #endif
    }

    private var legacyMaterial: some View {
        VisualEffectView(material: .popover)
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// Abre a janela de Configurações a partir de contextos fora de cena
/// SwiftUI (ex.: botão dentro do painel).
enum SettingsOpener {
    @MainActor
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
