import AppKit
import SwiftUI

struct FileStack: Identifiable, Equatable {
    let id: UUID
    var urls: [URL]

    init(id: UUID = UUID(), urls: [URL] = []) {
        self.id = id
        self.urls = urls
    }
}

/// Janela que escurece levemente a tela atrás do painel no modo
/// minimalista. Clicar nela fecha o painel.
final class DimmerWindow: NSWindow {
    var onClick: (() -> Void)?

    override var canBecomeKey: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.28)
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hasShadow = false
        animationBehavior = .none
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// Controla exibição, posicionamento, animação e auto-ocultação do painel.
@MainActor
final class PanelController: ObservableObject {
    /// Com o pin ativo o painel não se esconde sozinho.
    @Published var isPinned = false

    /// Preview flutuante de hover (compartilhado com a view do painel).
    let preview = PreviewController()

    /// Pilhas temporárias de arquivos (até 3, lado a lado) — sobrevivem
    /// a abrir e fechar o painel, até serem limpas.
    @Published var stacks: [FileStack] = []

    static let maxStacks = 3

    /// True enquanto um arrasto iniciado no painel está em andamento;
    /// usado para exibir a zona de soltar da pilha.
    @Published var isDraggingFromPanel = false

    private(set) var isVisible = false

    private let folderMonitor: FolderMonitor
    private var panel: PeekPanel?
    private var dimmer: DimmerWindow?
    private var watchTimer: Timer?
    private var outsideClickMonitor: Any?
    private var lastMouseInside = Date()
    private var lastCorner: HotCorner = .bottomRight
    private var lastScreen: NSScreen?

    init(folderMonitor: FolderMonitor) {
        self.folderMonitor = folderMonitor
    }

    func show(on screen: NSScreen, corner: HotCorner? = nil) {
        guard !isVisible else { return }

        let corner = corner ?? preferredCorner()
        lastCorner = corner
        lastScreen = screen

        let panel = ensurePanel()
        folderMonitor.reload()

        let mode = Prefs.viewMode
        if mode == .minimal {
            showDimmer(on: screen)
        }

        let frame = targetFrame(size: size(for: mode), corner: corner, screen: screen)

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

        // Clique em qualquer outro app/área fora do painel fecha.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { _ in
            Task { @MainActor in
                AppState.shared.panelController.handleOutsideClick()
            }
        }
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        watchTimer?.invalidate()
        watchTimer = nil
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        preview.dismiss()
        hideDimmer()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            panel.orderOut(nil)
        })
    }

    /// Reaplica modo de exibição/tamanho com o painel aberto (chamado
    /// quando as preferências mudam ou o modo é trocado pelo cabeçalho).
    func refreshAppearance() {
        guard isVisible, let panel, let screen = lastScreen else { return }

        let mode = Prefs.viewMode
        if mode == .minimal {
            showDimmer(on: screen)
        } else {
            hideDimmer()
        }

        let frame = targetFrame(size: size(for: mode), corner: lastCorner, screen: screen)
        // Compara apenas o tamanho: depois de um redimensionamento manual
        // o painel pode estar em outra posição, e não deve ser "puxado"
        // de volta ao canto enquanto está aberto.
        guard frame.size != panel.frame.size, !panel.inLiveResize else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Pilhas temporárias

    var hasStacks: Bool { !stacks.isEmpty }

    /// Adiciona à pilha indicada; com `id` nulo cria uma pilha nova
    /// (ou usa a última, se já houver 3).
    func addToStack(_ id: UUID?, url: URL) {
        if let id, let index = stacks.firstIndex(where: { $0.id == id }) {
            if !stacks[index].urls.contains(url) {
                stacks[index].urls.append(url)
            }
        } else if stacks.count < Self.maxStacks {
            stacks.append(FileStack(urls: [url]))
        } else if let last = stacks.indices.last, !stacks[last].urls.contains(url) {
            stacks[last].urls.append(url)
        }
    }

    func removeFromStack(_ id: UUID, url: URL) {
        guard let index = stacks.firstIndex(where: { $0.id == id }) else { return }
        stacks[index].urls.removeAll { $0 == url }
        if stacks[index].urls.isEmpty {
            stacks.remove(at: index)
        }
    }

    func clearStack(_ id: UUID) {
        stacks.removeAll { $0.id == id }
    }

    // MARK: - Internals

    private func preferredCorner() -> HotCorner {
        let corners = Prefs.corners
        if corners.contains(.bottomRight) { return .bottomRight }
        return HotCorner.allCases.first(where: { corners.contains($0) }) ?? .bottomRight
    }

    private func size(for mode: ViewMode) -> NSSize {
        // Tamanho ajustado manualmente pelo usuário tem prioridade.
        if let saved = Prefs.savedPanelSize(for: mode) {
            return saved
        }
        let scale = Prefs.uiScale
        let base: NSSize
        switch mode {
        case .grid: base = Prefs.panelSize
        case .list: base = NSSize(width: 460, height: 500)
        case .minimal: base = NSSize(width: 360, height: 540)
        }
        return NSSize(width: base.width * scale, height: base.height * scale)
    }

    private func ensurePanel() -> PeekPanel {
        if let panel { return panel }

        let panel = PeekPanel()
        panel.onClose = { [weak self] in
            Task { @MainActor in self?.hide() }
        }

        // Redimensionável pelas bordas/cantos, com memória por modo.
        panel.styleMask.insert(.resizable)
        panel.minSize = NSSize(width: 300, height: 240)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            Task { @MainActor in
                guard let panel else { return }
                Prefs.savePanelSize(panel.frame.size, for: Prefs.viewMode)
            }
        }

        let root = FolderPeekView()
            .environmentObject(folderMonitor)
            .environmentObject(self)
        panel.contentView = NSHostingView(rootView: root)

        self.panel = panel
        return panel
    }

    private func showDimmer(on screen: NSScreen) {
        let window: DimmerWindow
        if let dimmer {
            window = dimmer
        } else {
            window = DimmerWindow()
            window.onClick = { [weak self] in
                Task { @MainActor in self?.hide() }
            }
            dimmer = window
        }

        window.setFrame(screen.frame, display: false)
        guard !window.isVisible || window.alphaValue < 1 else { return }
        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            window.animator().alphaValue = 1
        }
    }

    private func hideDimmer() {
        guard let dimmer, dimmer.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            dimmer.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, let dimmer = self.dimmer else { return }
                // Só remove se ninguém voltou a precisar dele no meio do fade.
                if dimmer.alphaValue == 0 {
                    dimmer.orderOut(nil)
                }
            }
        })
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

    /// Esconde o painel quando o mouse se afasta dele além da margem
    /// configurada (mas nunca durante um arrasto e nunca quando fixado).
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
        if isPinned || !Prefs.autoHideEnabled {
            lastMouseInside = Date()
            return
        }

        let mouse = NSEvent.mouseLocation
        let margin = Prefs.hideMargin
        let inside = panel.frame.insetBy(dx: -margin, dy: -margin).contains(mouse)
            || preview.frameContains(mouse)
        let dragging = NSEvent.pressedMouseButtons != 0

        if inside || dragging {
            lastMouseInside = Date()
        } else if Date().timeIntervalSince(lastMouseInside) > 0.6 {
            hide()
        }
    }

    /// Clique global fora do painel (e fora do preview) fecha o painel.
    func handleOutsideClick() {
        guard isVisible, !isPinned, let panel else { return }
        let mouse = NSEvent.mouseLocation
        guard !panel.frame.contains(mouse), !preview.frameContains(mouse) else { return }
        hide()
    }
}
