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

/// Alça que move a janela (performDrag) e avisa quando o arrasto
/// termina — usado pelo snap na grade da tela.
struct WindowDragHandle: NSViewRepresentable {
    var onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: DragHandleView, context: Context) {
        view.onDragEnded = onDragEnded
    }
}

final class DragHandleView: NSView {
    var onDragEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        // performDrag só retorna quando o arrasto acaba.
        onDragEnded?()
    }
}
