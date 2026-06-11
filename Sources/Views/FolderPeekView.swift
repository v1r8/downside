import SwiftUI
import AppKit

/// Conteúdo do painel: cabeçalho + grid de arquivos com multi-seleção.
///
/// Seleção suportada:
///  - clique simples seleciona; clique duplo abre
///  - ⌘-clique alterna item; ⇧-clique seleciona intervalo
///  - clicar e arrastar em área vazia desenha o retângulo de seleção
///  - ⌘A seleciona tudo; Esc fecha o painel
struct FolderPeekView: View {
    @EnvironmentObject private var monitor: FolderMonitor
    @EnvironmentObject private var panel: PanelController

    @State private var selection: Set<URL> = []
    @State private var anchorIndex: Int?
    @State private var itemFrames: [URL: CGRect] = [:]
    @State private var rubberBand: CGRect?

    private let gridSpace = "downside.grid"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onReceive(NotificationCenter.default.publisher(for: .peekSelectAll)) { _ in
            selection = Set(monitor.items.map(\.url))
        }
        .onChange(of: monitor.items) { _, items in
            // Remove da seleção arquivos que sumiram da pasta.
            let valid = Set(items.map(\.url))
            selection.formIntersection(valid)
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: monitor.folderURL.path))
                .resizable()
                .frame(width: 18, height: 18)

            Text(monitor.folderURL.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

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
        .buttonStyle(.borderless)
        .imageScale(.medium)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    // MARK: - Grid

    @ViewBuilder
    private var content: some View {
        if monitor.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92, maximum: 116), spacing: 6)],
                        spacing: 6
                    ) {
                        ForEach(monitor.items) { item in
                            cell(for: item)
                        }
                    }
                    .padding(10)
                    .background(rubberBandCatcher)

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
            }
            .onPreferenceChange(ItemFramePreferenceKey.self) { frames in
                itemFrames = frames
            }
        }
    }

    private func cell(for item: FileItem) -> some View {
        FileCell(item: item, isSelected: selection.contains(item.url))
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ItemFramePreferenceKey.self,
                        value: [item.url: proxy.frame(in: .named(gridSpace))]
                    )
                }
            )
            .simultaneousGesture(
                TapGesture(count: 1).onEnded { handleClick(on: item) }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { open([item.url]) }
            )
            .onDrag {
                NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
            }
            .contextMenu { contextMenu(for: item) }
    }

    /// Camada atrás do grid que captura cliques/arrastos em área vazia.
    private var rubberBandCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                selection.removeAll()
                anchorIndex = nil
            }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(gridSpace))
                    .onChanged { value in
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
            )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Pasta vazia")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Seleção

    private func handleClick(on item: FileItem) {
        let modifiers = NSEvent.modifierFlags
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
        } else {
            selection = [item.url]
            anchorIndex = index
        }
    }

    /// Alvo das ações de contexto: a seleção, se o item clicado fizer
    /// parte dela; senão, apenas o item clicado (como no Finder).
    private func targets(for item: FileItem) -> [URL] {
        if selection.contains(item.url) {
            return monitor.items.filter { selection.contains($0.url) }.map(\.url)
        }
        return [item.url]
    }

    // MARK: - Ações

    @ViewBuilder
    private func contextMenu(for item: FileItem) -> some View {
        let urls = targets(for: item)
        let suffix = urls.count > 1 ? " (\(urls.count) itens)" : ""

        Button("Abrir\(suffix)") { open(urls) }
        Button("Mostrar no Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
        Divider()
        Button("Copiar\(suffix)") { copyToPasteboard(urls) }
        Divider()
        Button("Mover para o Lixo\(suffix)", role: .destructive) { moveToTrash(urls) }
    }

    private func open(_ urls: [URL]) {
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
