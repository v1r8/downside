import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let paneFill = Color.primary.opacity(0.05)
private let paneStroke = Color.primary.opacity(0.1)
private let barSpace = "downside.stackbar"

/// Faixa fixa no topo do painel com as pilhas temporárias (até 3, lado
/// a lado), no estilo de abas de navegador: aba ativa e painel de
/// conteúdo são UMA única forma contínua (mesma borda, mesmos cantos
/// arredondados). Abrir revela o conteúdo crescendo para baixo; trocar
/// de pilha desliza a "corcova" da aba e troca o conteúdo, sem fechar.
struct DropStackBar: View {
    @ObservedObject private var themeStore = ThemeStore.shared

    @EnvironmentObject private var panel: PanelController
    let scale: CGFloat

    @State private var expanded: UUID?
    /// Mantém a forma de fundo durante a animação de fechamento.
    @State private var lastDetailID: UUID?
    /// Debounce: cliques frenéticos não empilham transações.
    @State private var lastToggle = Date.distantPast
    @State private var chipFrames: [UUID: CGRect] = [:]
    /// Namespace do "deck de cartas": os ícones viajam entre o leque do
    /// chip e as linhas da lista expandida.
    @Namespace private var deck

    private var detailStack: FileStack? {
        guard let expanded else { return nil }
        return panel.stacks.first { $0.id == expanded }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8 * scale) {
                // Lixeira à ESQUERDA da seção de pilhas, durante arrastos.
                if panel.isDraggingFromPanel || panel.externalDragActive {
                    TrashDropTarget(scale: scale)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                ForEach(panel.stacks) { stack in
                    StackChip(
                        stack: stack,
                        scale: scale,
                        isActive: expanded == stack.id,
                        deck: deck,
                        onToggleExpand: { toggle(stack.id) }
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ChipFramesKey.self,
                                value: [stack.id: proxy.frame(in: .named(barSpace))]
                            )
                        }
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                if panel.isDraggingFromPanel || panel.externalDragActive,
                   panel.stacks.count < PanelController.maxStacks {
                    NewStackTarget(scale: scale)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }

            // Conteúdo expandido: entra/sai por fade (a altura anima no
            // layout) enquanto os ícones fazem o voo de deck de cartas.
            if let stack = detailStack {
                StackDetailContent(stack: stack, scale: scale, deck: deck) {
                    toggle(stack.id)
                }
                .id(stack.id)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                ))
            }
        }
        .background(unifiedTabBackground)
        .coordinateSpace(name: barSpace)
        .onPreferenceChange(ChipFramesKey.self) { chipFrames = $0 }
        .padding(.horizontal, 12 * scale)
        .padding(.bottom, 6 * scale)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: panel.stacks)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: panel.isDraggingFromPanel)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: panel.externalDragActive)
        .onChange(of: panel.stacks) { _, stacks in
            if let id = expanded, !stacks.contains(where: { $0.id == id }) {
                expanded = nil
            }
        }
    }

    private func toggle(_ id: UUID) {
        // Ignora rajadas de cliques no meio de uma transição.
        guard Date().timeIntervalSince(lastToggle) > 0.18 else { return }
        lastToggle = Date()

        if expanded == id {
            // Fechamento: UMA transação só — altura, pescoço da aba,
            // fade da forma e voo das cartas juntos, sem fase intermediária.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                expanded = nil
            }
        } else if expanded != nil {
            // Troca de aba: crossfade curto e ágil, sem empilhar molas.
            lastDetailID = id
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded = id
            }
        } else {
            // Abertura: mola viva.
            lastDetailID = id
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                expanded = id
            }
        }
    }

    /// Forma única aba+painel: fica atrás dos chips e do conteúdo,
    /// desenhada com a "corcova" sob a aba ativa. Some em fade no
    /// fechamento, enquanto o fundo próprio do chip volta em fade.
    @ViewBuilder
    private var unifiedTabBackground: some View {
        GeometryReader { proxy in
            if let id = expanded ?? lastDetailID, let tab = chipFrames[id] {
                let shape = TabPaneShape(
                    tabMinX: tab.minX,
                    tabMaxX: tab.maxX,
                    paneTop: tab.maxY,
                    // No fechamento o painel recolhe para dentro da aba.
                    collapse: expanded == nil ? 1 : 0,
                    radius: 10
                )
                ZStack {
                    shape.fill(paneFill)
                    shape.stroke(paneStroke, lineWidth: 1)
                }
                .opacity(expanded == nil ? 0 : 1)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

private struct ChipFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Contorno contínuo de aba + painel (estilo aba de navegador), com a
/// posição da aba animável — trocar de pilha desliza a corcova.
struct TabPaneShape: Shape {
    var tabMinX: CGFloat
    var tabMaxX: CGFloat
    var paneTop: CGFloat
    /// 0 = painel aberto na largura toda · 1 = recolhido na largura da
    /// aba. No fechamento as laterais retraem para DENTRO da aba, então
    /// nunca passam sob os chips vizinhos.
    var collapse: CGFloat = 0
    var radius: CGFloat = 10
    /// Filete côncavo onde o pescoço da aba encontra o painel —
    /// nenhum canto abrupto na junção.
    var fillet: CGFloat = 6

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(tabMinX, tabMaxX), AnimatablePair(paneTop, collapse)) }
        set {
            tabMinX = newValue.first.first
            tabMaxX = newValue.first.second
            paneTop = newValue.second.first
            collapse = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let r = radius
        let top = min(paneTop, rect.maxY)
        let minX = max(rect.minX, min(tabMinX, rect.maxX - 2 * r))
        let maxX = min(rect.maxX, max(tabMaxX, minX + 2 * r))
        let c = max(0, min(1, collapse))
        // Laterais do painel interpolam da largura total para a aba.
        let paneLeft = rect.minX + (minX - rect.minX) * c
        let paneRight = rect.maxX - (rect.maxX - maxX) * c
        // Painel ainda fechado (altura ~zero): desenha só a aba.
        let paneVisible = rect.maxY - top > 1
        let rightFillet = paneVisible && maxX + fillet < paneRight - r
        let leftFillet = paneVisible && minX - fillet > paneLeft + r

        var path = Path()
        path.move(to: CGPoint(x: minX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: minX + r, y: rect.minY + r),
            radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.addLine(to: CGPoint(x: maxX - r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: maxX - r, y: rect.minY + r),
            radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
        )

        if paneVisible {
            if rightFillet {
                path.addLine(to: CGPoint(x: maxX, y: top - fillet))
                path.addArc(
                    center: CGPoint(x: maxX + fillet, y: top - fillet),
                    radius: fillet, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
                )
                path.addLine(to: CGPoint(x: paneRight - r, y: top))
                path.addArc(
                    center: CGPoint(x: paneRight - r, y: top + r),
                    radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
                )
            } else if maxX < paneRight - r {
                path.addLine(to: CGPoint(x: maxX, y: top))
                path.addLine(to: CGPoint(x: paneRight - r, y: top))
                path.addArc(
                    center: CGPoint(x: paneRight - r, y: top + r),
                    radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
                )
            } else {
                path.addLine(to: CGPoint(x: paneRight, y: top))
            }
            path.addLine(to: CGPoint(x: paneRight, y: rect.maxY - r))
            path.addArc(
                center: CGPoint(x: paneRight - r, y: rect.maxY - r),
                radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
            )
            path.addLine(to: CGPoint(x: paneLeft + r, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: paneLeft + r, y: rect.maxY - r),
                radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
            )
            if leftFillet {
                path.addLine(to: CGPoint(x: paneLeft, y: top + r))
                path.addArc(
                    center: CGPoint(x: paneLeft + r, y: top + r),
                    radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
                )
                path.addLine(to: CGPoint(x: minX - fillet, y: top))
                path.addArc(
                    center: CGPoint(x: minX - fillet, y: top - fillet),
                    radius: fillet, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true
                )
            } else if minX > paneLeft + r {
                path.addLine(to: CGPoint(x: paneLeft, y: top + r))
                path.addArc(
                    center: CGPoint(x: paneLeft + r, y: top + r),
                    radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
                )
                path.addLine(to: CGPoint(x: minX, y: top))
            } else {
                path.addLine(to: CGPoint(x: paneLeft, y: top))
                path.addLine(to: CGPoint(x: minX, y: top))
            }
        } else {
            path.addLine(to: CGPoint(x: maxX, y: top))
            path.addLine(to: CGPoint(x: minX, y: top))
        }

        path.addLine(to: CGPoint(x: minX, y: rect.minY + r))
        path.closeSubpath()
        return path
    }
}

/// Pilha compacta (a "aba"): ícones em leque + contagem. Clique só
/// expande/recolhe; arrastar leva tudo; segurar um arrasto em cima
/// substitui o conteúdo (com preenchimento de progresso no fundo).
private struct StackChip: View {
    @EnvironmentObject private var panel: PanelController
    let stack: FileStack
    let scale: CGFloat
    let isActive: Bool
    let deck: Namespace.ID
    let onToggleExpand: () -> Void

    @State private var targeted = false
    @State private var replaceProgress: CGFloat = 0
    @State private var replaceTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6 * scale) {
            // Indicador de bulk action, estilo "estrela à esquerda".
            if stack.hadBulkAction, Prefs.bulkBadgeStyle == 2 {
                Image(systemName: "sparkles")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(Theme.output)
            }

            if stack.urls.isEmpty || isActive {
                // Deck "vazio" enquanto as cartas estão na lista.
                Image(systemName: "tray")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(.secondary)
                    .opacity(isActive ? 0.45 : 1)
                    .frame(width: 36 * scale, alignment: .leading)
            } else {
                // Leque na ordem de inserção: o primeiro adicionado é a
                // carta da frente — espelhando a ordem da lista.
                ZStack(alignment: .leading) {
                    ForEach(Array(stack.urls.prefix(3).enumerated()), id: \.element) { index, url in
                        ThumbnailView(url: url)
                            .frame(width: 22 * scale, height: 22 * scale)
                            .padding(.leading, CGFloat(index) * 6 * scale)
                            .rotationEffect(.degrees(Double(index) * 3 - 3))
                            .zIndex(Double(3 - index))
                            // O chip é a âncora da geometria: na retração
                            // as cartas voam direto para cá, sem teleporte.
                            .matchedGeometryEffect(
                                id: "\(stack.id)-\(url.path)",
                                in: deck,
                                isSource: true
                            )
                    }

                    // Indicador "carta no fim do deck": uma cartinha na
                    // cor dos outputs fecha o leque.
                    if stack.hadBulkAction, Prefs.bulkBadgeStyle == 1 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Theme.outputTint(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8)
                            )
                            .frame(width: 9 * scale, height: 13 * scale)
                            .rotationEffect(.degrees(9))
                            .padding(.leading, 21 * scale)
                            .zIndex(10)
                    }
                }
                .frame(width: 36 * scale, alignment: .leading)
            }

            Text("\(stack.urls.count)")
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 2 * scale)
                .background(GlassCapsule(tint: 0.7))
                .overlay(alignment: .topTrailing) {
                    // Indicador "ponto no contador".
                    if stack.hadBulkAction, Prefs.bulkBadgeStyle == 3 {
                        Circle()
                            .fill(Theme.output)
                            .frame(width: 5 * scale, height: 5 * scale)
                            .offset(x: 2 * scale, y: -2 * scale)
                    }
                }

            Image(systemName: isActive ? "chevron.up" : "chevron.down")
                .font(.system(size: 8 * scale, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8 * scale)
        .padding(.top, 5 * scale)
        // A aba ativa desce até o painel; as outras ficam com respiro
        // proporcional ao espaçamento lateral. O encolhimento anima na
        // mesma transação do fechamento (paneTop da forma é animável).
        .padding(.bottom, (isActive ? 17 : 5) * scale)
        .frame(maxWidth: .infinity)
        .background(chipBackground)
        .scaleEffect(targeted ? 1.05 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: targeted)
        .overlay(
            ItemInteraction(
                onMouseDown: { _ in },
                onClickUp: { _ in onToggleExpand() },
                // Clique duplo também só alterna — nunca abre arquivos.
                onDoubleClick: onToggleExpand,
                dragURLs: { stack.urls },
                menu: { contextMenu() },
                onHover: { hovering, _ in
                    // Pairar no chip mostra o preview de TODOS os docs
                    // da pilha, ao lado do painel.
                    if hovering {
                        panel.hoverStackPreview(stack)
                    } else {
                        panel.unhoverStackPreview(stack.id)
                    }
                },
                onDragStarted: { panel.isDraggingFromPanel = true },
                onDragEnded: { panel.isDraggingFromPanel = false }
            )
        )
        .onDrop(
            of: StackDropHandler.acceptedTypes,
            delegate: StackDropDelegate(
                onEntered: dropEntered,
                onExited: dropExited,
                onPerform: { providers in
                    dropExited()
                    return StackDropHandler.accept(providers) { url in
                        panel.addToStack(stack.id, url: url)
                    }
                }
            )
        )
        .help("Clique para ver o conteúdo · arraste para levar tudo · segure um arrasto para substituir")
    }

    /// Fundo próprio do chip: some quando a aba está ativa (a forma
    /// unificada assume), volta em fade no fechamento. Progresso do
    /// segurar-para-substituir e highlight de drop ficam por cima.
    private var chipBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack(alignment: .leading) {
            shape.fill(targeted ? Theme.tint(0.13) : paneFill)
                .opacity(isActive ? (targeted ? 1 : 0) : 1)
            shape.strokeBorder(paneStroke, lineWidth: 1)
                .opacity(isActive ? 0 : 1)

            if replaceProgress > 0 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Theme.tint(0.25))
                        .frame(width: proxy.size.width * replaceProgress)
                }
                .clipShape(shape)
            }

            if targeted {
                shape.strokeBorder(Theme.accent, lineWidth: 1)
            }
        }
    }

    private func dropEntered() {
        targeted = true
        guard !stack.urls.isEmpty else { return }

        let delay = Prefs.stackReplaceDelay
        replaceProgress = 0
        withAnimation(.linear(duration: delay)) {
            replaceProgress = 1
        }
        let id = stack.id
        replaceTask?.cancel()
        replaceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            panel.replaceStack(id)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            withAnimation(.easeOut(duration: 0.2)) {
                replaceProgress = 0
            }
        }
    }

    private func dropExited() {
        targeted = false
        replaceTask?.cancel()
        replaceTask = nil
        withAnimation(.easeOut(duration: 0.15)) {
            replaceProgress = 0
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let urls = stack.urls
        menu.addItem(ActionMenuItem(title: "Abrir todos") {
            urls.forEach { NSWorkspace.shared.open($0) }
        })
        menu.addItem(ActionMenuItem(title: "Mostrar no Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        })
        menu.addItem(.separator())
        let id = stack.id
        menu.addItem(ActionMenuItem(title: "Limpar pilha") {
            Task { @MainActor in AppState.shared.panelController.clearStack(id) }
        })
        return menu
    }
}

/// Alvo tracejado para criar uma nova pilha durante um arrasto.
private struct NewStackTarget: View {
    @EnvironmentObject private var panel: PanelController
    let scale: CGFloat

    @State private var targeted = false

    var body: some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: "plus")
            Text(panel.stacks.isEmpty ? "Solte para empilhar" : "Nova pilha")
        }
        .font(.system(size: 11 * scale))
        .foregroundStyle(targeted ? Theme.accent : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(targeted ? Theme.tint(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    targeted ? Theme.accent : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .scaleEffect(targeted ? 1.04 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: targeted)
        .onDrop(
            of: StackDropHandler.acceptedTypes,
            delegate: StackDropDelegate(
                onEntered: { targeted = true },
                onExited: { targeted = false },
                onPerform: { providers in
                    targeted = false
                    return StackDropHandler.accept(providers) { url in
                        panel.addToStack(nil, url: url)
                    }
                }
            )
        )
    }
}

/// Pílula de ação em massa, com texto completo (configurável).
struct BulkActionPill: View {
    let item: BulkActionItem
    let scale: CGFloat
    var action: () -> Void

    private var needsKey: Bool {
        (item.id == "resumo" || item.id == "chaves") && !ClaudeService.hasKey
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3 * scale) {
                Image(systemName: item.icon)
                    .font(.system(size: 9 * scale, weight: .semibold))
                Text(item.title)
                    .font(.system(size: 9.5 * scale, weight: .semibold))
                    .fixedSize()
            }
            .padding(.horizontal, 7 * scale)
            .padding(.vertical, 3.5 * scale)
            .background(
                Capsule().fill(Color.primary.opacity(needsKey ? 0.05 : 0.08))
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .foregroundStyle(needsKey ? Color.secondary.opacity(0.5) : Color.primary)
        }
        .buttonStyle(.borderless)
        .disabled(needsKey)
        .help(needsKey ? "Configure a chave da API em Configurações → IA" : item.title)
    }
}

/// Lixeira de arrasto: aparece ao lado de "Nova pilha" durante drags.
/// Solte arquivos para mandá-los ao Lixo; uma pilha ativa é liberada e
/// uma ficha do fichário é apagada do histórico (arquivos preservados).
private struct TrashDropTarget: View {
    @EnvironmentObject private var panel: PanelController
    let scale: CGFloat

    @State private var targeted = false

    var body: some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: "trash")
            Text("Lixo")
        }
        .font(.system(size: 11 * scale))
        .foregroundStyle(targeted ? Color.red : Color.secondary)
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 9 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(targeted ? Color.red.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    targeted ? Color.red : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .fixedSize()
        .scaleEffect(targeted ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            StackDropHandler.collectFileURLs(providers) { urls in
                handleTrashDrop(urls)
            }
            return true
        }
        .help("Solte para mover ao Lixo")
    }

    @MainActor
    private func handleTrashDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let dropped = Set(urls)

        // Ficha do fichário? Apaga só a ficha (os arquivos ficam).
        if let entry = StackHistoryStore.shared.archived.first(where: { Set($0.urls) == dropped }) {
            StackHistoryStore.shared.delete(entry.id)
            return
        }
        // Pilha ativa? Libera a pilha e manda os arquivos ao Lixo.
        if let stack = AppState.shared.panelController.stacks.first(where: { Set($0.urls) == dropped }) {
            AppState.shared.panelController.clearStack(stack.id)
        }
        for url in urls {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

/// Conteúdo do painel da aba: as "cartas" pousam aqui vindas do leque
/// do chip (matched geometry). Também é alvo de drop, com o mesmo
/// highlight azul dos chips. Sem fundo próprio — a forma unificada da
/// barra cuida do visual.
private struct StackDetailContent: View {
    @EnvironmentObject private var panel: PanelController
    let stack: FileStack
    let scale: CGFloat
    let deck: Namespace.ID
    var onClose: () -> Void

    @State private var targeted = false
    @StateObject private var runner = BulkActionRunner()
    @ObservedObject private var actionConfig = BulkActionConfigStore.shared

    /// Despacha uma ação configurada pelo id.
    private func perform(_ id: String) {
        switch id {
        case "abrir":
            stack.urls.forEach { NSWorkspace.shared.open($0) }
        case "pdf":
            runner.run("Gerando PDF…", stack: stack, panel: panel) {
                try await runner.makePDF(from: $0)
            }
        case "links":
            runner.run("Baixando…", stack: stack, panel: panel) {
                try await runner.downloadLinks(from: $0)
            }
        case "resumo":
            guard ClaudeService.hasKey else { return }
            runner.run("Resumindo…", stack: stack, panel: panel) {
                try await runner.summarize($0)
            }
        case "chaves":
            guard ClaudeService.hasKey else { return }
            runner.run("Caracterizando…", stack: stack, panel: panel) {
                try await runner.keywords($0)
            }
        case "arquivar":
            let snapshot = stack
            Task { @MainActor in
                let title = await ClaudeService.stackTitle(for: snapshot.urls)
                StackHistoryStore.shared.archive(snapshot, title: title)
                panel.clearStack(snapshot.id)
            }
            onClose()
        default:
            break
        }
    }

    private var originals: [URL] {
        stack.urls.filter { !stack.outputs.contains($0) }
    }

    private var outputs: [URL] {
        stack.urls.filter { stack.outputs.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(originals, id: \.self) { url in
                        row(url)
                    }
                }
                .padding(6 * scale)
            }
            .frame(maxHeight: 170 * scale)

            // Outputs de ações em massa: fixados na base, lado a lado,
            // como mini-pilhas.
            if !outputs.isEmpty {
                Divider().opacity(0.3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6 * scale) {
                        ForEach(outputs, id: \.self) { url in
                            outputChip(url)
                        }
                    }
                    .padding(.horizontal, 8 * scale)
                    .padding(.vertical, 5 * scale)
                }
            }

            Divider().opacity(0.3)

            // Pílulas de ação com texto completo, configuráveis nas
            // Configurações → Pilhas; rolagem horizontal (a roda
            // vertical também rola, sempre com movimento horizontal).
            HStack(spacing: 6 * scale) {
                if let label = runner.runningLabel {
                    ProgressView().controlSize(.mini)
                    Text(label)
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    HorizontalWheelScroller {
                        HStack(spacing: 6 * scale) {
                            ForEach(actionConfig.items.filter(\.enabled)) { item in
                                BulkActionPill(item: item, scale: scale) {
                                    perform(item.id)
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
            .buttonStyle(.borderless)
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 5 * scale)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.tint(targeted ? 0.08 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1)
                .opacity(targeted ? 1 : 0)
        )
        .animation(.easeOut(duration: 0.12), value: targeted)
        .onDrop(
            of: StackDropHandler.acceptedTypes,
            delegate: StackDropDelegate(
                onEntered: { targeted = true },
                onExited: { targeted = false },
                onPerform: { providers in
                    targeted = false
                    return StackDropHandler.accept(providers) { url in
                        panel.addToStack(stack.id, url: url)
                    }
                }
            )
        )
    }

    /// Mini-chip de output: ✨ à esquerda, X à direita para apagar;
    /// arrastável, com preview no hover e menu de reaplicar.
    private func outputChip(_ url: URL) -> some View {
        HStack(spacing: 5 * scale) {
            HStack(spacing: 5 * scale) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8 * scale))
                    .foregroundStyle(Theme.output)
                ThumbnailView(url: url)
                    .frame(width: 18 * scale, height: 18 * scale)
                Text(url.lastPathComponent)
                    .font(.system(size: 10 * scale))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 110 * scale)
            }
            .contentShape(Rectangle())
            .overlay(
                ItemInteraction(
                    onMouseDown: { _ in panel.preview.dismiss() },
                    onClickUp: { _ in },
                    onDoubleClick: { NSWorkspace.shared.open(url) },
                    dragURLs: { [url] },
                    menu: { outputMenu(url) },
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

            Button {
                panel.removeFromStack(stack.id, url: url)
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Apagar output")
        }
        .padding(.horizontal, 7 * scale)
        .padding(.vertical, 4 * scale)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.outputTint(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.outputTint(0.35), lineWidth: 1)
        )
    }

    private func outputMenu(_ url: URL) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "Abrir") {
            NSWorkspace.shared.open(url)
        })
        menu.addItem(ActionMenuItem(title: "Mostrar no Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        })
        menu.addItem(.separator())

        let reapply = NSMenuItem(title: "Reaplicar ação", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let snapshot = stack
        submenu.addItem(ActionMenuItem(title: "Gerar PDF") { [runner] in
            Task { @MainActor in
                runner.run("Gerando PDF…", stack: snapshot, panel: AppState.shared.panelController) {
                    try await runner.makePDF(from: $0)
                }
            }
        })
        submenu.addItem(ActionMenuItem(title: "Baixar links") { [runner] in
            Task { @MainActor in
                runner.run("Baixando…", stack: snapshot, panel: AppState.shared.panelController) {
                    try await runner.downloadLinks(from: $0)
                }
            }
        })
        submenu.addItem(ActionMenuItem(title: "Resumir com IA") { [runner] in
            Task { @MainActor in
                runner.run("Resumindo…", stack: snapshot, panel: AppState.shared.panelController) {
                    try await runner.summarize($0)
                }
            }
        })
        submenu.addItem(ActionMenuItem(title: "Palavras-chave com IA") { [runner] in
            Task { @MainActor in
                runner.run("Caracterizando…", stack: snapshot, panel: AppState.shared.panelController) {
                    try await runner.keywords($0)
                }
            }
        })
        reapply.submenu = submenu
        menu.addItem(reapply)

        menu.addItem(.separator())
        let id = stack.id
        menu.addItem(ActionMenuItem(title: "Apagar output") {
            Task { @MainActor in
                AppState.shared.panelController.removeFromStack(id, url: url)
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        })
        return menu
    }

    private func row(_ url: URL) -> some View {
        let isOutput = stack.outputs.contains(url)
        return HStack(spacing: 6 * scale) {
            HStack(spacing: 8 * scale) {
                ThumbnailView(url: url)
                    .frame(width: 26 * scale, height: 26 * scale)
                    .matchedGeometryEffect(
                        id: "\(stack.id)-\(url.path)",
                        in: deck,
                        isSource: false
                    )
                Text(url.lastPathComponent)
                    .font(.system(size: 11.5 * scale))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isOutput {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9 * scale))
                        .foregroundStyle(Theme.output)
                        .help("Gerado por ação em massa")
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .overlay(
                ItemInteraction(
                    onMouseDown: { _ in panel.preview.dismiss() },
                    onClickUp: { _ in },
                    onDoubleClick: { NSWorkspace.shared.open(url) },
                    dragURLs: { [url] },
                    menu: { rowMenu(url) },
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

            Button {
                panel.removeFromStack(stack.id, url: url)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remover da pilha")
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 2 * scale)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isOutput ? Theme.outputTint(0.1) : Color.clear)
        )
    }

    private func rowMenu(_ url: URL) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "Abrir") {
            NSWorkspace.shared.open(url)
        })
        menu.addItem(ActionMenuItem(title: "Mostrar no Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        })
        menu.addItem(.separator())
        let id = stack.id
        menu.addItem(ActionMenuItem(title: "Remover da pilha") {
            Task { @MainActor in AppState.shared.panelController.removeFromStack(id, url: url) }
        })
        return menu
    }
}

/// Delegate de drop que força semântica de CÓPIA (nunca mover o
/// original) e expõe enter/exit para o segurar-para-substituir.
struct StackDropDelegate: DropDelegate {
    let onEntered: () -> Void
    let onExited: () -> Void
    let onPerform: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: StackDropHandler.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        onEntered()
    }

    func dropExited(info: DropInfo) {
        onExited()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        onPerform(info.itemProviders(for: StackDropHandler.acceptedTypes))
    }
}

/// Resolve drops em URLs de arquivo. As pilhas são independentes das
/// pastas: arquivos locais entram por referência (nunca movidos);
/// conteúdo da web/imagens/texto é salvo num cofre próprio do app.
enum StackDropHandler {
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .utf8PlainText]

    static func accept(_ providers: [NSItemProvider], add: @escaping (URL) -> Void) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                loadFileURL(provider, add: add)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                saveImage(provider, add: add)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true
                resolveWebURL(provider, add: add)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                accepted = true
                saveText(provider, add: add)
            }
        }
        return accepted
    }

    // MARK: - Origens

    private static func loadFileURL(_ provider: NSItemProvider, add: @escaping (URL) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            if let url = urlFrom(data) {
                Task { @MainActor in add(url) }
            }
        }
    }

    private static func saveImage(_ provider: NSItemProvider, add: @escaping (URL) -> Void) {
        let identifier = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        }
        guard let identifier else { return }
        let ext = UTType(identifier)?.preferredFilenameExtension ?? "png"

        provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
            guard var data else { return }
            var finalExt = ext
            if finalExt == "tiff" || finalExt == "tif",
               let rep = NSBitmapImageRep(data: data),
               let png = rep.representation(using: .png, properties: [:]) {
                data = png
                finalExt = "png"
            }
            let destination = uniqueDestination(name: "Imagem \(timestamp())", ext: finalExt)
            do {
                try data.write(to: destination)
                Task { @MainActor in add(destination) }
            } catch {}
        }
    }

    private static func resolveWebURL(_ provider: NSItemProvider, add: @escaping (URL) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
            guard let url = urlFrom(data) else { return }
            if url.isFileURL {
                Task { @MainActor in add(url) }
                return
            }
            Task {
                guard let (temp, response) = try? await URLSession.shared.download(from: url) else { return }
                var name = response.suggestedFilename ?? url.lastPathComponent
                if name.isEmpty || name == "/" { name = "Download \(timestamp())" }
                let destination = uniqueDestination(filename: name)
                try? FileManager.default.moveItem(at: temp, to: destination)
                await MainActor.run { add(destination) }
            }
        }
    }

    private static func saveText(_ provider: NSItemProvider, add: @escaping (URL) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, _ in
            guard let data, !data.isEmpty else { return }
            let destination = uniqueDestination(name: "Texto \(timestamp())", ext: "txt")
            do {
                try data.write(to: destination)
                Task { @MainActor in add(destination) }
            } catch {}
        }
    }

    // MARK: - Helpers

    /// Resolve todos os fileURLs de um drop de uma vez (para alvos que
    /// precisam do conjunto completo, como o fichário).
    static func collectFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let queue = DispatchQueue(label: "downside.collect")
        for provider in providers
        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                if let url = urlFrom(data) {
                    queue.sync { urls.append(url) }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(urls)
        }
    }

    private static func urlFrom(_ data: (any NSSecureCoding)?) -> URL? {
        if let data = data as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let url = data as? URL {
            return url
        }
        if let string = data as? String {
            return URL(string: string)
        }
        return nil
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    /// Cofre próprio do app para conteúdo capturado de drops — as
    /// pilhas não dependem da pasta monitorada.
    private static func stashDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Downside/Pilhas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func uniqueDestination(name: String, ext: String) -> URL {
        uniqueDestination(filename: "\(name).\(ext)")
    }

    private static func uniqueDestination(filename: String) -> URL {
        let folder = stashDirectory()
        var candidate = folder.appendingPathComponent(filename)
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }
}
