import SwiftUI
import AppKit

/// Fichário: histórico de pilhas arquivadas. Fichas expansíveis (com
/// preview por item e outputs fixados), arrastáveis de volta para as
/// pilhas provisórias, renomeáveis (manual ou por IA), com
/// multi-seleção. A busca usa a barra principal do painel.
struct HistoryOverlay: View {
    @ObservedObject private var themeStore = ThemeStore.shared

    @ObservedObject private var store = StackHistoryStore.shared
    @EnvironmentObject private var panel: PanelController
    let scale: CGFloat
    let searchQuery: String

    @State private var selection: Set<UUID> = []
    @State private var expandedEntry: UUID?
    @State private var renamingEntry: UUID?
    @State private var renameText = ""
    @State private var listDropTargeted = false
    @StateObject private var runner = BulkActionRunner()
    @ObservedObject private var actionConfig = BulkActionConfigStore.shared
    @AppStorage(PrefKey.historyLayout) private var layoutRaw = 1
    @AppStorage("ficharioFavoritesCollapsed") private var favoritesCollapsed = false
    /// Deck de cartas do fichário: os ícones voam entre o leque da
    /// ficha e as linhas do conteúdo expandido (como nas pilhas).
    @Namespace private var deck

    /// Organizações do fichário: lista + 5 alternativas.
    enum HistoryLayout: Int, CaseIterable {
        case list = 1, grid, compact, timeline, mosaic, shelves

        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid: return "square.grid.2x2"
            case .compact: return "rectangle.compress.vertical"
            case .timeline: return "calendar.day.timeline.left"
            case .mosaic: return "circle.grid.3x3"
            case .shelves: return "books.vertical"
            }
        }

        var label: String {
            switch self {
            case .list: return "Lista"
            case .grid: return "Grade"
            case .compact: return "Compacta"
            case .timeline: return "Linha do tempo"
            case .mosaic: return "Mosaico"
            case .shelves: return "Estantes"
            }
        }
    }

    private var layout: HistoryLayout {
        HistoryLayout(rawValue: layoutRaw) ?? .list
    }

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

    /// Seção de favoritas no topo; o resto vem abaixo (se não há
    /// favoritas, a lista fica como sempre foi, sem cabeçalhos).
    private var favoriteEntries: [ArchivedStack] {
        filtered.filter(\.isFavorite)
    }

    private var regularEntries: [ArchivedStack] {
        favoriteEntries.isEmpty ? filtered : filtered.filter { !$0.isFavorite }
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
                    Button("Limpar") {
                        selection.removeAll()
                    }
                    .font(.system(size: 10.5 * scale))
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 2 * scale)
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
                // Nos modos de mosaico/grade/estantes, a ficha aberta
                // vira um cartão fixado no topo.
                if usesPinnedDetail, let id = expandedEntry,
                   let entry = filtered.first(where: { $0.id == id }) {
                    detailCard(entry)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ScrollView {
                    switch layout {
                    case .list:
                        LazyVStack(spacing: 4 * scale) {
                            if !favoriteEntries.isEmpty {
                                favoritesHeader
                                if !favoritesCollapsed {
                                    ForEach(favoriteEntries) { entry in
                                        card(entry)
                                    }
                                }
                                sectionHeader("Todas")
                            }
                            ForEach(regularEntries) { entry in
                                card(entry)
                            }
                        }
                    case .compact:
                        LazyVStack(spacing: 2) {
                            if !favoriteEntries.isEmpty {
                                favoritesHeader
                                if !favoritesCollapsed {
                                    ForEach(favoriteEntries) { entry in
                                        compactRow(entry)
                                    }
                                }
                                sectionHeader("Todas")
                            }
                            ForEach(regularEntries) { entry in
                                compactRow(entry)
                            }
                        }
                    case .grid:
                        LazyVStack(spacing: 6 * scale) {
                            if !favoriteEntries.isEmpty {
                                favoritesHeader
                                if !favoritesCollapsed {
                                    historyGrid(favoriteEntries, minimum: 140, maximum: 190)
                                }
                                sectionHeader("Todas")
                            }
                            historyGrid(regularEntries, minimum: 140, maximum: 190)
                        }
                    case .mosaic:
                        LazyVStack(spacing: 6 * scale) {
                            if !favoriteEntries.isEmpty {
                                favoritesHeader
                                if !favoritesCollapsed {
                                    historyGrid(favoriteEntries, minimum: 64, maximum: 84, mosaic: true)
                                }
                                sectionHeader("Todas")
                            }
                            historyGrid(regularEntries, minimum: 64, maximum: 84, mosaic: true)
                        }
                    case .timeline:
                        LazyVStack(spacing: 4 * scale) {
                            if !favoriteEntries.isEmpty {
                                favoritesHeader
                                if !favoritesCollapsed {
                                    ForEach(favoriteEntries) { entry in
                                        card(entry)
                                    }
                                }
                            }
                            ForEach(timelineGroups, id: \.0) { group in
                                sectionHeader(group.0)
                                ForEach(group.1) { entry in
                                    card(entry)
                                }
                            }
                        }
                    case .shelves:
                        LazyVStack(alignment: .leading, spacing: 8 * scale) {
                            if !favoriteEntries.isEmpty {
                                favoritesHeader
                                if !favoritesCollapsed {
                                    shelfRow(favoriteEntries)
                                }
                            }
                            ForEach(shelfGroups, id: \.0) { group in
                                sectionHeader(group.0)
                                shelfRow(group.1)
                            }
                        }
                    }
                }
            }
        }
        .padding(10 * scale)
        // A lista inteira também é alvo de drop: solte uma pilha (ou
        // docs) em qualquer lugar do fichário aberto para arquivar —
        // alternativa a mirar na bolha.
        .overlay {
            if listDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.tint(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                Theme.accent,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                    )
                    .padding(4 * scale)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $listDropTargeted) { providers in
            StackDropHandler.collectFileURLs(providers) { urls in
                archiveDropped(urls)
            }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: listDropTargeted)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: expandedEntry)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: selection)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: layoutRaw)
    }

    private var usesPinnedDetail: Bool {
        layout == .grid || layout == .mosaic || layout == .shelves
    }

    /// Agrupamentos da linha do tempo.
    private var timelineGroups: [(String, [ArchivedStack])] {
        let calendar = Calendar.current
        let now = Date()
        func bucket(_ date: Date) -> String {
            if calendar.isDateInToday(date) { return "Hoje" }
            if calendar.isDateInYesterday(date) { return "Ontem" }
            if let week = calendar.dateInterval(of: .weekOfYear, for: now),
               week.contains(date) { return "Esta semana" }
            if let month = calendar.dateInterval(of: .month, for: now),
               month.contains(date) { return "Este mês" }
            return "Anteriores"
        }
        let order = ["Hoje", "Ontem", "Esta semana", "Este mês", "Anteriores"]
        let grouped = Dictionary(grouping: regularEntries) { bucket($0.date) }
        return order.compactMap { key in
            grouped[key].map { (key, $0) }
        }
    }

    /// Estantes por mês.
    private var shelfGroups: [(String, [ArchivedStack])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL 'de' yyyy"
        formatter.locale = Locale(identifier: "pt_BR")
        var seen: [String] = []
        var grouped: [String: [ArchivedStack]] = [:]
        for entry in regularEntries {
            let key = formatter.string(from: entry.date).capitalized
            if grouped[key] == nil { seen.append(key) }
            grouped[key, default: []].append(entry)
        }
        return seen.map { ($0, grouped[$0] ?? []) }
    }

    private func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 4 * scale) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8.5 * scale))
                    .foregroundStyle(.yellow)
            }
            Text(title)
        }
        .font(.system(size: 10 * scale, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4 * scale)
    }

    /// Grade reaproveitada pelas seções (favoritas + todas).
    private func historyGrid(
        _ entries: [ArchivedStack],
        minimum: CGFloat,
        maximum: CGFloat,
        mosaic: Bool = false
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimum * scale, maximum: maximum * scale), spacing: 6 * scale)],
            spacing: 6 * scale
        ) {
            ForEach(entries) { entry in
                if mosaic {
                    mosaicTile(entry)
                } else {
                    gridTile(entry)
                }
            }
        }
    }

    private func shelfRow(_ entries: [ArchivedStack]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6 * scale) {
                ForEach(entries) { entry in
                    gridTile(entry)
                        .frame(width: 150 * scale)
                }
            }
        }
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
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.accent : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
    }


    /// Título da ficha: efeito mágico enquanto a IA nomeia.
    @ViewBuilder
    private func entryTitle(_ entry: ArchivedStack, size: CGFloat, lines: Int = 1) -> some View {
        if store.namingIDs.contains(entry.id) {
            MagicNamePlaceholder(scale: scale)
        } else {
            Text(entry.title.isEmpty ? "Sem título" : entry.title)
                .font(.system(size: size * scale, weight: .semibold))
                .lineLimit(lines)
        }
    }

    // MARK: - Componentes compartilhados

    /// Leque de ícones da ficha, com o indicador de bulk action
    /// "carta no fim do deck" quando configurado.
    private func fan(_ entry: ArchivedStack, size: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(entry.urls.prefix(3).enumerated()), id: \.offset) { index, url in
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: size * scale, height: size * scale)
                    .padding(.leading, CGFloat(index) * size * 0.25 * scale)
                    .rotationEffect(.degrees(Double(index) * 3 - 3))
                    // Profundidade explícita: sem isto a carta holográfica
                    // sempre ficava à frente, ignorando a configuração.
                    .zIndex(Double(3 - index))
                    // O leque é a âncora: ao expandir/fechar a ficha, as
                    // cartas voam daqui para as linhas e de volta.
                    .matchedGeometryEffect(
                        id: "fich-\(entry.id)-\(url.path)",
                        in: deck,
                        isSource: true
                    )
            }
            if entry.hadBulkAction, !entry.outputPaths.isEmpty, Prefs.bulkBadgeStyle == 1 {
                HoloCardBadge(
                    width: size * 0.62 * scale,
                    height: size * 0.9 * scale
                )
                .rotationEffect(.degrees(-10))
                .offset(x: -size * 0.3 * scale)
                .zIndex(Prefs.holoCardFront ? 20 : 0)
            }
        }
        .frame(width: size * 1.7 * scale, alignment: .leading)
    }

    /// Arquiva o que foi solto sobre a lista do fichário: pilha ativa
    /// vira ficha (e é liberada); ficha já existente não duplica.
    private func archiveDropped(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let dropped = Set(urls)
        guard !store.archived.contains(where: { Set($0.urls) == dropped }) else { return }
        let matching = panel.stacks.first { Set($0.urls) == dropped }
        let snapshot = matching ?? FileStack(urls: urls)
        store.archiveAndName(snapshot)
        if let matching {
            panel.clearStack(matching.id)
        }
    }

    /// Cabeçalho da seção de favoritas: clique expande/oculta.
    private var favoritesHeader: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                favoritesCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 4 * scale) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8.5 * scale))
                    .foregroundStyle(.yellow)
                Text("Favoritas")
                Text("\(favoriteEntries.count)")
                    .foregroundStyle(.tertiary)
                Image(systemName: favoritesCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 7 * scale, weight: .semibold))
                Spacer()
            }
            .font(.system(size: 10 * scale, weight: .semibold))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.top, 4 * scale)
        .help(favoritesCollapsed ? "Mostrar favoritas" : "Ocultar favoritas")
    }

    /// Estrelinha de favorita (indicador discreto junto ao título).
    @ViewBuilder
    private func favStar(_ entry: ArchivedStack) -> some View {
        if entry.isFavorite {
            Image(systemName: "star.fill")
                .font(.system(size: 8 * scale))
                .foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private func bulkStar(_ entry: ArchivedStack) -> some View {
        if entry.hadBulkAction, !entry.outputPaths.isEmpty, Prefs.bulkBadgeStyle == 2 {
            Image(systemName: "sparkles")
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundStyle(Theme.output)
        }
    }

    @ViewBuilder
    private func bulkDot(_ entry: ArchivedStack) -> some View {
        if entry.hadBulkAction, !entry.outputPaths.isEmpty, Prefs.bulkBadgeStyle == 3 {
            Circle()
                .fill(Theme.output)
                .frame(width: 5 * scale, height: 5 * scale)
        }
    }

    /// Interação comum às variantes (clique expande, ⌘ seleciona,
    /// duplo expande, arrasto restaura, menu, hover-preview).
    private func tileInteraction(_ entry: ArchivedStack) -> ItemInteraction {
        let isSelected = selection.contains(entry.id)
        let isExpanded = expandedEntry == entry.id
        return ItemInteraction(
            onMouseDown: { _ in },
            onClickUp: { modifiers in
                if modifiers.contains(.command) {
                    if isSelected { selection.remove(entry.id) } else { selection.insert(entry.id) }
                } else {
                    expandedEntry = isExpanded ? nil : entry.id
                }
            },
            onDoubleClick: { expandedEntry = isExpanded ? nil : entry.id },
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
    }

    // MARK: - Variantes de organização

    private func compactRow(_ entry: ArchivedStack) -> some View {
        let isSelected = selection.contains(entry.id)
        let isExpanded = expandedEntry == entry.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6 * scale) {
                favStar(entry)
                bulkStar(entry)
                entryTitle(entry, size: 11)
                bulkDot(entry)
                Spacer()
                Text("\(entry.paths.count)")
                    .font(.system(size: 9.5 * scale))
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7.5 * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 4 * scale)
            .contentShape(Rectangle())
            .overlay(tileInteraction(entry))

            if isExpanded {
                Divider().opacity(0.3)
                expandedContent(entry)
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 1)
        )
    }

    private func gridTile(_ entry: ArchivedStack) -> some View {
        let isSelected = selection.contains(entry.id)
        return VStack(spacing: 5 * scale) {
            HStack(spacing: 4 * scale) {
                favStar(entry)
                bulkStar(entry)
                fan(entry, size: 26)
            }
            entryTitle(entry, size: 10.5, lines: 2)
                .multilineTextAlignment(.center)
            HStack(spacing: 4 * scale) {
                Text("\(entry.paths.count) docs")
                bulkDot(entry)
            }
            .font(.system(size: 9 * scale))
            .foregroundStyle(.secondary)
        }
        .padding(8 * scale)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.accent
                        : (expandedEntry == entry.id ? Theme.tint(0.6) : Color.primary.opacity(0.07)),
                    lineWidth: 1
                )
        )
        .overlay(tileInteraction(entry))
        .help(entry.title)
    }

    private func mosaicTile(_ entry: ArchivedStack) -> some View {
        let isSelected = selection.contains(entry.id)
        return VStack(spacing: 3 * scale) {
            HStack(spacing: 3 * scale) {
                favStar(entry)
                bulkStar(entry)
                fan(entry, size: 22)
            }
            HStack(spacing: 3 * scale) {
                Text("\(entry.paths.count)")
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5 * scale)
                    .padding(.vertical, 1.5 * scale)
                    .background(GlassCapsule(tint: 0.7))
                bulkDot(entry)
            }
        }
        .padding(6 * scale)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.accent
                        : (expandedEntry == entry.id ? Theme.tint(0.6) : Color.clear),
                    lineWidth: 1
                )
        )
        .overlay(tileInteraction(entry))
        .help(entry.title)
    }

    /// Cartão de detalhe fixado no topo (grade/mosaico/estantes).
    private func detailCard(_ entry: ArchivedStack) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6 * scale) {
                bulkStar(entry)
                entryTitle(entry, size: 11.5)
                Spacer()
                Button {
                    expandedEntry = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 5 * scale)

            Divider().opacity(0.3)
            expandedContent(entry)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.tint(0.4), lineWidth: 1)
        )
    }

    private func header(_ entry: ArchivedStack, isSelected: Bool, isExpanded: Bool) -> some View {
        HStack(spacing: 8 * scale) {
            HStack(spacing: 8 * scale) {
                bulkStar(entry)
                fan(entry, size: 20)

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
                        entryTitle(entry, size: 11.5)
                    }
                    HStack(spacing: 4 * scale) {
                        Text("\(entry.paths.count) docs · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                        bulkDot(entry)
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

            // Favoritar direto da ficha: a estrela fica fora da camada
            // de interação, então o clique não expande a ficha.
            Button {
                store.toggleFavorite(entry.id)
            } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(entry.isFavorite ? Color.yellow : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.borderless)
            .help(entry.isFavorite ? "Remover dos favoritos" : "Favoritar")

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8 * scale, weight: .semibold))
                .foregroundStyle(.secondary)
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
                            // Mesmo racional das pilhas: ✨ à esquerda,
                            // X à direita para apagar.
                            HStack(spacing: 5 * scale) {
                                HStack(spacing: 5 * scale) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8 * scale))
                                        .foregroundStyle(Theme.output)
                                    ThumbnailView(url: url)
                                        .frame(width: 16 * scale, height: 16 * scale)
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 9.5 * scale))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: 100 * scale)
                                }
                                .contentShape(Rectangle())
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

                                Button {
                                    store.removeOutput(entry.id, url: url)
                                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 9 * scale))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Apagar output")
                            }
                            .padding(.horizontal, 6 * scale)
                            .padding(.vertical, 3 * scale)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.outputTint(0.12))
                            )
                            .overlay(HoloShimmer(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Theme.outputTint(0.35), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 4 * scale)
                }
            }

            // Mesmas ações em massa da pilha expandida — os outputs são
            // anexados à ficha (e ela ganha o fundo destacado).
            Divider().opacity(0.3)
            HStack(spacing: 6 * scale) {
                if let label = runner.runningLabel {
                    ProgressView().controlSize(.mini)
                    Text(label)
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.secondary)
                } else {
                    HorizontalWheelScroller {
                        HStack(spacing: 6 * scale) {
                            ForEach(actionConfig.items.filter { $0.enabled && $0.id != "arquivar" }) { item in
                                BulkActionPill(item: item, scale: scale) {
                                    performArchived(item.id, entry: entry)
                                }
                            }
                        }
                        .padding(.horizontal, 2 * scale)
                    }
                    .frame(height: 24 * scale)

                    if let message = runner.message {
                        Text(message)
                            .font(.system(size: 10 * scale))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 4 * scale)
        }
        .padding(.vertical, 4 * scale)
    }

    private func performArchived(_ id: String, entry: ArchivedStack) {
        switch id {
        case "abrir":
            entry.urls.forEach { NSWorkspace.shared.open($0) }
        case "pdf":
            runner.runArchived("Gerando PDF…", entry: entry) {
                try await runner.makePDF(from: $0)
            }
        case "links":
            runner.runArchived("Baixando…", entry: entry) {
                try await runner.downloadLinks(from: $0)
            }
        case "resumo":
            runner.runArchived("Resumindo…", entry: entry) {
                try await runner.summarize($0)
            }
        case "chaves":
            runner.runArchived("Caracterizando…", entry: entry) {
                try await runner.keywords($0)
            }
        default:
            break
        }
    }

    private func fileRow(_ url: URL, entry: ArchivedStack) -> some View {
        HStack(spacing: 6 * scale) {
            ThumbnailView(url: url)
                .frame(width: 18 * scale, height: 18 * scale)
                .matchedGeometryEffect(
                    id: "fich-\(entry.id)-\(url.path)",
                    in: deck,
                    isSource: false
                )
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
                StackHistoryStore.shared.regenerateTitle(entry)
            }
        })
        menu.addItem(ActionMenuItem(
            title: entry.isFavorite ? "Remover dos favoritos" : "Favoritar"
        ) {
            Task { @MainActor in
                StackHistoryStore.shared.toggleFavorite(entry.id)
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
