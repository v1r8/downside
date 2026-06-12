import AppKit
import SwiftUI
import QuickLookThumbnailing
import PDFKit
import AVFoundation

enum PreviewContent {
    /// Renderização Quick Look (imagem, e formatos sem modo interativo).
    case image(NSImage)
    /// Conteúdo de pastas: primeiros itens + total.
    case folder(children: [URL], total: Int)
    /// PDF com rolagem de páginas (PDFKit).
    case pdf(URL)
    /// Áudio com player que permanece na tela até ser fechado.
    case audio(URL)
    /// Texto editável com salvamento automático.
    case text(URL)
    /// CSV/TSV exibido como tabela.
    case table(URL)
    /// Evento de calendário (.ics) com botão de adicionar à Agenda.
    case event(URL)
    /// Link da web (.webloc) com arte própria.
    case link(URL)
    /// Sem renderização disponível: ícone grande do arquivo.
    case icon

    /// Conteúdos interativos recebem mouse (rolagem, edição, player).
    var isInteractive: Bool {
        switch self {
        case .pdf, .audio, .text, .table, .event: return true
        case .image, .folder, .icon, .link: return false
        }
    }

    /// Nenhum conteúdo nasce fixado: o player de áudio só fixa quando
    /// o usuário dá play (aí sim sobrevive até o X).
    var isSticky: Bool { false }

    /// Categoria usada para o ajuste de tamanho por tipo de arquivo.
    var sizeCategory: PreviewCategory {
        switch self {
        case .image, .icon: return .image
        case .pdf: return .pdf
        case .text, .event, .link: return .text
        case .table: return .table
        case .folder: return .folder
        case .audio: return .audio
        }
    }
}

enum PreviewBuilder {
    private static let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "flac", "aiff", "ogg"]
    private static let textExtensions: Set<String> = [
        "txt", "md", "json", "xml", "log", "yml", "yaml", "csv-template",
        "swift", "js", "ts", "py", "html", "css", "sh", "rtf-plain",
    ]

    static func build(for item: FileItem) async -> PreviewContent {
        if item.isDirectory {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: item.url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            let sorted = children.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            return .folder(children: Array(sorted.prefix(8)), total: children.count)
        }

        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return .pdf(item.url)
        case _ where audioExtensions.contains(ext):
            return .audio(item.url)
        case "csv", "tsv":
            return .table(item.url)
        case "ics":
            return .event(item.url)
        case "webloc":
            if let plist = try? PropertyListSerialization.propertyList(
                from: Data(contentsOf: item.url), format: nil
            ) as? [String: Any],
               let raw = plist["URL"] as? String,
               let target = URL(string: raw) {
                return .link(target)
            }
        case _ where textExtensions.contains(ext):
            if item.size < 1_000_000 { return .text(item.url) }
        default:
            break
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 512, height: 512),
            scale: 2,
            representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request) {
            return .image(representation.nsImage)
        }
        return .icon
    }
}

/// Painel do preview: recebe teclado sem ativar o app, com atalhos de
/// edição roteados manualmente (não há menu principal).
final class PreviewPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
            return
        }
        if event.modifierFlags.contains(.command),
           let editor = firstResponder as? NSTextView {
            let key = event.charactersIgnoringModifiers
            switch key {
            case "a": editor.selectAll(nil); return
            case "c": editor.copy(nil); return
            case "v": editor.paste(nil); return
            case "x": editor.cut(nil); return
            case "z":
                if event.modifierFlags.contains(.shift) {
                    editor.undoManager?.redo()
                } else {
                    editor.undoManager?.undo()
                }
                return
            default: break
            }
        }
        super.keyDown(with: event)
    }
}

/// Mostra um cartão flutuante com o preview do item sob o mouse depois
/// do atraso configurado. Conteúdos interativos (PDF, áudio, texto,
/// tabela, evento) aceitam mouse; o player de áudio permanece na tela
/// até ser fechado no X.
extension Notification.Name {
    /// Postada quando o player do preview de áudio começa a tocar —
    /// só então o preview fixa na tela.
    static let audioPreviewStartedPlaying = Notification.Name("downside.audioPlay")
}

@MainActor
final class PreviewController {
    private var panel: PreviewPanel?
    private var showTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var currentURL: URL?
    private(set) var isShowing = false
    private(set) var isSticky = false
    private var mouseInsideCard = false

    init() {
        NotificationCenter.default.addObserver(
            forName: .audioPreviewStartedPlaying,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.audioDidStartPlaying() }
        }
    }

    /// Play no áudio: agora sim o preview fixa (arrastável, fecha no X).
    private func audioDidStartPlaying() {
        guard isShowing else { return }
        isSticky = true
        panel?.isMovableByWindowBackground = true
        dismissTask?.cancel()
        dismissTask = nil
    }

    /// Posição "encaixada" (ao lado do painel) do preview fixado e
    /// estado do vai-e-vem quando o painel fecha/abre.
    private var stickyDockFrame: NSRect?
    private var parked = false
    private var animatingMove = false

    func frameContains(_ point: NSPoint) -> Bool {
        isShowing && panel?.frame.contains(point) == true
    }

    func hover(item: FileItem, near rect: NSRect) {
        guard Prefs.hoverPreviewEnabled, !isSticky else { return }
        // Durante um arrasto (botão pressionado), preview só atrapalha:
        // quem arrasta não está buscando olhar outros arquivos.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        dismissTask?.cancel()
        dismissTask = nil

        guard currentURL != item.url else { return }
        showTask?.cancel()
        currentURL = item.url

        // Com um preview já aberto, trocar de item é imediato.
        let delay = isShowing ? 0.08 : Prefs.hoverPreviewDelay
        showTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.present(item: item, near: rect)
        }
    }

    func unhover(_ url: URL) {
        guard currentURL == url else { return }
        showTask?.cancel()
        showTask = nil
        currentURL = nil
        scheduleDismiss()
    }

    // MARK: - Preview global de pilha

    private func stackKey(_ id: UUID) -> URL {
        URL(string: "downside-stack://\(id.uuidString)")!
    }

    /// Pairar sobre uma pilha: mostra todos os documentos dela de uma
    /// vez, num cartão ao lado do painel (nunca por cima).
    func hoverStack(_ id: UUID, urls: [URL], near rect: NSRect) {
        guard Prefs.stackPreviewEnabled, !isSticky, !urls.isEmpty else { return }
        guard NSEvent.pressedMouseButtons == 0 else { return }
        dismissTask?.cancel()
        dismissTask = nil

        let key = stackKey(id)
        guard currentURL != key else { return }
        showTask?.cancel()
        currentURL = key

        let delay = isShowing ? 0.1 : Prefs.stackPreviewDelay
        showTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.presentStack(key: key, urls: urls, near: rect)
        }
    }

    func unhoverStack(_ id: UUID) {
        unhover(stackKey(id))
    }

    private func presentStack(key: URL, urls: [URL], near rect: NSRect) {
        guard currentURL == key else { return }

        let hosting = NSHostingView(
            rootView: StackGridCard(urls: urls, scale: Prefs.uiScale)
        )
        let size = hosting.fittingSize

        let panel = ensurePanel()
        panel.contentView = hosting
        panel.ignoresMouseEvents = true
        isSticky = false
        panel.isMovableByWindowBackground = false
        parked = false

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) })
            ?? NSScreen.main else { return }
        let origin = origin(for: size, near: rect, on: screen)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        panel.alphaValue = 0
        panel.orderFront(nil)
        isShowing = true
        fadeIn(panel)
    }

    /// Fecha, exceto o player de áudio fixado (que só sai pelo X).
    func dismiss() {
        guard !isSticky else { return }
        forceDismiss()
    }

    /// Fecha incondicionalmente (X, Esc no preview).
    func forceDismiss() {
        showTask?.cancel()
        showTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        currentURL = nil
        guard isShowing, let panel else { return }
        isShowing = false
        isSticky = false
        mouseInsideCard = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShowing else { return }
                self.panel?.orderOut(nil)
                // Libera o conteúdo (para o player de áudio, etc.).
                self.panel?.contentView = NSView()
            }
        })
    }

    // MARK: - Internals

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            guard !self.isSticky, !self.mouseInsideCard else { return }
            self.forceDismiss()
        }
    }

    private func cardHoverChanged(_ inside: Bool) {
        mouseInsideCard = inside
        if inside {
            dismissTask?.cancel()
            dismissTask = nil
        } else if !isSticky {
            scheduleDismiss()
        }
    }

    private func present(item: FileItem, near rect: NSRect) async {
        let content = await PreviewBuilder.build(for: item)
        guard currentURL == item.url, !Task.isCancelled else { return }

        let scale = Prefs.uiScale
        let sizeFactor = Prefs.hoverPreviewSize * Prefs.previewCategorySize(content.sizeCategory)
        let card = PreviewCard(
            item: item,
            content: content,
            scale: scale,
            sizeFactor: sizeFactor,
            onClose: { [weak self] in self?.forceDismiss() },
            onHoverChange: { [weak self] inside in self?.cardHoverChanged(inside) }
        )
        let hosting = NSHostingView(rootView: card)
        let size = hosting.fittingSize

        let panel = ensurePanel()
        panel.contentView = hosting
        panel.ignoresMouseEvents = !content.isInteractive
        isSticky = content.isSticky
        panel.isMovableByWindowBackground = false
        parked = false

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) })
            ?? NSScreen.main else { return }
        let origin = origin(for: size, near: rect, on: screen)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        stickyDockFrame = panel.frame

        panel.alphaValue = 0
        panel.orderFront(nil)
        isShowing = true
        fadeIn(panel)
    }

    // MARK: - Player fixado: estacionar / reencaixar

    /// Painel principal fechou: leva o player à posição memorizada
    /// (ajustável arrastando), para não ficar "órfão" no meio da tela.
    func parkSticky() {
        guard isSticky, isShowing, let panel else { return }
        parked = true
        animateMove(panel, to: parkedOrigin(for: panel.frame.size))
    }

    /// Painel principal reabriu: traz o player de volta para o encaixe.
    func dockSticky() {
        guard isSticky, isShowing, parked, let panel else { return }
        parked = false
        let target = stickyDockFrame?.origin ?? panel.frame.origin
        animateMove(panel, to: clamped(target, size: panel.frame.size))
    }

    private func parkedOrigin(for size: NSSize) -> NSPoint {
        let x = UserDefaults.standard.double(forKey: "stickyPlayer.x")
        let y = UserDefaults.standard.double(forKey: "stickyPlayer.y")
        if x != 0 || y != 0 {
            let saved = NSPoint(x: x, y: y)
            if NSScreen.screens.contains(where: {
                $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(saved)
            }) {
                return clamped(saved, size: size)
            }
        }
        if let area = NSScreen.main?.visibleFrame {
            return NSPoint(x: area.maxX - size.width - 16, y: area.minY + 16)
        }
        return .zero
    }

    private func clamped(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let area = NSScreen.screens
            .first(where: { $0.frame.contains(origin) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        else { return origin }
        let x = min(max(origin.x, area.minX + 8), area.maxX - size.width - 8)
        let y = min(max(origin.y, area.minY + 8), area.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    private func animateMove(_ panel: NSPanel, to origin: NSPoint) {
        animatingMove = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(
                NSRect(origin: origin, size: panel.frame.size),
                display: true
            )
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.animatingMove = false }
        })
    }

    /// Usuário arrastou o player estacionado: memoriza a posição.
    private func windowMoved() {
        guard isSticky, parked, !animatingMove, let panel else { return }
        UserDefaults.standard.set(Double(panel.frame.origin.x), forKey: "stickyPlayer.x")
        UserDefaults.standard.set(Double(panel.frame.origin.y), forKey: "stickyPlayer.y")
    }

    private func fadeIn(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    private func ensurePanel() -> PreviewPanel {
        if let panel { return panel }
        let panel = PreviewPanel()
        panel.onClose = { [weak self] in
            Task { @MainActor in self?.forceDismiss() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.windowMoved() }
        }
        self.panel = panel
        return panel
    }

    /// Posiciona ao lado do item (no lado com mais espaço), sem sair da tela.
    private func origin(for size: NSSize, near rect: NSRect, on screen: NSScreen) -> NSPoint {
        let area = screen.visibleFrame
        let gap: CGFloat = 12

        let spaceLeft = rect.minX - area.minX
        let spaceRight = area.maxX - rect.maxX
        var x: CGFloat
        if spaceLeft >= spaceRight {
            x = rect.minX - size.width - gap
        } else {
            x = rect.maxX + gap
        }
        x = max(area.minX + 8, min(x, area.maxX - 8 - size.width))

        var y = rect.midY - size.height / 2
        y = max(area.minY + 8, min(y, area.maxY - 8 - size.height))

        return NSPoint(x: x, y: y)
    }
}

// MARK: - Cartão

struct PreviewCard: View {
    let item: FileItem
    let content: PreviewContent
    let scale: CGFloat
    let sizeFactor: CGFloat
    var onClose: () -> Void = {}
    var onHoverChange: (Bool) -> Void = { _ in }

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var width: CGFloat { 380 * scale * sizeFactor }

    var body: some View {
        VStack(spacing: 10 * scale) {
            if content.isInteractive {
                HStack {
                    Text(item.name)
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    // Texto vindo do clipboard: converter em .txt na pasta.
                    if case .text(let url) = content,
                       url.path.contains("/Downside/Clipboard/") {
                        SaveClipboardTextButton(url: url, scale: scale)
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13 * scale))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Fechar preview")
                }
            }

            preview

            if !content.isInteractive {
                VStack(spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                    Text(detail)
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(detail)
                    .font(.system(size: 9.5 * scale))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14 * scale)
        .frame(width: width)
        .background(VisualEffectView(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onHover(perform: onHoverChange)
    }

    @ViewBuilder
    private var preview: some View {
        switch content {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: width - 28 * scale, maxHeight: 330 * scale * sizeFactor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)

        case .folder(let children, let total):
            VStack(alignment: .leading, spacing: 4 * scale) {
                if children.isEmpty {
                    Text("Pasta vazia")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.secondary)
                }
                ForEach(children, id: \.self) { child in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: child.path))
                            .resizable()
                            .frame(width: 14 * scale, height: 14 * scale)
                        Text(child.lastPathComponent)
                            .font(.system(size: 11 * scale))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if total > children.count {
                    Text("+ \(total - children.count) itens")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .pdf(let url):
            PDFKitView(url: url)
                .frame(height: 420 * scale * sizeFactor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .audio(let url):
            AudioPlayerView(url: url, scale: scale)

        case .text(let url):
            TextFilePreview(url: url, scale: scale, sizeFactor: sizeFactor)

        case .table(let url):
            CSVTablePreview(url: url, scale: scale, sizeFactor: sizeFactor)

        case .event(let url):
            VStack(spacing: 8 * scale) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 48 * scale, height: 48 * scale)
                if let ics = ICSParser.parse(url: url) {
                    Text(ics.title)
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(ics.start.formatted(
                        date: .abbreviated,
                        time: ics.isAllDay ? .omitted : .shortened
                    ))
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
                    if let location = ics.location, !location.isEmpty {
                        Text(location)
                            .font(.system(size: 10 * scale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                CalendarAddButton(url: url, scale: scale)
            }
            .frame(maxWidth: .infinity)

        case .link(let target):
            VStack(spacing: 8 * scale) {
                Image(systemName: "safari")
                    .font(.system(size: 44 * scale, weight: .thin))
                    .foregroundStyle(Theme.tint(0.9))
                Text(target.host ?? "Link")
                    .font(.system(size: 13 * scale, weight: .semibold))
                Text(target.absoluteString)
                    .font(.system(size: 9.5 * scale))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

        case .icon:
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 96 * scale, height: 96 * scale)
        }
    }

    private var detail: String {
        let when = item.date.formatted(date: .abbreviated, time: .shortened)
        if item.isDirectory {
            return when
        }
        return "\(Self.sizeFormatter.string(fromByteCount: item.size)) · \(when)"
    }
}

/// Cartão com todos os documentos de uma pilha de uma vez, em grade de
/// tamanho dinâmico (colunas conforme a quantidade).
struct StackGridCard: View {
    let urls: [URL]
    let scale: CGFloat

    private var shown: [URL] { Array(urls.prefix(12)) }

    private var columns: Int {
        switch urls.count {
        case ...2: return max(1, urls.count)
        case 3...4: return 2
        case 5...9: return 3
        default: return 4
        }
    }

    private var rows: [[URL]] {
        stride(from: 0, to: shown.count, by: columns).map {
            Array(shown[$0..<min($0 + columns, shown.count)])
        }
    }

    var body: some View {
        VStack(spacing: 10 * scale) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10 * scale) {
                    ForEach(row, id: \.self) { url in
                        VStack(spacing: 4 * scale) {
                            ThumbnailView(url: url)
                                .frame(width: 96 * scale, height: 96 * scale)
                            Text(url.lastPathComponent)
                                .font(.system(size: 9.5 * scale))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: 100 * scale)
                        }
                    }
                }
            }

            if urls.count > shown.count {
                Text("+ \(urls.count - shown.count) itens")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14 * scale)
        .background(VisualEffectView(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Pill no preview de texto do clipboard: salva uma cópia .txt na
/// pasta monitorada (vira um doc "de verdade" na lista).
struct SaveClipboardTextButton: View {
    let url: URL
    let scale: CGFloat

    @State private var saved = false

    var body: some View {
        Button {
            let folder = Prefs.folderURL
            var name = url.deletingPathExtension().lastPathComponent
            if name.isEmpty { name = "Texto" }
            var destination = folder.appendingPathComponent("\(name).txt")
            var counter = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                destination = folder.appendingPathComponent("\(name) \(counter).txt")
                counter += 1
            }
            if (try? FileManager.default.copyItem(at: url, to: destination)) != nil {
                withAnimation(.easeInOut(duration: 0.15)) { saved = true }
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation(.easeInOut(duration: 0.15)) { saved = false }
                }
            }
        } label: {
            Image(systemName: saved ? "checkmark" : "arrow.down.doc")
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22 * scale, height: 22 * scale)
        }
        .buttonStyle(.borderless)
        .background(
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(saved ? Color.green.opacity(0.75) : Theme.tint(0.65))
            }
        )
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
        .help("Criar um arquivo .txt na pasta monitorada")
    }
}

// MARK: - Conteúdos interativos

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

@MainActor
final class AudioPlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var rate: Float = 1.0 {
        didSet {
            player?.rate = rate
        }
    }

    let duration: TimeInterval
    private var player: AVAudioPlayer?
    private var timer: Timer?

    init(url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        duration = player?.duration ?? 0
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            player.play()
            player.rate = rate
            isPlaying = true
            startTimer()
            NotificationCenter.default.post(name: .audioPreviewStartedPlaying, object: nil)
        }
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), duration)
        player?.currentTime = clamped
        currentTime = clamped
    }

    func skip(_ seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        currentTime = player?.currentTime ?? 0
        if player?.isPlaying != true {
            isPlaying = false
            timer?.invalidate()
        }
    }

    deinit {
        player?.stop()
        timer?.invalidate()
    }
}

struct AudioPlayerView: View {
    let scale: CGFloat
    @StateObject private var model: AudioPlayerModel

    private static let speeds: [Float] = [1.0, 1.2, 1.5, 1.7, 2.0]

    init(url: URL, scale: CGFloat) {
        self.scale = scale
        _model = StateObject(wrappedValue: AudioPlayerModel(url: url))
    }

    var body: some View {
        VStack(spacing: 7 * scale) {
            HStack(spacing: 14 * scale) {
                Button {
                    model.skip(-10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 15 * scale))
                }
                .help("Voltar 10 s")

                Button {
                    model.toggle()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30 * scale))
                }
                .help(model.isPlaying ? "Pausar" : "Reproduzir")

                Button {
                    model.skip(10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 15 * scale))
                }
                .help("Avançar 10 s")

                Spacer()

                Menu {
                    ForEach(Self.speeds, id: \.self) { speed in
                        Button {
                            model.rate = speed
                        } label: {
                            if speed == model.rate {
                                Label(speedLabel(speed), systemImage: "checkmark")
                            } else {
                                Text(speedLabel(speed))
                            }
                        }
                    }
                } label: {
                    Text(speedLabel(model.rate))
                        .font(.system(size: 10.5 * scale, weight: .semibold, design: .monospaced))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Velocidade de reprodução")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            Slider(
                value: Binding(
                    get: { model.currentTime },
                    set: { model.seek(to: $0) }
                ),
                in: 0...max(model.duration, 1)
            )
            .controlSize(.small)

            HStack {
                Text(timeString(model.currentTime))
                Spacer()
                Text(timeString(model.duration))
            }
            .font(.system(size: 9.5 * scale, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2 * scale)
    }

    private func speedLabel(_ speed: Float) -> String {
        let text = speed == 1 || speed == 2
            ? String(Int(speed))
            : String(format: "%.1f", speed).replacingOccurrences(of: ".", with: ",")
        return "\(text)×"
    }

    private func timeString(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct CSVTablePreview: View {
    let url: URL
    let scale: CGFloat
    let sizeFactor: CGFloat

    @State private var rows: [[String]] = []
    @State private var truncated = false

    private let maxRows = 30
    private let maxColumns = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            ScrollView([.vertical, .horizontal]) {
                Grid(alignment: .leading, horizontalSpacing: 12 * scale, verticalSpacing: 3 * scale) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(.system(
                                        size: 10.5 * scale,
                                        weight: index == 0 ? .semibold : .regular,
                                        design: .monospaced
                                    ))
                                    .lineLimit(1)
                            }
                        }
                        if index == 0 {
                            Divider()
                        }
                    }
                }
                .padding(6 * scale)
            }
            .frame(height: 240 * scale * sizeFactor)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            if truncated {
                Text("Mostrando as primeiras \(maxRows) linhas")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard rows.isEmpty else { return }
        guard let raw = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        else { return }

        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
        truncated = lines.count > maxRows

        let first = lines.first.map(String.init) ?? ""
        let delimiter: Character
        if url.pathExtension.lowercased() == "tsv" || first.contains("\t") {
            delimiter = "\t"
        } else if first.filter({ $0 == ";" }).count > first.filter({ $0 == "," }).count {
            delimiter = ";"
        } else {
            delimiter = ","
        }

        rows = lines.prefix(maxRows).map { line in
            line.split(separator: delimiter, omittingEmptySubsequences: false)
                .prefix(maxColumns)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        }
    }
}
