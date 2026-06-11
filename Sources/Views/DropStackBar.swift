import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Faixa fixa no topo do painel com as pilhas temporárias (até 3, lado
/// a lado). Durante um arrasto aparece também o alvo de nova pilha.
/// Clicar numa pilha expande a lista do que há dentro.
struct DropStackBar: View {
    @EnvironmentObject private var panel: PanelController
    let scale: CGFloat

    @State private var expandedStack: UUID?

    var body: some View {
        VStack(spacing: 6 * scale) {
            HStack(spacing: 8 * scale) {
                ForEach(panel.stacks) { stack in
                    StackChip(
                        stack: stack,
                        scale: scale,
                        isExpanded: expandedStack == stack.id,
                        onToggleExpand: { toggleExpanded(stack.id) }
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                if panel.isDraggingFromPanel, panel.stacks.count < PanelController.maxStacks {
                    NewStackTarget(scale: scale)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }

            if let id = expandedStack, let stack = panel.stacks.first(where: { $0.id == id }) {
                StackDetail(stack: stack, scale: scale)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12 * scale)
        .padding(.bottom, 6 * scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: panel.stacks)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: panel.isDraggingFromPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: expandedStack)
        .onChange(of: panel.stacks) { _, stacks in
            if let id = expandedStack, !stacks.contains(where: { $0.id == id }) {
                expandedStack = nil
            }
        }
    }

    private func toggleExpanded(_ id: UUID) {
        expandedStack = expandedStack == id ? nil : id
    }
}

/// Pilha compacta: ícones em leque + contagem. Arrastável (leva tudo),
/// alvo de drop, clique expande.
private struct StackChip: View {
    @EnvironmentObject private var panel: PanelController
    let stack: FileStack
    let scale: CGFloat
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    @State private var targeted = false

    var body: some View {
        HStack(spacing: 6 * scale) {
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
        .padding(.vertical, 5 * scale)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    targeted ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .scaleEffect(targeted ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: targeted)
        .overlay(
            ItemInteraction(
                onMouseDown: { _ in },
                onClickUp: { _ in onToggleExpand() },
                onDoubleClick: { stack.urls.forEach { NSWorkspace.shared.open($0) } },
                dragURLs: { stack.urls },
                menu: { contextMenu() },
                onHover: { _, _ in },
                onDragStarted: { panel.isDraggingFromPanel = true },
                onDragEnded: { panel.isDraggingFromPanel = false }
            )
        )
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            StackDropHandler.accept(providers) { url in
                panel.addToStack(stack.id, url: url)
            }
        }
        .help("Clique para ver o conteúdo · arraste para levar tudo")
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
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            StackDropHandler.accept(providers) { url in
                panel.addToStack(nil, url: url)
            }
        }
    }
}

/// Conteúdo expandido de uma pilha: lista com remoção individual.
private struct StackDetail: View {
    @EnvironmentObject private var panel: PanelController
    let stack: FileStack
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(stack.urls, id: \.self) { url in
                        HStack(spacing: 6 * scale) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 16 * scale, height: 16 * scale)
                            Text(url.lastPathComponent)
                                .font(.system(size: 11 * scale))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
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
                        .padding(.horizontal, 8 * scale)
                        .padding(.vertical, 2 * scale)
                    }
                }
            }
            .frame(maxHeight: 140 * scale)

            HStack {
                Button("Abrir todos") {
                    stack.urls.forEach { NSWorkspace.shared.open($0) }
                }
                Spacer()
                Button("Limpar pilha", role: .destructive) {
                    panel.clearStack(stack.id)
                }
            }
            .font(.system(size: 10.5 * scale))
            .buttonStyle(.borderless)
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 4 * scale)
        }
        .padding(.vertical, 4 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

/// Resolve providers de drop em URLs de arquivo.
enum StackDropHandler {
    static func accept(_ providers: [NSItemProvider], add: @escaping (URL) -> Void) -> Bool {
        var accepted = false
        for provider in providers
        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                let url: URL?
                if let data = data as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = data as? URL {
                    url = direct
                } else {
                    url = nil
                }
                if let url {
                    Task { @MainActor in add(url) }
                }
            }
        }
        return accepted
    }
}
