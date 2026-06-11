import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let paneFill = Color.primary.opacity(0.05)

/// Faixa fixa no topo do painel com as pilhas temporárias (até 3, lado
/// a lado), no estilo de abas de navegador: o chip expandido se funde
/// com o painel de conteúdo logo abaixo. Trocar de pilha com uma aberta
/// só troca o conteúdo (ágil, sem recolher/abrir).
struct DropStackBar: View {
    @EnvironmentObject private var panel: PanelController
    let scale: CGFloat

    @State private var expanded: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8 * scale) {
                ForEach(panel.stacks) { stack in
                    StackChip(
                        stack: stack,
                        scale: scale,
                        isExpanded: expanded == stack.id,
                        onToggleExpand: {
                            expanded = expanded == stack.id ? nil : stack.id
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
            .zIndex(1)

            if let id = expanded, let stack = panel.stacks.first(where: { $0.id == id }) {
                StackDetail(stack: stack, scale: scale) {
                    expanded = nil
                }
                .id(stack.id)
                .transition(.expandDown)
            }
        }
        .padding(.horizontal, 12 * scale)
        .padding(.bottom, 6 * scale)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: panel.stacks)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: panel.isDraggingFromPanel)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: panel.externalDragActive)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: expanded)
        .onChange(of: panel.stacks) { _, stacks in
            if let id = expanded, !stacks.contains(where: { $0.id == id }) {
                expanded = nil
            }
        }
    }
}

/// O retângulo da pilha "cresce para baixo" ao abrir.
private struct VerticalExpandModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: max(progress, 0.01), anchor: .top)
            .opacity(Double(progress))
    }
}

private extension AnyTransition {
    static let expandDown = AnyTransition.modifier(
        active: VerticalExpandModifier(progress: 0),
        identity: VerticalExpandModifier(progress: 1)
    )
}

/// Pilha compacta (a "aba"): ícones em leque + contagem. Clique só
/// expande/recolhe; arrastar leva tudo; segurar um arrasto em cima por
/// alguns segundos substitui o conteúdo (com preenchimento de progresso
/// no fundo).
private struct StackChip: View {
    @EnvironmentObject private var panel: PanelController
    let stack: FileStack
    let scale: CGFloat
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    @State private var targeted = false
    @State private var replaceProgress: CGFloat = 0
    @State private var replaceTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6 * scale) {
            if stack.urls.isEmpty {
                Image(systemName: "tray")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(.secondary)
                    .frame(width: 36 * scale, alignment: .leading)
            } else {
                ZStack(alignment: .leading) {
                    ForEach(Array(stack.urls.suffix(3).enumerated()), id: \.element) { index, url in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 22 * scale, height: 22 * scale)
                            .offset(x: CGFloat(index) * 6 * scale)
                            .rotationEffect(.degrees(Double(index) * 3 - 3))
                    }
                }
                .frame(width: 36 * scale, alignment: .leading)
            }

            Text("\(stack.urls.count)")
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 2 * scale)
                .background(Capsule().fill(Color.accentColor))

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8 * scale, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8 * scale)
        .padding(.top, 5 * scale)
        // A aba ativa desce até encostar no painel de conteúdo.
        .padding(.bottom, isExpanded ? 11 * scale : 5 * scale)
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
                onHover: { _, _ in },
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

    @ViewBuilder
    private var chipBackground: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 10,
            bottomLeadingRadius: isExpanded ? 0 : 10,
            bottomTrailingRadius: isExpanded ? 0 : 10,
            topTrailingRadius: 10,
            style: .continuous
        )
        ZStack(alignment: .leading) {
            shape.fill(targeted ? Color.accentColor.opacity(0.13) : paneFill)

            // Preenchimento de progresso do "segurar para substituir".
            if replaceProgress > 0 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(width: proxy.size.width * replaceProgress)
                }
                .clipShape(shape)
            }

            if !isExpanded {
                shape.strokeBorder(
                    targeted ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
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
        .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    targeted ? Color.accentColor : Color.secondary.opacity(0.4),
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

/// Painel de conteúdo da aba: lista com previews, itens entrando em
/// cascata; cantos superiores retos sob a aba ativa (fusão visual).
private struct StackDetail: View {
    @EnvironmentObject private var panel: PanelController
    let stack: FileStack
    let scale: CGFloat
    var onClose: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(stack.urls.enumerated()), id: \.element) { index, url in
                        row(url)
                            .offset(y: appeared ? 0 : -12)
                            .opacity(appeared ? 1 : 0)
                            .rotationEffect(.degrees(appeared ? 0 : Double(min(index, 6)) * 1.5 - 1.5))
                            .animation(
                                .spring(response: 0.32, dampingFraction: 0.74)
                                    .delay(Double(min(index, 10)) * 0.028),
                                value: appeared
                            )
                    }
                }
                .padding(6 * scale)
            }
            .frame(maxHeight: 190 * scale)

            Divider().opacity(0.3)

            HStack {
                Button("Abrir todos") {
                    stack.urls.forEach { NSWorkspace.shared.open($0) }
                }
                Spacer()
                Button("Limpar pilha", role: .destructive) {
                    panel.clearStack(stack.id)
                    onClose()
                }
            }
            .font(.system(size: 10.5 * scale))
            .buttonStyle(.borderless)
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 5 * scale)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 6,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                topTrailingRadius: 6,
                style: .continuous
            )
            .fill(paneFill)
        )
        .onAppear { appeared = true }
    }

    private func row(_ url: URL) -> some View {
        HStack(spacing: 6 * scale) {
            HStack(spacing: 8 * scale) {
                ThumbnailView(url: url)
                    .frame(width: 26 * scale, height: 26 * scale)
                Text(url.lastPathComponent)
                    .font(.system(size: 11.5 * scale))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .overlay(
                ItemInteraction(
                    onMouseDown: { _ in },
                    onClickUp: { _ in },
                    onDoubleClick: { NSWorkspace.shared.open(url) },
                    dragURLs: { [url] },
                    menu: { rowMenu(url) },
                    onHover: { _, _ in },
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
