import AppKit

extension Notification.Name {
    static let peekSelectAll = Notification.Name("dev.downside.peekSelectAll")
}

/// Painel flutuante sem borda que recebe teclado sem ativar o app
/// (estilo Spotlight/Centro de Notificações).
final class PeekPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        // Esc
        if event.keyCode == 53 {
            onClose?()
            return
        }
        // Cmd+A → selecionar tudo no grid
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            NotificationCenter.default.post(name: .peekSelectAll, object: nil)
            return
        }
        super.keyDown(with: event)
    }
}
