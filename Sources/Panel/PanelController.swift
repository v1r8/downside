import AppKit
import SwiftUI

/// Controla exibição, posicionamento, animação e auto-ocultação do painel.
@MainActor
final class PanelController: ObservableObject {
    /// Com o pin ativo o painel não se esconde sozinho.
    @Published var isPinned = false

    private(set) var isVisible = false

    private let folderMonitor: FolderMonitor
    private var panel: PeekPanel?
    private var watchTimer: Timer?
    private var lastMouseInside = Date()

    init(folderMonitor: FolderMonitor) {
        self.folderMonitor = folderMonitor
    }

    func show(on screen: NSScreen) {
        guard !isVisible else { return }

        let panel = ensurePanel()
        folderMonitor.reload()

        let corner = Prefs.corner
        let frame = targetFrame(size: Prefs.panelSize, corner: corner, screen: screen)

        // Parte ligeiramente "de dentro" do canto, com fade — movimento
        // curto e suave, como os paineis do sistema.
        var start = frame
        let offset: CGFloat = 16
        switch corner {
        case .bottomLeft: start.origin.x -= offset; start.origin.y -= offset
        case .bottomRight: start.origin.x += offset; start.origin.y -= offset
        case .topLeft: start.origin.x -= offset; start.origin.y += offset
        case .topRight: start.origin.x += offset; start.origin.y += offset
        }

        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        lastMouseInside = Date()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }

        startAutoHideWatcher()
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        watchTimer?.invalidate()
        watchTimer = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            panel.orderOut(nil)
        })
    }

    // MARK: - Internals

    private func ensurePanel() -> PeekPanel {
        if let panel { return panel }

        let panel = PeekPanel()
        panel.onClose = { [weak self] in
            Task { @MainActor in self?.hide() }
        }

        let root = FolderPeekView()
            .environmentObject(folderMonitor)
            .environmentObject(self)
        panel.contentView = NSHostingView(rootView: root)

        self.panel = panel
        return panel
    }

    private func targetFrame(size: NSSize, corner: HotCorner, screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let margin: CGFloat = 12
        let width = min(size.width, area.width - 2 * margin)
        let height = min(size.height, area.height - 2 * margin)

        let origin: NSPoint
        switch corner {
        case .bottomLeft:
            origin = NSPoint(x: area.minX + margin, y: area.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: area.maxX - width - margin, y: area.minY + margin)
        case .topLeft:
            origin = NSPoint(x: area.minX + margin, y: area.maxY - height - margin)
        case .topRight:
            origin = NSPoint(x: area.maxX - width - margin, y: area.maxY - height - margin)
        }
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    /// Esconde o painel quando o mouse sai dele por um instante
    /// (mas nunca durante um arrasto e nunca quando fixado).
    private func startAutoHideWatcher() {
        watchTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoHideTick() }
        }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func autoHideTick() {
        guard isVisible, let panel else { return }
        if isPinned {
            lastMouseInside = Date()
            return
        }

        let mouse = NSEvent.mouseLocation
        let inside = panel.frame.insetBy(dx: -24, dy: -24).contains(mouse)
        let dragging = NSEvent.pressedMouseButtons != 0

        if inside || dragging {
            lastMouseInside = Date()
        } else if Date().timeIntervalSince(lastMouseInside) > 0.35 {
            hide()
        }
    }
}
