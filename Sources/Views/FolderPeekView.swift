import SwiftUI
import AppKit

/// Conteúdo do painel: cabeçalho + arquivos no modo de exibição escolhido
/// (grade, lista ou minimalista).
///
/// Seleção (comportamento do Finder, em todos os modos):
///  - clique seleciona (no mouse-down); clique duplo abre
///  - ⌘-clique alterna item; ⇧-clique seleciona intervalo
///  - arrastar de área vazia desenha o retângulo de seleção
///  - arrastar um item selecionado leva TODOS os selecionados
///  - ⌘A seleciona tudo; Esc fecha o painel
///  - parar o mouse sobre um item abre o preview (configurável)
struct FolderPeekView: View {
    @EnvironmentObject private var monitor: FolderMonitor
    @EnvironmentObject private var panel: PanelController

    @AppStorage(PrefKey.viewMode) private var viewModeRaw = ViewMode.grid.rawValue
    @AppStorage(PrefKey.uiScale) private var uiScaleRaw = 1.0

    @State private var selection: Set<URL> = []
    @State private var anchorIndex: Int?
    @State private var itemFrames: [URL: CGRect] = [:]
    @State private var rubberBand: CGRect?

    private let gridSpace = "downside.grid"

    private var mode: ViewMode {
        ViewMode(rawValue: viewModeRaw) ?? .grid
    }

    private var scale: CGFloat {
        let value = CGFloat(uiScaleRaw)
        return (0.8...2.0).contains(value) ? value : 1.0
    }

    var body: some View {
        // No minimalista o texto fica branco com sombra sobre a tela
        // escurecida, então forçamos o esquema escuro.
        if mode == .minimal {
            core.environment(\.colorScheme, .dark)
        } else {
            core
        }
    }

    private var core: some View {
        VStack(spacing: 0) {
            header
            if mode != .minimal {
                Divider().opacity(0.4)
            }
            content
        }
        .background {
            if mode != .minimal {
                PanelBackground()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if mode != .minimal {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .peekSelectAll)) { _ in
            selection = Set(monitor.items.map(\.url))
        }
        .onChange(of: monitor.items) { _, items in
            // Remove da seleção arquivos que sumiram da pasta.
            let valid = Set(items.map(\.url))
            selection.formIntersection(valid)
        }
        .onChange(of: viewModeRaw) { _, _ in
            itemFrames = [:]
            panel.preview.dismiss()
            panel.refreshAppearance()
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 8 * scale) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: monitor.folderURL.path))
                .resizable()
                .frame(width: 18 * scale, height: 18 * scale)
                .opacity(mode == .minimal ? 0.85 : 1)

            Text(monitor.folderURL.lastPathComponent)
                .font(.system(size: 13 * scale, weight: .semibold))
                .minimalShadow(mode == .minimal)

            Text(subtitle)
                .font(.system(size: 11 * scale))
                .foregroundStyle(.secondary)
                .minimalShadow(mode == .minimal)

            Spacer()

            Picker("Modo de exibição", selection: $viewModeRaw) {
                ForEach(ViewMode.allCases) { mode in
                    Image(systemName: mode.icon)
                        .help(mode.label)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Group {
                Button {
                    panel.isPinned.toggle()
                } label: {
                    Image(systemName: panel.isPinned ? "pin.fill" : "pin")
                }
                .help(panel.isPinned ? "Liberar painel" : "Manter painel aberto")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([monitor.folderURL])
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Abrir no Finder")

                Button {
                    SettingsOpener.open()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Configurações")
            }
            .font(.system(size: 13 * scale))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 10 * scale)
    }

    private var subtitle: String {
        if !selection.isEmpty {
            return "\(selection.count) de \(monitor.items.count) selecionados"
        }
        if monitor.isTruncated {
            return "\(monitor.items.count) itens mais recentes"
        }
        return monitor.items.count == 1 ? "1 item" : "\(monitor.items.count) itens"
    }

    // MARK: - Conteúdo

    @ViewBuilder
    private var content: some View {
        if monitor.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    layout
                        .padding(mode == .grid ? 10 * scale : 12 * scale)
                        .background(emptyAreaCatcher)

                    if let rect = rubberBand {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                            )
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: gridSpace)
                .simultaneousGesture(rubberBandGesture)
            }
            .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                itemFrames = frames
            }
        }
    }

    @ViewBuilder
    private var layout: some View {
        switch mode {
        case .grid:
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92 * scale, maximum: 116 * scale), spacing: 6 * scale)],
                spacing: 6 * scale
            ) {
                ForEach(monitor.items) { item in
                    interactive(item) {
                        FileCell(item: item, isSelected: selection.contains(item.url), scale: scale)
                    }
                }
            }
        case .list:
            LazyVStack(spacing: 2) {
                ForEach(monitor.items) { item in
                    interactive(item) {
                        FileRow(item: item, isSelected: selection.contains(item.url), scale: scale)
                    }
                }
            }
        case .minimal:
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(monitor.items) { item in
                    interactive(item) {
                        MinimalFileRow(item: item, isSelected: selection.contains(item.url), scale: scale)
                    }
                }
            }
        }
    }

    /// Aplica a cada item os comportamentos comuns a todos os modos:
    /// rastreio de posição (rubber band) e a camada nativa de interação
    /// (cliques, arrasto múltiplo, menu de contexto e hover).
    private func interactive<Content: View>(
        _ item: FileItem,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ItemFramePreferenceKey.self,
                        value: [item.url: proxy.frame(in: .named(gridSpace))]
                    )
                }
            )
            .overlay(
                ItemInteraction(
                    onMouseDown: { modifiers in mouseDown(on: item, modifiers: modifiers) },
                    onClickUp: { modifiers in clickUp(on: item, modifiers: modifiers) },
                    onDoubleClick: { open(targets(for: item)) },
                    dragURLs: { dragTargets(for: item) },
                    menu: { contextMenu(for: item) },
                    onHover: { hovering, rect in
                        if hovering {
                            panel.preview.hover(item: item, near: rect)
                        } else {
                            panel.preview.unhover(item.url)
                        }
                    }
                )
            )
    }

    /// Camada atrás dos itens: clique em área vazia limpa a seleção.
    private var emptyAreaCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                selection.removeAll()
                anchorIndex = nil
            }
    }

    /// Retângulo de seleção: só inicia em área vazia (sobre um item, o
    /// arrasto é dos arquivos). Funciona nos três modos.
    private var rubberBandGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(gridSpace))
            .onChanged { value in
                if rubberBand == nil {
                    let startedOnItem = itemFrames.contains { $0.value.contains(value.startLocation) }
                    if startedOnItem { return }
                    panel.preview.dismiss()
                }
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                rubberBand = rect
                selection = Set(
                    itemFrames
                        .filter { $0.value.intersects(rect) }
                        .map(\.key)
                )
            }
            .onEnded { _ in
                rubberBand = nil
            }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32 * scale))
                .foregroundStyle(.tertiary)
            Text("Pasta vazia")
                .font(.system(size: 13 * scale))
                .foregroundStyle(.secondary)
                .minimalShadow(mode == .minimal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Seleção (semântica do Finder)

    private func mouseDown(on item: FileItem, modifiers: NSEvent.ModifierFlags) {
        panel.preview.dismiss()
        guard let index = monitor.items.firstIndex(of: item) else { return }

        if modifiers.contains(.command) {
            if selection.contains(item.url) {
                selection.remove(item.url)
            } else {
                selection.insert(item.url)
            }
            anchorIndex = index
        } else if modifiers.contains(.shift), let anchor = anchorIndex {
            let range = min(anchor, index)...max(anchor, index)
            selection.formUnion(monitor.items[range].map(\.url))
        } else if !selection.contains(item.url) {
            selection = [item.url]
            anchorIndex = index
        }
        // Item já selecionado sem modificador: mantém o grupo intacto
        // para permitir arrastar todos; o colapso acontece no mouse-up.
    }

    private func clickUp(on item: FileItem, modifiers: NSEvent.ModifierFlags) {
        guard modifiers.isDisjoint(with: [.command, .shift]),
              selection.contains(item.url),
              selection.count > 1
        else { return }
        selection = [item.url]
        anchorIndex = monitor.items.firstIndex(of: item)
    }

    /// Alvo das ações: a seleção, se o item fizer parte dela; senão,
    /// apenas o item (como no Finder). Mantém a ordem da listagem.
    private func targets(for item: FileItem) -> [URL] {
        if selection.contains(item.url) {
            return monitor.items.filter { selection.contains($0.url) }.map(\.url)
        }
        return [item.url]
    }

    private func dragTargets(for item: FileItem) -> [URL] {
        targets(for: item)
    }

    // MARK: - Ações

    private func contextMenu(for item: FileItem) -> NSMenu {
        panel.preview.dismiss()
        if !selection.contains(item.url) {
            selection = [item.url]
            anchorIndex = monitor.items.firstIndex(of: item)
        }
        let urls = targets(for: item)
        let suffix = urls.count > 1 ? " (\(urls.count) itens)" : ""

        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "Abrir\(suffix)") { open(urls) })
        menu.addItem(ActionMenuItem(title: "Mostrar no Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Copiar\(suffix)") { copyToPasteboard(urls) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Mover para o Lixo\(suffix)") { moveToTrash(urls) })
        return menu
    }

    private func open(_ urls: [URL]) {
        panel.preview.dismiss()
        urls.forEach { NSWorkspace.shared.open($0) }
        if !panel.isPinned {
            panel.hide()
        }
    }

    private func copyToPasteboard(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    private func moveToTrash(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        selection.subtract(urls)
        monitor.reload()
    }
}

private struct ItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [URL: CGRect] = [:]

    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Sombra para o texto continuar legível sobre a tela escurecida
    /// do modo minimalista.
    @ViewBuilder
    func minimalShadow(_ active: Bool) -> some View {
        if active {
            shadow(color: .black.opacity(0.8), radius: 2, y: 1)
        } else {
            self
        }
    }
}
