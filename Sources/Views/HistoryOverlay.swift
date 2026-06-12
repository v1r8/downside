import SwiftUI
import AppKit

/// Fichário: histórico de pilhas arquivadas. Fichas expansíveis (com
/// preview por item e outputs fixados), arrastáveis de volta para as
/// pilhas provisórias, renomeáveis (manual ou por IA), com
/// multi-seleção. A busca usa a barra principal do painel.
struct HistoryOverlay: View {
    @ObservedObject private var store = StackHistoryStore.shared
    @EnvironmentObject private var panel: PanelController
    let scale: CGFloat
    let searchQuery: String

    @State private var selection: Set<UUID> = []
    @State private var expandedEntry: UUID?
    @State private var renamingEntry: UUID?
    @State private var renameText = ""

    private var filtered: [ArchivedStack] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.archived }
        let needle = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return store.archived.filter { entry in
            let haystack = (entry.title + " " + entry.paths.joined(separator: " "))
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            return haystack.contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 6 * scale) {
            if !selection.isEmpty {
                HStack {
                    Text("\(selection.count) selecionadas")
                        .font(.system(size: 10.5 * scale))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apagar", role: .destructive) {
                        for id in selection { store.delete(id) }
                        selection.removeAll()
                    }
                    .font(.system(size: 10.5 * scale))
                    Button("Limpar seleção") {
                        selection.removeAll()
                    }
                    .font(.system(size: 10.5 * scale))
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 4 * scale)
            }

            if filtered.isEmpty {
                VStack(spacing: 6 * scale) {
                    Image(systemName: "book")
                        .font(.system(size: 26 * scale))
                        .foregroundStyle(.tertiary)
                    Text(store.archived.isEmpty
                        ? "Pilhas arquivadas aparecem aqui — arraste uma pilha para o livrinho"
                        : "Nada encontrado para a busca")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4 * scale) {
                        ForEach(filtered) { entry in
                            card(entry)
                        }
                    }
                }
            }
        }
        .padding(10 * scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: expandedEntry)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: selection)
    }

    // MARK: - Ficha

    @ViewBuilder
    private func card(_ entry: ArchivedStack) -> some View {
        let isSelected = selection.contains(entry.id)
        let isExpanded = expandedEntry == entry.id

        VStack(alignment: .leading, spacing: 0) {
            header(entry, isSelected: isSelected, isExpanded: isExpanded)

            if isExpanded {
                Divider().opacity(0.3)
                expandedContent(entry)
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(entry.hadBulkAction ? Theme.tint(0.08) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.accent : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
    }

    private func header(_ entry: ArchivedStack, isSelected: Bool, isExpanded: Bool) -> some View {
        HStack(spacing: 8 * scale) {
            HStack(spacing: 8 * scale) {
                ZStack(alignment: .leading) {
                    ForEach(Array(entry.urls.prefix(3).enumerated()), id: \.offset) { index, url in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 20 * scale, height: 20 * scale)
                            .padding(.leading, CGFloat(index) * 5 * scale)
                            .rotationEffect(.degrees(Double(index) * 3 - 3))
                    }
                }
                .frame(width: 34 * scale, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    if renamingEntry == entry.id {
                        TextField("Título", text: $renameText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5 * scale, weight: .semibold))
                            .onSubmit {
                                store.rename(entry.id, to: renameText)
                                renamingEntry = nil
                            }
                    } else {
                        Text(entry.title)
                            .font(.system(size: 11.5 * scale, weight: .semibold))
                            .lineLimit(1)
                    }
                    HStack(spacing: 4 * scale) {
                        Text("\(entry.paths.count) docs · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                        if entry.hadBulkAction {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .font(.system(size: 9.5 * scale))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .overlay(
                ItemInteraction(
                    onMouseDown: { _ in },
                    onClickUp: { modifiers in
                        if modifiers.contains(.command) {
                            if isSelected { selection.remove(entry.id) } else { selection.insert(entry.id) }
                        } else {
                            expandedEntry = isExpanded ? nil : entry.id
                        }
                    },
                    onDoubleClick: { expandedEntry = isExpanded ? nil : entry.id },
                    // Arrastar a ficha de volta: solte nos alvos das
                    // pilhas provisórias para restaurá-la.
                    dragURLs: { entry.urls },
                    menu: { cardMenu(entry) },
                    onHover: { hovering, _ in
                        guard Prefs.archiveHoverPreview else { return }
                        if hovering {
                            panel.hoverStackPreviewURLs(entry.id, urls: entry.urls)
                        } else {
                            panel.preview.unhoverStack(entry.id)
                        }
                    },
                    onDragStarted: { panel.isDraggingFromPanel = true },
                    onDragEnded: { panel.isDraggingFromPanel = false }
                )
            )

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8 * scale, weight: .semibold))
                .foregroundStyle(.secondary)

            Button {
                store.delete(entry.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Apagar do fichário")
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 5 * scale)
    }

    @ViewBuilder
    private func expandedContent(_ entry: ArchivedStack) -> some View {
        let outputSet = Set(entry.outputPaths)
        let originals = entry.urls.filter { !outputSet.contains($0.path) }

        VStack(alignment: .leading, spacing: 2) {
            ForEach(originals.prefix(12), id: \.self) { url in
                fileRow(url, entry: entry)
            }
            if originals.count > 12 {
                Text("+ \(originals.count - 12) docs")
                    .font(.system(size: 9.5 * scale))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8 * scale)
            }

            if !entry.outputs.isEmpty {
                Divider().opacity(0.3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6 * scale) {
                        ForEach(entry.outputs, id: \.self) { url in
                            HStack(spacing: 5 * scale) {
                                ThumbnailView(url: url)
                                    .frame(width: 16 * scale, height: 16 * scale)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 9.5 * scale))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 100 * scale)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8 * scale))
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(.horizontal, 6 * scale)
                            .padding(.vertical, 3 * scale)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.tint(0.12))
                            )
                            .overlay(
                                ItemInteraction(
                                    onMouseDown: { _ in },
                                    onClickUp: { _ in },
                                    onDoubleClick: { NSWorkspace.shared.open(url) },
                                    dragURLs: { [url] },
                                    menu: { simpleMenu(url) },
                                    onHover: { hovering, rect in
                                        if hovering {
                                            panel.preview.hover(item: FileItem(url: url), near: rect)
                                        } else {
                                            panel.preview.unhover(url)
                                        }
                                    }
                                )
                            )
                        }
                    }
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 4 * scale)
                }
            }
        }
        .padding(.vertical, 4 * scale)
    }

    private func fileRow(_ url: URL, entry: ArchivedStack) -> some View {
        HStack(spacing: 6 * scale) {
            ThumbnailView(url: url)
                .frame(width: 18 * scale, height: 18 * scale)
            Text(url.lastPathComponent)
                .font(.system(size: 10.5 * scale))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 1.5 * scale)
        .contentShape(Rectangle())
        .overlay(
            ItemInteraction(
                onMouseDown: { _ in panel.preview.dismiss() },
                onClickUp: { _ in },
                onDoubleClick: { NSWorkspace.shared.open(url) },
                dragURLs: { [url] },
                menu: { simpleMenu(url) },
                onHover: { hovering, rect in
                    if hovering {
                        panel.preview.hover(item: FileItem(url: url), near: rect)
                    } else {
                        panel.preview.unhover(url)
                    }
                },
                onDragStarted: { panel.isDraggingFromPanel = true },
                onDragEnded: { panel.isDraggingFromPanel = false }
            )
        )
    }

    // MARK: - Menus e helpers

    private func cardMenu(_ entry: ArchivedStack) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "Renomear") {
            Task { @MainActor in
                renameText = entry.title
                renamingEntry = entry.id
            }
        })
        menu.addItem(ActionMenuItem(title: "Gerar título com IA") {
            Task { @MainActor in
                let title = await ClaudeService.stackTitle(for: entry.urls)
                StackHistoryStore.shared.rename(entry.id, to: title)
            }
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Restaurar como pilha") {
            Task { @MainActor in
                AppState.shared.panelController.restoreArchived(entry)
            }
        })
        menu.addItem(ActionMenuItem(title: "Mostrar no Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(entry.urls)
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Apagar do fichário") {
            Task { @MainActor in StackHistoryStore.shared.delete(entry.id) }
        })
        return menu
    }

    private func simpleMenu(_ url: URL) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "Abrir") { NSWorkspace.shared.open(url) })
        menu.addItem(ActionMenuItem(title: "Mostrar no Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        })
        return menu
    }
}
