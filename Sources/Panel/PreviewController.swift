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
    /// Sem renderização disponível: ícone grande do arquivo.
    case icon

    /// Conteúdos interativos recebem mouse (rolagem, edição, player).
    var isInteractive: Bool {
        switch self {
        case .pdf, .audio, .text, .table, .event: return true
        case .image, .folder, .icon: return false
        }
    }

    /// O player de áudio fica na tela até o usuário fechar no X.
    var isSticky: Bool {
        if case .audio = self { return true }
        return false
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
@MainActor
final class PreviewController {
    private var panel: PreviewPanel?
    private var showTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var currentURL: URL?
    private(set) var isShowing = false
    private(set) var isSticky = false
    private var mouseInsideCard = false

    func frameContains(_ point: NSPoint) -> Bool {
        isShowing && panel?.frame.contains(point) == true
    }

    func hover(item: FileItem, near rect: NSRect) {
        guard Prefs.hoverPreviewEnabled, !isSticky else { return }
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
        let sizeFactor = Prefs.hoverPreviewSize
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

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) })
            ?? NSScreen.main else { return }
        let origin = origin(for: size, near: rect, on: screen)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        panel.alphaValue = 0
        panel.orderFront(nil)
        isShowing = true
        fadeIn(panel)
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
            VStack(spacing: 10 * scale) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 64 * scale, height: 64 * scale)
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Adicionar à Agenda", systemImage: "calendar.badge.plus")
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12 * scale)
                        .padding(.vertical, 6 * scale)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.borderless)
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

    let duration: TimeInterval
    private var player: AVAudioPlayer?
    private var timer: Timer?

    init(url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
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
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
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

    init(url: URL, scale: CGFloat) {
        self.scale = scale
        _model = StateObject(wrappedValue: AudioPlayerModel(url: url))
    }

    var body: some View {
        HStack(spacing: 10 * scale) {
            Button {
                model.toggle()
            } label: {
                Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28 * scale))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)

            Slider(
                value: Binding(
                    get: { model.currentTime },
                    set: { model.seek(to: $0) }
                ),
                in: 0...max(model.duration, 1)
            )

            Text("\(timeString(model.currentTime)) / \(timeString(model.duration))")
                .font(.system(size: 10 * scale, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4 * scale)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TextFilePreview: View {
    let url: URL
    let scale: CGFloat
    let sizeFactor: CGFloat

    @State private var text = ""
    @State private var loaded = false
    @State private var status = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            TextEditor(text: $text)
                .font(.system(size: 12 * scale, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 260 * scale * sizeFactor)
                .padding(4 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            Text(status.isEmpty ? "Edição com salvamento automático · ⌘Z desfaz, ⇧⌘Z refaz" : status)
                .font(.system(size: 9 * scale))
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: load)
        .onChange(of: text) { _, newValue in
            guard loaded else { return }
            scheduleSave(newValue)
        }
    }

    private func load() {
        guard !loaded else { return }
        text = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
            ?? ""
        loaded = true
    }

    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            do {
                try value.write(to: url, atomically: true, encoding: .utf8)
                status = "Salvo ✓"
            } catch {
                status = "Não foi possível salvar"
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { status = "" }
        }
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
