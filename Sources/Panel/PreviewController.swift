import AppKit
import SwiftUI
import QuickLookThumbnailing

enum PreviewContent {
    /// Renderização Quick Look (PDF, imagem, planilha, texto…).
    case image(NSImage)
    /// Conteúdo de pastas: primeiros itens + total.
    case folder(children: [URL], total: Int)
    /// Sem renderização disponível: ícone grande do arquivo.
    case icon
}

enum PreviewBuilder {
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

/// Mostra um cartão flutuante com o preview do item sob o mouse depois
/// do atraso configurado. O cartão ignora o mouse, então nunca atrapalha
/// cliques nem o fechamento automático do painel.
@MainActor
final class PreviewController {
    private var panel: NSPanel?
    private var showTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var currentURL: URL?
    private(set) var isShowing = false

    func hover(item: FileItem, near rect: NSRect) {
        guard Prefs.hoverPreviewEnabled else { return }
        dismissTask?.cancel()
        dismissTask = nil

        guard currentURL != item.url else { return }
        showTask?.cancel()
        currentURL = item.url

        // Com um preview já aberto, trocar de item é imediato (como
        // tooltips do sistema).
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

        // Pequeno atraso para não piscar ao deslizar entre itens vizinhos.
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        showTask?.cancel()
        showTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        currentURL = nil
        guard isShowing, let panel else { return }
        isShowing = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShowing else { return }
                self.panel?.orderOut(nil)
            }
        })
    }

    // MARK: - Internals

    private func present(item: FileItem, near rect: NSRect) async {
        let content = await PreviewBuilder.build(for: item)
        guard currentURL == item.url, !Task.isCancelled else { return }

        let hosting = NSHostingView(
            rootView: PreviewCard(item: item, content: content, scale: Prefs.uiScale)
        )
        let size = hosting.fittingSize

        let panel = ensurePanel()
        panel.contentView = hosting

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) })
            ?? NSScreen.main else { return }
        let origin = origin(for: size, near: rect, on: screen)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        panel.alphaValue = 0
        panel.orderFront(nil)
        isShowing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
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

struct PreviewCard: View {
    let item: FileItem
    let content: PreviewContent
    let scale: CGFloat

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(spacing: 10 * scale) {
            preview

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
        }
        .padding(14 * scale)
        .frame(width: 380 * scale)
        .background(VisualEffectView(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var preview: some View {
        switch content {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 352 * scale, maxHeight: 330 * scale)
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
