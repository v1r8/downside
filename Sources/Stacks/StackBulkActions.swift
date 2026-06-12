import AppKit
import SwiftUI
import PDFKit

/// Executa ações em massa sobre uma pilha: gerar PDF, baixar links,
/// resumo e palavras-chave por IA, e arquivar no fichário. Os arquivos
/// gerados entram na pilha marcados como output, e pilhas com ação em
/// massa são fotografadas no fichário automaticamente.
@MainActor
final class BulkActionRunner: ObservableObject {
    @Published var runningLabel: String?
    @Published var message: String?

    private let textExtensions: Set<String> = ["txt", "md", "json", "xml", "log", "csv"]

    func run(
        _ label: String,
        stack: FileStack,
        panel: PanelController,
        action: @escaping (FileStack) async throws -> [URL]
    ) {
        guard runningLabel == nil else { return }
        runningLabel = label
        message = nil
        Task {
            do {
                let outputs = try await action(stack)
                for output in outputs {
                    panel.addOutput(output, to: stack.id)
                }
                // Fotografa a pilha (originais + outputs) no fichário.
                if let updated = panel.stacks.first(where: { $0.id == stack.id }) {
                    let title = await ClaudeService.stackTitle(for: updated.urls)
                    StackHistoryStore.shared.archive(updated, title: title)
                }
                message = outputs.isEmpty ? "Nada para processar" : "Concluído ✓"
            } catch {
                message = "Não foi possível concluir"
            }
            runningLabel = nil
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            message = nil
        }
    }

    /// Variante para fichas do fichário: os outputs são anexados à
    /// própria ficha arquivada.
    func runArchived(
        _ label: String,
        entry: ArchivedStack,
        action: @escaping (FileStack) async throws -> [URL]
    ) {
        guard runningLabel == nil else { return }
        runningLabel = label
        message = nil
        Task {
            do {
                let stack = FileStack(
                    urls: entry.urls,
                    outputs: Set(entry.outputs),
                    hadBulkAction: entry.hadBulkAction
                )
                let outputs = try await action(stack)
                StackHistoryStore.shared.appendOutputs(entry.id, urls: outputs)
                message = outputs.isEmpty ? "Nada para processar" : "Concluído ✓"
            } catch {
                message = "Não foi possível concluir"
            }
            runningLabel = nil
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            message = nil
        }
    }

    // MARK: - Ações

    /// Um PDF único com todas as cartas: PDFs são incorporados página a
    /// página; imagens viram páginas; textos são renderizados.
    func makePDF(from stack: FileStack) async throws -> [URL] {
        let document = PDFDocument()
        var index = 0

        for url in stack.urls {
            let ext = url.pathExtension.lowercased()
            if ext == "pdf", let part = PDFDocument(url: url) {
                for page in 0..<part.pageCount {
                    if let copied = part.page(at: page)?.copy() as? PDFPage {
                        document.insert(copied, at: index)
                        index += 1
                    }
                }
            } else if let image = NSImage(contentsOf: url), image.isValid {
                if let page = PDFPage(image: image) {
                    document.insert(page, at: index)
                    index += 1
                }
            } else if textExtensions.contains(ext),
                      let text = try? String(contentsOf: url, encoding: .utf8) {
                if let page = PDFPage(image: render(text: text, title: url.lastPathComponent)) {
                    document.insert(page, at: index)
                    index += 1
                }
            }
        }

        guard document.pageCount > 0 else { return [] }
        let destination = Prefs.supportDirectory("Pilhas")
            .appendingPathComponent("Pilha \(stamp()).pdf")
        guard document.write(to: destination) else { return [] }
        return [destination]
    }

    /// Baixa todos os links encontrados em textos/.webloc da pilha.
    func downloadLinks(from stack: FileStack) async throws -> [URL] {
        var links: [URL] = []
        for url in stack.urls {
            let ext = url.pathExtension.lowercased()
            if ext == "webloc",
               let plist = try? PropertyListSerialization.propertyList(
                   from: Data(contentsOf: url), format: nil
               ) as? [String: Any],
               let raw = plist["URL"] as? String,
               let link = URL(string: raw) {
                links.append(link)
            } else if textExtensions.contains(ext),
                      let text = try? String(contentsOf: url, encoding: .utf8) {
                let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                let matches = detector.matches(
                    in: text, range: NSRange(text.startIndex..., in: text)
                )
                links.append(contentsOf: matches.compactMap(\.url).filter { $0.scheme?.hasPrefix("http") == true })
            }
        }

        var results: [URL] = []
        for link in links.prefix(10) {
            guard let (temp, response) = try? await URLSession.shared.download(from: link) else { continue }
            var name = response.suggestedFilename ?? link.lastPathComponent
            if name.isEmpty || name == "/" { name = "Download \(stamp())" }
            let destination = Prefs.supportDirectory("Pilhas").appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.moveItem(at: temp, to: destination)
            results.append(destination)
        }
        return results
    }

    /// Resumo do conteúdo textual da pilha via Claude.
    func summarize(_ stack: FileStack) async throws -> [URL] {
        let text = gatherText(from: stack)
        guard !text.isEmpty else { return [] }
        let summary = try await ClaudeService.complete(
            prompt: """
            Resuma em português, em tópicos claros e curtos, o conteúdo \
            dos documentos a seguir. Termine com uma linha "Em uma frase: …".

            \(text)
            """
        )
        return [write(summary, name: "Resumo \(stamp())")]
    }

    /// Caracterização em palavras-chave via Claude.
    func keywords(_ stack: FileStack) async throws -> [URL] {
        let text = gatherText(from: stack)
        guard !text.isEmpty else { return [] }
        let result = try await ClaudeService.complete(
            prompt: """
            Caracterize os documentos a seguir em 8 a 12 palavras-chave \
            em português (uma por linha, sem numeração), seguidas de uma \
            frase única de caracterização geral.

            \(text)
            """,
            maxTokens: 400
        )
        return [write(result, name: "Palavras-chave \(stamp())")]
    }

    // MARK: - Helpers

    private func gatherText(from stack: FileStack) -> String {
        var parts: [String] = []
        var budget = 14_000
        for url in stack.urls where budget > 200 {
            let ext = url.pathExtension.lowercased()
            var content: String?
            if textExtensions.contains(ext) {
                content = try? String(contentsOf: url, encoding: .utf8)
            } else if ext == "pdf" {
                content = PDFDocument(url: url)?.string
            }
            guard var content, !content.isEmpty else { continue }
            if content.count > budget {
                content = String(content.prefix(budget))
            }
            budget -= content.count
            parts.append("— \(url.lastPathComponent):\n\(content)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func write(_ text: String, name: String) -> URL {
        let destination = Prefs.supportDirectory("Pilhas")
            .appendingPathComponent("\(name).md")
        try? text.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    private func render(text: String, title: String) -> NSImage {
        let size = NSSize(width: 612, height: 792)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let content = "\(title)\n\n\(text.prefix(3500))"
        (content as NSString).draw(
            in: NSRect(x: 36, y: 36, width: 540, height: 720),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.black,
            ]
        )
        image.unlockFocus()
        return image
    }

    private func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter.string(from: Date())
    }
}
