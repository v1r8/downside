import Foundation
import Combine

/// Uma pilha arquivada no fichário.
struct ArchivedStack: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var date: Date
    var paths: [String]
    var outputPaths: [String]
    var hadBulkAction: Bool
    /// Opcional para decodificar fichários antigos sem o campo.
    var favorite: Bool? = nil

    var isFavorite: Bool { favorite ?? false }

    var urls: [URL] { paths.map { URL(fileURLWithPath: $0) } }
    var outputs: [URL] { outputPaths.map { URL(fileURLWithPath: $0) } }
}

/// Fichário: histórico persistente de pilhas (JSON em Application
/// Support), com títulos gerados por IA quando há chave configurada.
@MainActor
final class StackHistoryStore: ObservableObject {
    static let shared = StackHistoryStore()

    @Published private(set) var archived: [ArchivedStack] = []

    /// Fichas cujo título ainda está sendo gerado pela IA — a UI mostra
    /// o efeito mágico no lugar do nome, mas a ficha já é utilizável.
    @Published private(set) var namingIDs: Set<UUID> = []

    private var storeURL: URL {
        Prefs.supportDirectory("Fichario").appendingPathComponent("historico.json")
    }

    private init() {
        load()
    }

    /// Arquiva IMEDIATAMENTE (ficha utilizável na hora) e nomeia em
    /// segundo plano.
    func archiveAndName(_ stack: FileStack) {
        let entry = ArchivedStack(
            id: UUID(),
            title: "",
            date: Date(),
            paths: stack.urls.map(\.path),
            outputPaths: stack.outputs.map(\.path),
            hadBulkAction: stack.hadBulkAction
        )
        archived.insert(entry, at: 0)
        save()
        nameEntry(entry.id, urls: stack.urls)
    }

    /// Regera o título de uma ficha existente (com o efeito mágico).
    func regenerateTitle(_ entry: ArchivedStack) {
        nameEntry(entry.id, urls: entry.urls)
    }

    private func nameEntry(_ id: UUID, urls: [URL]) {
        namingIDs.insert(id)
        Task { [weak self] in
            let title = await ClaudeService.stackTitle(for: urls)
            self?.rename(id, to: title)
            self?.namingIDs.remove(id)
        }
    }

    func archive(_ stack: FileStack, title: String) {
        let entry = ArchivedStack(
            id: UUID(),
            title: title,
            date: Date(),
            paths: stack.urls.map(\.path),
            outputPaths: stack.outputs.map(\.path),
            hadBulkAction: stack.hadBulkAction
        )
        archived.insert(entry, at: 0)
        save()
    }

    func delete(_ id: UUID) {
        archived.removeAll { $0.id == id }
        save()
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = archived.firstIndex(where: { $0.id == id }) else { return }
        archived[index].title = title
        save()
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = archived.firstIndex(where: { $0.id == id }) else { return }
        archived[index].favorite = !archived[index].isFavorite
        save()
    }

    /// Remove um output de uma ficha (o arquivo é tratado pelo chamador).
    func removeOutput(_ id: UUID, url: URL) {
        guard let index = archived.firstIndex(where: { $0.id == id }) else { return }
        archived[index].paths.removeAll { $0 == url.path }
        archived[index].outputPaths.removeAll { $0 == url.path }
        // Sem outputs restantes, o indicador de ação em massa some.
        if archived[index].outputPaths.isEmpty {
            archived[index].hadBulkAction = false
        }
        save()
    }

    /// Anexa outputs de uma ação em massa a uma ficha arquivada.
    func appendOutputs(_ id: UUID, urls: [URL]) {
        guard !urls.isEmpty,
              let index = archived.firstIndex(where: { $0.id == id }) else { return }
        for url in urls {
            if !archived[index].paths.contains(url.path) {
                archived[index].paths.append(url.path)
            }
            if !archived[index].outputPaths.contains(url.path) {
                archived[index].outputPaths.append(url.path)
            }
        }
        archived[index].hadBulkAction = true
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([ArchivedStack].self, from: data)
        else { return }
        archived = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(archived) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
