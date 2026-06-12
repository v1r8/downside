import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @ObservedObject private var themeStore = ThemeStore.shared

    @EnvironmentObject private var monitor: FolderMonitor
    @EnvironmentObject private var panel: PanelController
    @EnvironmentObject private var clipboard: ClipboardMonitor
    @Environment(\.openSettings) private var openSettings

    @AppStorage(PrefKey.viewMode) private var viewModeRaw = ViewMode.grid.rawValue
    @AppStorage(PrefKey.uiScale) private var uiScaleRaw = 1.0

    @State private var selection: Set<URL> = []
    @State private var anchorIndex: Int?
    @State private var itemFrames: [URL: CGRect] = [:]
    @State private var rubberBand: CGRect?
    @State private var searchText = ""
    @State private var hoveredItem: URL?
    @State private var scrolledDown = false
    @State private var showHistory = false
    @State private var confirmClean = false
    @State private var cleaning: [(url: URL, from: CGPoint)]?
    @State private var historyDropTargeted = false

    @AppStorage(PrefKey.clipboardTimeline) private var clipboardTimeline = false
    @AppStorage(PrefKey.showDragHandle) private var showDragHandle = true
    @AppStorage(PrefKey.clipboardStyle) private var clipboardStyle = 2
    @AppStorage(PrefKey.cleanButtonEnabled) private var cleanButtonEnabled = true
    @ObservedObject private var history = StackHistoryStore.shared

    private let gridSpace = "downside.grid"

    private var mode: ViewMode {
        ViewMode(rawValue: viewModeRaw) ?? .grid
    }

    private var showStackBar: Bool {
        panel.isDraggingFromPanel || panel.externalDragActive || panel.hasStacks
    }

    /// Abertura do fichário, configurável: a área se expande a partir
    /// do botão até ocupar o painel; fechar inverte a mesma animação.
    private var historyTransition: AnyTransition {
        switch Prefs.ficharioRevealStyle {
        case 2: return .opacity
        case 3: return .identity
        default:
            return .modifier(
                active: CircleRevealModifier(progress: 0),
                identity: CircleRevealModifier(progress: 1)
            )
        }
    }

    private var revealAnimation: Animation {
        .easeInOut(duration: Prefs.ficharioRevealSpeed)
    }

    private var scale: CGFloat {
        let value = CGFloat(uiScaleRaw)
        return (0.8...2.0).contains(value) ? value : 1.0
    }

    private var parsedQuery: ParsedQuery? {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let query = NaturalSearch.parse(trimmed)
        return query.isEmpty ? nil : query
    }

    /// Itens visíveis: pasta (+ clipboard, se habilitado), filtrados
    /// pela busca.
    private var displayedItems: [FileItem] {
        var base = monitor.items
        if clipboardTimeline, !clipboard.items.isEmpty {
            let known = Set(base.map(\.url))
            base = (base + clipboard.items.filter { !known.contains($0.url) })
                .sorted { $0.date > $1.date }
        }
        guard let query = parsedQuery else { return base }
        return base.filter { NaturalSearch.matches($0, query: query) }
    }

    /// Itens da pasta com mais de 30 dias — alvo da limpeza.
    private var cleanableItems: [FileItem] {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        return monitor.items.filter { $0.date < cutoff }
    }

    /// Busca unificada: resultados das pilhas ativas e do fichário.
    private var stackHits: [URL] {
        guard let query = parsedQuery else { return [] }
        return panel.stacks.flatMap(\.urls)
            .filter { NaturalSearch.matches(FileItem(url: $0), query: query) }
    }

    /// Resultados do fichário agrupados pela pilha onde vivem.
    private var archiveGroups: [(entry: ArchivedStack, urls: [URL])] {
        guard let query = parsedQuery else { return [] }
        var groups: [(ArchivedStack, [URL])] = []
        for entry in history.archived.prefix(60) {
            let hits = entry.urls.prefix(30).filter {
                NaturalSearch.matches(FileItem(url: $0), query: query)
            }
            if !hits.isEmpty {
                groups.append((entry, Array(hits.prefix(10))))
            }
        }
        return Array(groups.prefix(12))
    }

    @ViewBuilder
    private var searchExtraSections: some View {
        if !stackHits.isEmpty {
            searchSectionHeader("Nas pilhas", icon: "square.stack.3d.up")
            ForEach(stackHits, id: \.self) { url in
                searchHitRow(url, context: nil)
            }
        }
        if !archiveGroups.isEmpty {
            searchSectionHeader("No fichário", icon: "book")
            ForEach(archiveGroups, id: \.entry.id) { group in
                // Pilha-mãe primeiro; os docs aparecem subordinados.
                HStack(spacing: 5 * scale) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 8.5 * scale))
                        .foregroundStyle(Theme.accent)
                    Text(group.entry.title)
                        .font(.system(size: 10.5 * scale, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.top, 5 * scale)
                .padding(.horizontal, 4 * scale)

                ForEach(group.urls, id: \.self) { url in
                    searchHitRow(url, context: nil)
                        .padding(.leading, 16 * scale)
                }
            }
        }
    }

    private func searchSectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 10 * scale, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10 * scale)
        .padding(.bottom, 3 * scale)
    }

    private func searchHitRow(_ url: URL, context: String?) -> some View {
        HStack(spacing: 8 * scale) {
            ThumbnailView(url: url)
                .frame(width: 22 * scale, height: 22 * scale)
            VStack(alignment: .leading, spacing: 0) {
                Text(url.lastPathComponent)
                    .font(.system(size: 11.5 * scale))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let context {
                    Text(context)
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2 * scale)
        .padding(.horizontal, 4 * scale)
        .contentShape(Rectangle())
        .overlay(
            ItemInteraction(
                onMouseDown: { _ in panel.preview.dismiss() },
                onClickUp: { _ in },
                onDoubleClick: { NSWorkspace.shared.open(url) },
                dragURLs: { [url] },
                menu: { nil },
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

            if let query = parsedQuery {
                Text(query.summary)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14 * scale)
                    .padding(.bottom, 4 * scale)
                    .minimalShadow(mode == .minimal)
            }

            if showStackBar {
                DropStackBar(scale: scale)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                    ))
            }

            if mode != .minimal {
                Divider().opacity(0.4)
            }
            if showHistory {
                HistoryOverlay(scale: scale, searchQuery: searchText)
                    .transition(historyTransition)
            } else {
                content
                    .transition(.opacity)
            }
        }
        .animation(revealAnimation, value: showHistory)
        .alert("Limpar a pasta?", isPresented: $confirmClean) {
            Button("Mover para o Lixo", role: .destructive) { startClean() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(cleanableItems.count) itens com mais de 30 dias serão movidos para o Lixo (recuperáveis)." )
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
        // Com o fichário aberto, um brilho suave respira ao longo de
        // todas as bordas do painel — fica óbvio onde você está.
        .overlay {
            if showHistory, Prefs.ficharioGlowEnabled, mode != .minimal {
                FicharioEdgeGlow(intensity: Prefs.ficharioGlowIntensity)
                    .transition(.opacity)
            }
        }
        // Fecha/abre a faixa de pilhas com mola (ex.: última pilha
        // removida pela lixeira ou menu) — o conteúdo reflui suave.
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showStackBar)
        .onReceive(NotificationCenter.default.publisher(for: .peekSelectAll)) { _ in
            selection = Set(displayedItems.map(\.url))
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
        HStack(spacing: 9 * scale) {

            // Bolha do fichário: vidro líquido suspenso, brilho
            // irisado ao clicar. Também é alvo de drop — arraste uma
            // pilha para cá para arquivá-la; durante arrastos a bolha
            // cresce e ganha o anel tracejado.
            FicharioBubble(
                scale: scale,
                isOpen: showHistory,
                dropTargeted: historyDropTargeted,
                dragActive: panel.isDraggingFromPanel || panel.externalDragActive
            ) {
                withAnimation(revealAnimation) {
                    showHistory.toggle()
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $historyDropTargeted) { providers in
                StackDropHandler.collectFileURLs(providers) { urls in
                    archiveDropped(urls)
                }
                return true
            }
            .help("Fichário de pilhas — solte uma pilha aqui para arquivar")

            // A busca é única (pasta, clipboard, pilhas e fichário).
            searchField

            // Ao selecionar, a busca encolhe e o contador surge ao lado.
            if !selection.isEmpty {
                Button {
                    selection.removeAll()
                    anchorIndex = nil
                } label: {
                    HStack(spacing: 3 * scale) {
                        Text("\(selection.count)")
                            .font(.system(size: 11 * scale, weight: .bold))
                        Image(systemName: "xmark")
                            .font(.system(size: 7 * scale, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 4 * scale)
                    .background(GlassCapsule(tint: 0.7))
                }
                .help("\(selection.count) selecionados — clique para limpar")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Cluster do canto direito: todos os ícones na MESMA caixa
            // (26×26) com o MESMO respiro entre eles.
            HStack(spacing: 3 * scale) {
                if showDragHandle {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.secondary)
                        .frame(width: 26 * scale, height: 26 * scale)
                        .contentShape(Rectangle())
                        .overlay(WindowDragHandle { panel.panelDragEnded() })
                        .help("Arraste para reposicionar — o painel encaixa na grade da tela e memoriza")
                }

                // Toggle de itens do clipboard: folha dobrada vazada;
                // ativa = preenchida.
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        clipboardTimeline.toggle()
                    }
                } label: {
                    Image(systemName: clipboardTimeline ? "doc.fill" : "doc")
                        .foregroundStyle(Color.primary)
                        .frame(width: 26 * scale, height: 26 * scale)
                        .contentShape(Rectangle())
                }
                .scaleEffect(clipboardTimeline ? 1.06 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: clipboardTimeline)
                .help(clipboardTimeline ? "Ocultar itens do clipboard" : "Mostrar itens do clipboard")

                Button {
                    panel.isPinned.toggle()
                } label: {
                    Image(systemName: panel.isPinned ? "pin.fill" : "pin")
                        .frame(width: 26 * scale, height: 26 * scale)
                        .contentShape(Rectangle())
                }
                .help(panel.isPinned ? "Liberar painel" : "Manter painel aberto")

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 26 * scale, height: 26 * scale)
                        .contentShape(Rectangle())
                }
                .help("Configurações")
            }
            .font(.system(size: 13 * scale))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 10 * scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selection.isEmpty)
    }

    private var searchField: some View {
        HStack(spacing: 4 * scale) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10 * scale))
                .foregroundStyle(.secondary)

            TextField("Buscar (ex.: pdfs de hoje)", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12 * scale))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 4 * scale)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Conteúdo

    @ViewBuilder
    private var content: some View {
        if displayedItems.isEmpty {
            emptyState
        } else {
            ScrollViewReader { scrollProxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            // LazyVStack: o rodapé de "carregar mais" só é
                            // instanciado (e dispara) quando realmente entra
                            // na área visível, ao rolar até o fim.
                            LazyVStack(spacing: 0) {
                                layout
                                if parsedQuery != nil {
                                    searchExtraSections
                                }
                                if monitor.isTruncated {
                                    LoadMoreFooter(scale: scale) {
                                        monitor.increaseLimit()
                                    }
                                }
                            }
                            .padding(mode == .grid ? 10 * scale : 12 * scale)
                            .background(emptyAreaCatcher)

                            if let rect = rubberBand {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.tint(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .strokeBorder(Theme.tint(0.5), lineWidth: 1)
                                    )
                                    .frame(width: rect.width, height: rect.height)
                                    .offset(x: rect.minX, y: rect.minY)
                                    .allowsHitTesting(false)
                            }

                            if let cleaning {
                                CleanDeckOverlay(
                                    cards: cleaning,
                                    center: deckCenter,
                                    scale: scale
                                ) {
                                    finishClean()
                                }
                            }
                        }
                        .id("downside.top")
                        .coordinateSpace(name: gridSpace)
                        .simultaneousGesture(rubberBandGesture)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ScrollOffsetKey.self,
                                    value: proxy.frame(in: .named("downside.viewport")).minY
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "downside.viewport")
                    .onPreferenceChange(ScrollOffsetKey.self) { minY in
                        scrolledDown = minY < -250
                    }

                    VStack(spacing: 8 * scale) {
                        if scrolledDown {
                            BackToTopButton(scale: scale) {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    scrollProxy.scrollTo("downside.top", anchor: .top)
                                }
                            }
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }

                        if cleanButtonEnabled {
                            CleanCardsButton(scale: scale) {
                                guard cleaning == nil else { return }
                                if cleanableItems.isEmpty {
                                    NSSound.beep()
                                } else {
                                    confirmClean = true
                                }
                            }
                        }
                    }
                    .padding(12 * scale)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scrolledDown)
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
                ForEach(displayedItems) { item in
                    interactive(item) {
                        FileCell(
                            item: item,
                            isSelected: selection.contains(item.url),
                            scale: scale,
                            isHovered: hoveredItem == item.url
                        )
                    }
                }
            }
        case .list:
            LazyVStack(spacing: 2) {
                ForEach(displayedItems) { item in
                    HStack(spacing: 6 * scale) {
                        interactive(item) {
                            FileRow(
                                item: item,
                                isSelected: selection.contains(item.url),
                                scale: scale,
                                isHovered: hoveredItem == item.url
                            )
                        }
                        if item.url.pathExtension.lowercased() == "ics" {
                            CalendarAddButton(url: item.url, scale: scale)
                        } else if item.url.pathExtension.lowercased() == "dmg" {
                            DMGActionButton(url: item.url, scale: scale)
                        }
                    }
                }
            }
        case .minimal:
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(displayedItems) { item in
                    interactive(item) {
                        MinimalFileRow(
                            item: item,
                            isSelected: selection.contains(item.url),
                            scale: scale,
                            isHovered: hoveredItem == item.url
                        )
                    }
                }
            }
        }
    }

    private func isClipboardItem(_ item: FileItem) -> Bool {
        item.url.path.contains("/Downside/Clipboard/")
    }

    /// Aplica a cada item os comportamentos comuns a todos os modos:
    /// rastreio de posição (rubber band) e a camada nativa de interação
    /// (cliques, arrasto múltiplo, menu de contexto e hover).
    private func interactive<Content: View>(
        _ item: FileItem,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            // Nomeação inteligente: só itens que ficaram visíveis
            // entram na fila (a LLM local nomeia um por vez).
            .task(id: item.url) { SmartNameStore.shared.ensureName(item) }
            .modifier(ClipboardMark(
                active: isClipboardItem(item),
                style: clipboardStyle,
                scale: scale
            ))
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
                    // Texto do clipboard é arrastado como TEXTO (cola no
                    // destino), não como upload de arquivo .txt.
                    dragText: (isClipboardItem(item) && item.url.pathExtension == "txt")
                        ? { try? String(contentsOf: item.url, encoding: .utf8) }
                        : nil,
                    menu: { contextMenu(for: item) },
                    onHover: { hovering, rect in
                        if hovering {
                            hoveredItem = item.url
                            panel.preview.hover(item: item, near: rect)
                        } else {
                            if hoveredItem == item.url { hoveredItem = nil }
                            panel.preview.unhover(item.url)
                        }
                    },
                    onDragStarted: { panel.isDraggingFromPanel = true },
                    onDragEnded: { panel.isDraggingFromPanel = false }
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
            Image(systemName: parsedQuery != nil ? "magnifyingglass" : "tray")
                .font(.system(size: 32 * scale))
                .foregroundStyle(.tertiary)
            Text(parsedQuery != nil ? "Nada encontrado para a busca" : "Pasta vazia")
                .font(.system(size: 13 * scale))
                .foregroundStyle(.secondary)
                .minimalShadow(mode == .minimal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Arquiva uma pilha arrastada para o livrinho: se as URLs casam
    /// com uma pilha ativa, ela é arquivada e liberada; senão, cria-se
    /// uma ficha nova com o que foi solto.
    private func archiveDropped(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let dropped = Set(urls)
        let matching = panel.stacks.first { Set($0.urls) == dropped }
        let snapshot = matching ?? FileStack(urls: urls)
        StackHistoryStore.shared.archiveAndName(snapshot)
        if let matching {
            panel.clearStack(matching.id)
        }
    }

    // MARK: - Limpeza com deck

    private var deckCenter: CGPoint {
        let union = itemFrames.values.reduce(nil as CGRect?) { partial, frame in
            partial?.union(frame) ?? frame
        }
        guard let union else { return CGPoint(x: 220, y: 160) }
        return CGPoint(x: union.midX, y: min(union.minY + 170, union.midY))
    }

    private func startClean() {
        let victims = cleanableItems
        guard !victims.isEmpty else { return }
        let visible = victims.compactMap { item -> (url: URL, from: CGPoint)? in
            guard let frame = itemFrames[item.url] else { return nil }
            return (url: item.url, from: CGPoint(x: frame.midX, y: frame.midY))
        }
        if visible.isEmpty {
            finishClean()
        } else {
            cleaning = Array(visible.prefix(12))
        }
    }

    private func finishClean() {
        for item in cleanableItems {
            try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        }
        selection.removeAll()
        cleaning = nil
        monitor.reload()
    }

    // MARK: - Seleção (semântica do Finder)

    private func mouseDown(on item: FileItem, modifiers: NSEvent.ModifierFlags) {
        panel.preview.dismiss()
        // displayedItems: inclui itens de clipboard (que não estão no
        // monitor da pasta) — multi-seleção vale para todos.
        guard let index = displayedItems.firstIndex(of: item) else { return }

        if modifiers.contains(.command) {
            if selection.contains(item.url) {
                selection.remove(item.url)
            } else {
                selection.insert(item.url)
            }
            anchorIndex = index
        } else if modifiers.contains(.shift), let anchor = anchorIndex {
            let items = displayedItems
            let upper = min(max(anchor, index), items.count - 1)
            let lower = min(min(anchor, index), upper)
            selection.formUnion(items[lower...upper].map(\.url))
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
        anchorIndex = displayedItems.firstIndex(of: item)
    }

    /// Alvo das ações: a seleção, se o item fizer parte dela; senão,
    /// apenas o item (como no Finder). Mantém a ordem da listagem.
    private func targets(for item: FileItem) -> [URL] {
        if selection.contains(item.url) {
            return displayedItems.filter { selection.contains($0.url) }.map(\.url)
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
        if Prefs.smartNamesEnabled, urls.count == 1, let url = urls.first {
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem(title: "Nomear com IA") {
                Task { @MainActor in
                    SmartNameStore.shared.requestName(FileItem(url: url), force: true)
                }
            })
            if SmartNameStore.shared.hasName(url) {
                menu.addItem(ActionMenuItem(title: "Usar nome original") {
                    Task { @MainActor in SmartNameStore.shared.clearName(url) }
                })
            }
        }
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
        // Docs do clipboard saem da lista junto (paridade com a pasta).
        clipboard.remove(urls)
        monitor.reload()
    }
}

/// Rodapé que aparece ao rolar até o fim quando há mais itens: um
/// círculo se preenche pela circunferência e o próximo lote carrega.
private struct LoadMoreFooter: View {
    let scale: CGFloat
    var onComplete: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        HStack(spacing: 8 * scale) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Theme.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16 * scale, height: 16 * scale)

            Text("Carregando mais itens…")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12 * scale)
        .onAppear {
            progress = 0
            withAnimation(.easeInOut(duration: 0.7)) {
                progress = 1
            }
            Task {
                try? await Task.sleep(nanoseconds: 750_000_000)
                onComplete()
            }
        }
    }
}

/// Distinção visual dos itens vindos do clipboard — 5 estilos à escolha
/// nas configurações.
struct ClipboardMark: ViewModifier {
    let active: Bool
    let style: Int
    let scale: CGFloat

    /// Visibilidade ajustável nas configurações.
    private var boost: Double { Prefs.clipboardMarkIntensity }

    func body(content: Content) -> some View {
        if !active {
            content
        } else {
            switch style {
            case 1: // Borda tracejada
                content.overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            Theme.tint(0.5 * boost),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                )
            case 2: // Selo de clipboard
                content.overlay(alignment: .topTrailing) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 8 * scale * boost))
                        .foregroundStyle(Theme.accent)
                        .padding(3 * scale)
                        .allowsHitTesting(false)
                }
            case 3: // Barra lateral
                content.overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.tint(min(1, 0.7 * boost)))
                        .frame(width: Prefs.clipboardBarWidth)
                        .padding(.vertical, 4 * scale)
                        .allowsHitTesting(false)
                }
            case 4: // Degradê suave
                content.background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.tint(0.12 * boost), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            default: // 5: Etiqueta CLIP
                content.overlay(alignment: .bottomTrailing) {
                    Text("CLIP")
                        .font(.system(size: 6.5 * scale * boost, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4 * scale)
                        .padding(.vertical, 1.5 * scale)
                        .background(Capsule().fill(Theme.tint(0.8)))
                        .padding(3 * scale)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Botão flutuante de limpeza: um mini-deck de cartas em círculo de
/// vidro bem transparente. As cartas se abrem em leque no hover e dão
/// uma embaralhada no clique — satisfatório de apertar.
private struct CleanCardsButton: View {
    let scale: CGFloat
    var action: () -> Void

    @State private var fanned = false
    @State private var shuffling = false

    var body: some View {
        Button {
            shuffling = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 280_000_000)
                shuffling = false
                action()
            }
        } label: {
            ZStack {
                card(angle: fanned ? -16 : -5, offset: -3)
                card(angle: fanned ? 16 : 5, offset: 3)
                card(angle: 0, offset: 0)
            }
            .rotationEffect(.degrees(shuffling ? 12 : 0))
            .animation(
                shuffling
                    ? .easeInOut(duration: 0.07).repeatCount(4, autoreverses: true)
                    : .spring(response: 0.3, dampingFraction: 0.6),
                value: shuffling
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: fanned)
            .frame(width: 40 * scale, height: 40 * scale)
        }
        .buttonStyle(.borderless)
        .background(glassCircle)
        .onHover { fanned = $0 }
        .help("Limpar: mover itens com +30 dias para o Lixo")
    }

    private func card(angle: Double, offset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.2)
            )
            .overlay(
                // "Linhas" da carta, para ler como documento.
                VStack(spacing: 2.5 * scale) {
                    Capsule().frame(width: 7 * scale, height: 1)
                    Capsule().frame(width: 7 * scale, height: 1)
                    Capsule().frame(width: 4.5 * scale, height: 1)
                }
                .foregroundStyle(Color.primary.opacity(0.35))
            )
            .frame(width: 13 * scale, height: 17.5 * scale)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .rotationEffect(.degrees(angle))
            .offset(x: offset * scale)
    }

    @ViewBuilder
    private var glassCircle: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Circle())
        } else {
            legacyGlass
        }
        #else
        legacyGlass
        #endif
    }

    private var legacyGlass: some View {
        Circle()
            .fill(.regularMaterial)
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

/// Botão circular de voltar ao topo, em vidro (liquid glass no Tahoe,
/// material translúcido como fallback).
private struct BackToTopButton: View {
    let scale: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34 * scale, height: 34 * scale)
        }
        .buttonStyle(.borderless)
        .background(glassCircle)
        .help("Voltar ao topo")
    }

    @ViewBuilder
    private var glassCircle: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Circle())
        } else {
            legacyGlass
        }
        #else
        legacyGlass
        #endif
    }

    private var legacyGlass: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
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

/// Bolha do fichário: círculo de vidro líquido suspenso (sombra
/// flutuante), com um leve pulso ao clicar. Durante arrastos vira
/// alvo de drop com anel tracejado e cresce SÓ visualmente
/// (scaleEffect) — a caixa de layout não muda, então o resto do
/// cabeçalho fica parado.
private struct FicharioBubble: View {
    @ObservedObject private var themeStore = ThemeStore.shared

    let scale: CGFloat
    let isOpen: Bool
    let dropTargeted: Bool
    let dragActive: Bool
    var action: () -> Void

    @State private var popping = false

    private var visualScale: CGFloat {
        dropTargeted ? 1.35 : (dragActive ? 1.1 : 1)
    }

    var body: some View {
        Button {
            playPop()
            action()
        } label: {
            Image(systemName: isOpen ? "book.fill" : "book")
                .font(.system(size: 12.5 * scale))
                .foregroundStyle(
                    dropTargeted || dragActive ? Theme.accent : Color.primary
                )
                .frame(width: 28 * scale, height: 28 * scale)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .background(glass)
        .background(
            Circle().fill(Theme.tint(dropTargeted ? 0.18 : (dragActive ? 0.08 : 0)))
        )
        .overlay(
            Circle()
                .strokeBorder(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .opacity(dragActive || dropTargeted ? 1 : 0)
        )
        .scaleEffect(visualScale * (popping ? 1.1 : 1))
        .animation(
            dropTargeted
                ? .spring(response: 0.28, dampingFraction: 0.74)
                : .spring(response: 0.45, dampingFraction: 1.0),
            value: dropTargeted
        )
        .animation(
            dragActive
                ? .spring(response: 0.32, dampingFraction: 0.78)
                : .spring(response: 0.5, dampingFraction: 1.0),
            value: dragActive
        )
        .animation(.spring(response: 0.26, dampingFraction: 0.62), value: popping)
        .zIndex(10)
    }

    private func playPop() {
        popping = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            popping = false
        }
    }

    @ViewBuilder
    private var glass: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Circle())
        } else {
            legacyGlass
        }
        #else
        legacyGlass
        #endif
    }

    private var legacyGlass: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
    }
}

/// Abertura do fichário: um círculo que nasce na bolha e se expande
/// até revelar o painel inteiro; fechar encolhe de volta (a mesma
/// animação, invertida pelo próprio SwiftUI).
private struct CircleRevealModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .clipShape(RevealCircle(progress: progress))
            .opacity(progress < 0.12 ? Double(progress / 0.12) : 1)
    }
}

private struct RevealCircle: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Centro na posição aproximada da bolha (acima, à esquerda).
        let center = CGPoint(x: rect.minX + 26, y: rect.minY - 20)
        let reach = hypot(rect.width, rect.height) + 40
        let radius = max(1, 10 + progress * reach)
        return Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}

/// Brilho suave que respira ao longo das bordas do painel enquanto o
/// fichário está aberto (cor de destaque; intensidade configurável).
private struct FicharioEdgeGlow: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    let intensity: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathe = 0.82 + 0.18 * sin(t * 1.6)
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        Theme.tint(min(1, 0.6 * intensity * breathe)),
                        lineWidth: 1.2
                    )
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        Theme.tint(min(1, 0.38 * intensity * breathe)),
                        lineWidth: 5
                    )
                    .blur(radius: 6)
            }
        }
        .allowsHitTesting(false)
    }
}
