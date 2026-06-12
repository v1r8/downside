import SwiftUI
import AppKit
import Combine

/// Item configurável da barra de ações em massa (texto, ícone, ordem e
/// ativação editáveis nas configurações).
struct BulkActionItem: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var icon: String
    var enabled: Bool
}

@MainActor
final class BulkActionConfigStore: ObservableObject {
    static let shared = BulkActionConfigStore()

    static let defaultItems: [BulkActionItem] = [
        BulkActionItem(id: "abrir", title: "Abrir todos", icon: "arrow.up.forward.app", enabled: true),
        BulkActionItem(id: "pdf", title: "Gerar PDF", icon: "doc.richtext", enabled: true),
        BulkActionItem(id: "links", title: "Baixar links", icon: "link", enabled: true),
        BulkActionItem(id: "resumo", title: "Resumir com IA", icon: "text.alignleft", enabled: true),
        BulkActionItem(id: "chaves", title: "Palavras-chave", icon: "tag", enabled: true),
        BulkActionItem(id: "arquivar", title: "Arquivar", icon: "book", enabled: true),
    ]

    static let iconChoices = [
        "doc.richtext", "link", "text.alignleft", "tag", "book",
        "sparkles", "wand.and.stars", "square.stack.3d.up", "tray.full",
        "doc.zipper", "arrow.down.circle", "list.bullet.rectangle",
    ]

    @Published var items: [BulkActionItem] {
        didSet { save() }
    }

    private init() {
        var loaded = Self.defaultItems
        if let data = UserDefaults.standard.data(forKey: "bulkActions"),
           let decoded = try? JSONDecoder().decode([BulkActionItem].self, from: data),
           !decoded.isEmpty {
            loaded = decoded
            // Migração: garante que ações novas do app apareçam.
            for item in Self.defaultItems where !loaded.contains(where: { $0.id == item.id }) {
                loaded.insert(item, at: 0)
            }
        }
        items = loaded
    }

    func move(_ id: String, up: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? index - 1 : index + 1
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }

    func reset() {
        items = Self.defaultItems
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: "bulkActions")
    }
}

/// ScrollView horizontal que também responde à rolagem VERTICAL do
/// mouse/trackpad, sempre com movimento horizontal animado.
struct HorizontalWheelScroller<Content: View>: NSViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> HWheelScrollView {
        let scroll = HWheelScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        let host = NSHostingView(rootView: content)
        host.frame.size = host.fittingSize
        scroll.documentView = host
        return scroll
    }

    func updateNSView(_ scroll: HWheelScrollView, context: Context) {
        if let host = scroll.documentView as? NSHostingView<Content> {
            host.rootView = content
            host.frame.size = host.fittingSize
        }
    }
}

final class HWheelScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let deltaY = event.scrollingDeltaY
        guard abs(deltaY) > abs(event.scrollingDeltaX), let document = documentView else {
            super.scrollWheel(with: event)
            return
        }
        var origin = contentView.bounds.origin
        let maxX = max(0, document.frame.width - contentView.bounds.width)
        origin.x = max(0, min(maxX, origin.x - deltaY * 3))
        if event.hasPreciseScrollingDeltas {
            // Trackpad: resposta imediata (os deltas já são contínuos).
            contentView.setBoundsOrigin(origin)
        } else {
            // Roda "de cliques": suaviza com uma animação curta.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                contentView.animator().setBoundsOrigin(origin)
            }
        }
        reflectScrolledClipView(contentView)
    }
}
