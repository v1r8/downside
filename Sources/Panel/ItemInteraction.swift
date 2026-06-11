import SwiftUI
import AppKit

/// Camada AppKit sobre cada item do painel. Substitui os gestos SwiftUI
/// para reproduzir o comportamento do Finder com fidelidade:
///  - seleção no mouse-down (deixando o grupo intacto para arrasto)
///  - arrasto nativo com TODOS os arquivos selecionados
///  - clique duplo, menu de contexto e hover (para o preview).
struct ItemInteraction: NSViewRepresentable {
    var onMouseDown: (NSEvent.ModifierFlags) -> Void
    var onClickUp: (NSEvent.ModifierFlags) -> Void
    var onDoubleClick: () -> Void
    var dragURLs: () -> [URL]
    var menu: () -> NSMenu?
    var onHover: (Bool, NSRect) -> Void
    var onDragStarted: () -> Void = {}
    var onDragEnded: () -> Void = {}

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        configure(view)
        return view
    }

    func updateNSView(_ view: InteractionView, context: Context) {
        configure(view)
    }

    private func configure(_ view: InteractionView) {
        view.onMouseDown = onMouseDown
        view.onClickUp = onClickUp
        view.onDoubleClick = onDoubleClick
        view.dragURLs = dragURLs
        view.menuProvider = menu
        view.onHover = onHover
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
    }
}

final class InteractionView: NSView, NSDraggingSource {
    var onMouseDown: ((NSEvent.ModifierFlags) -> Void)?
    var onClickUp: ((NSEvent.ModifierFlags) -> Void)?
    var onDoubleClick: (() -> Void)?
    var dragURLs: (() -> [URL])?
    var menuProvider: (() -> NSMenu?)?
    var onHover: ((Bool, NSRect) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var downEvent: NSEvent?
    private var didDrag = false

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        guard let window else { return }
        let screenRect = window.convertToScreen(convert(bounds, to: nil))
        onHover?(true, screenRect)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false, .zero)
    }

    // MARK: - Cliques e arrasto

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        didDrag = false
        onMouseDown?(event.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downEvent, !didDrag else { return }
        let dx = event.locationInWindow.x - downEvent.locationInWindow.x
        let dy = event.locationInWindow.y - downEvent.locationInWindow.y
        guard (dx * dx + dy * dy).squareRoot() > 4 else { return }
        didDrag = true
        beginDrag(with: downEvent)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downEvent = nil }
        guard !didDrag else { return }
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else if event.clickCount == 1 {
            onClickUp?(event.modifierFlags)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    private func beginDrag(with event: NSEvent) {
        let urls = dragURLs?() ?? []
        guard !urls.isEmpty else { return }

        let location = convert(event.locationInWindow, from: nil)
        let side: CGFloat = 48
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            // Leve "leque" nos primeiros itens para o arrasto múltiplo
            // ficar visível.
            let offset = CGFloat(min(index, 6)) * 3
            item.setDraggingFrame(
                NSRect(
                    x: location.x - side / 2 + offset,
                    y: location.y - side / 2 - offset,
                    width: side,
                    height: side
                ),
                contents: icon
            )
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .move, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragStarted?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onDragEnded?()
    }
}

/// NSMenuItem que executa uma closure (para os menus de contexto).
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) não suportado")
    }

    @objc private func run() {
        handler()
    }
}
