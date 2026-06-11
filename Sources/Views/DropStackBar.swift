import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Barra fixa no topo do painel: zona de soltar discreta que vira uma
/// pilha temporária de arquivos. Aparece quando um arrasto começa no
/// painel (ou enquanto a pilha tiver itens) e fica fora do scroll, então
/// dá para rolar a lista e ir empilhando.
struct DropStackBar: View {
    @EnvironmentObject private var panel: PanelController
    let scale: CGFloat

    @State private var targeted = false

    var body: some View {
        Group {
            if panel.stackURLs.isEmpty {
                dropPrompt
            } else {
                stackRow
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            handleDrop(providers)
        }
        .padding(.horizontal, 12 * scale)
        .padding(.bottom, 6 * scale)
    }

    private var dropPrompt: some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: "tray.and.arrow.down")
            Text("Solte aqui para empilhar")
        }
        .font(.system(size: 11 * scale))
        .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8 * scale)
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
        .animation(.easeOut(duration: 0.12), value: targeted)
    }

    private var stackRow: some View {
        HStack(spacing: 8 * scale) {
            HStack(spacing: 8 * scale) {
                ZStack(alignment: .leading) {
                    ForEach(Array(panel.stackURLs.suffix(4).enumerated()), id: \.element) { index, url in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 26 * scale, height: 26 * scale)
                            .offset(x: CGFloat(index) * 7 * scale)
                    }
                }
                .frame(width: 50 * scale, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Pilha temporária")
                        .font(.system(size: 11 * scale, weight: .semibold))
                    Text(stackSubtitle)
                        .font(.system(size: 9.5 * scale))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .overlay(
                // Arrastar a pilha leva todos os itens de uma vez.
                ItemInteraction(
                    onMouseDown: { _ in },
                    onClickUp: { _ in },
                    onDoubleClick: { openAll() },
                    dragURLs: { panel.stackURLs },
                    menu: { stackMenu() },
                    onHover: { _, _ in },
                    onDragStarted: { panel.isDraggingFromPanel = true },
                    onDragEnded: { panel.isDraggingFromPanel = false }
                )
            )

            Spacer()

            Button {
                panel.clearStack()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Limpar pilha")
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 6 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    targeted ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.12), value: targeted)
    }

    private var stackSubtitle: String {
        let count = panel.stackURLs.count
        let items = count == 1 ? "1 item" : "\(count) itens"
        return "\(items) — arraste daqui para onde quiser"
    }

    private func openAll() {
        panel.stackURLs.forEach { NSWorkspace.shared.open($0) }
    }

    private func stackMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(title: "Abrir todos") { openAll() })
        menu.addItem(ActionMenuItem(title: "Mostrar no Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(panel.stackURLs)
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Limpar pilha") {
            Task { @MainActor in panel.clearStack() }
        })
        return menu
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
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
                    Task { @MainActor in panel.addToStack(url) }
                }
            }
        }
        return accepted
    }
}
