import AppKit
import PDFKit
import Vision

/// Índice local de CONTEÚDO para a busca: texto de txt/md/csv, texto
/// extraído de PDFs, OCR de imagens (Vision) e o dossiê de links
/// (título/descrição da página). Tudo 100% no aparelho, indexado em
/// segundo plano quando uma busca acontece, com cache por data de
/// modificação — os resultados vão aparecendo conforme indexa.
@MainActor
final class ContentIndex: ObservableObject {
    static let shared = ContentIndex()

    struct Entry: Codable {
        var text: String
        var modified: TimeInterval
    }

    /// Bump a cada lote indexado — a busca refaz o filtro ao vivo.
    @Published private(set) var revision = 0

    private var entries: [String: Entry] = [:]
    private var queue: [URL] = []
    private var queued: Set<String> = []
    private var working = false

    private static let textExtensions: Set<String> = ["txt", "md", "csv", "json", "xml", "log"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "webp", "gif"]

    static let indexableExtensions: Set<String> =
        textExtensions.union(imageExtensions).union(["pdf", "webloc"])

    private var storeURL: URL {
        Prefs.supportDirectory("Index").appendingPathComponent("conteudo.json")
    }

    private init() { load() }

    /// Texto indexado e ainda fresco (arquivo não mudou desde então).
    func text(for url: URL) -> String? {
        guard let entry = entries[url.path] else { return nil }
        guard abs(entry.modified - modificationTime(url)) < 2 else { return nil }
        return entry.text
    }

    /// Todos os termos aparecem no conteúdo indexado?
    func contains(_ url: URL, terms: [String]) -> Bool {
        guard !terms.isEmpty, let text = text(for: url), !text.isEmpty else { return false }
        return terms.allSatisfy { text.contains($0) }
    }

    /// Coloca na fila o que ainda não foi indexado (ou ficou velho).
    func ensureIndexed(_ urls: [URL]) {
        for url in urls.prefix(800) {
            guard Self.indexableExtensions.contains(url.pathExtension.lowercased()),
                  text(for: url) == nil,
                  !queued.contains(url.path)
            else { continue }
            queued.insert(url.path)
            queue.append(url)
        }
        kick()
    }

    private func kick() {
        guard !working, !queue.isEmpty else { return }
        working = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            var processed = 0
            while !self.queue.isEmpty {
                let url = self.queue.removeFirst()
                self.queued.remove(url.path)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let raw = await Self.extract(url) ?? ""
                self.entries[url.path] = Entry(
                    text: Self.normalize(raw),
                    modified: self.modificationTime(url)
                )
                processed += 1
                if processed.isMultiple(of: 4) {
                    self.revision += 1
                }
            }
            self.revision += 1
            self.save()
            self.working = false
            self.kick()
        }
    }

    private nonisolated static func extract(_ url: URL) async -> String? {
        let ext = url.pathExtension.lowercased()
        if textExtensions.contains(ext) {
            return (try? String(contentsOf: url, encoding: .utf8))
                .map { String($0.prefix(12_000)) }
        }
        if ext == "pdf" {
            return await Task.detached(priority: .utility) {
                PDFDocument(url: url)?.string.map { String($0.prefix(12_000)) }
            }.value
        }
        if imageExtensions.contains(ext) {
            // OCR local (Vision) — o texto da imagem vira buscável.
            return await Task.detached(priority: .utility) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["pt-BR", "en-US"]
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(url: url)
                try? handler.perform([request])
                let lines = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                return lines.isEmpty ? nil : String(lines.joined(separator: " ").prefix(8_000))
            }.value
        }
        if ext == "webloc" {
            guard let link = LinkPeek.url(fromWebloc: url) else { return nil }
            var parts = [link.absoluteString]
            if let summary = await LinkPeek.pageSummary(for: link) {
                parts.append(summary)
            }
            return parts.joined(separator: " ")
        }
        return nil
    }

    private func modificationTime(_ url: URL) -> TimeInterval {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        return date?.timeIntervalSince1970 ?? 0
    }

    private nonisolated static func normalize(_ text: String) -> String {
        text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "pt_BR")
        )
    }

    // MARK: - Persistência

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return }
        entries = stored
    }

    private func save() {
        // Poda entradas de arquivos que não existem mais.
        if entries.count > 2_000 {
            entries = entries.filter { FileManager.default.fileExists(atPath: $0.key) }
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
