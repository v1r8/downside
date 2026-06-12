import Foundation
import PDFKit
import Vision

#if compiler(>=6.2)
import FoundationModels
#endif

/// Prompt compartilhado de nomeação (Apple Intelligence, Ollama,
/// Claude). No detalhamento 2, lê textos, extrai texto de PDFs e
/// ANALISA imagens localmente (Vision) para descrever o conteúdo.
enum TitlePrompt {
    static func build(for urls: [URL]) async -> String {
        let names = urls.prefix(15).map(\.lastPathComponent).joined(separator: "\n")

        var excerpts = ""
        if Prefs.stackTitleDetail >= 2 {
            let textExtensions: Set<String> = ["txt", "md", "csv", "json", "xml", "log"]
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff"]

            for url in urls.prefix(5) {
                let ext = url.pathExtension.lowercased()
                if textExtensions.contains(ext),
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    excerpts += "\n— \(url.lastPathComponent): \(String(content.prefix(280)))"
                } else if ext == "pdf",
                          let content = PDFDocument(url: url)?.string {
                    excerpts += "\n— \(url.lastPathComponent) (PDF): \(String(content.prefix(280)))"
                } else if imageExtensions.contains(ext) {
                    let labels = await imageLabels(url)
                    if !labels.isEmpty {
                        excerpts += "\n— \(url.lastPathComponent) (imagem mostra): \(labels.joined(separator: ", "))"
                    }
                }
            }
        }

        return """
        Dê um título curto (3 a 6 palavras, em português, sem aspas nem \
        pontuação final) que descreva o tema comum destes arquivos. \
        Responda APENAS com o título:

        \(names)\(excerpts.isEmpty ? "" : "\n\nConteúdo analisado:\(excerpts)")
        """
    }

    /// Classificação local da imagem (Vision) — rótulos do que ela mostra.
    private static func imageLabels(_ url: URL) async -> [String] {
        await Task.detached(priority: .utility) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(url: url)
            try? handler.perform([request])
            return (request.results ?? [])
                .filter { $0.confidence > 0.3 }
                .prefix(4)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }.value
    }
}

/// Nomeador local de pilhas: usa o modelo on-device do Apple
/// Intelligence (macOS 26+) para ler nomes — e, conforme o nível de
/// detalhamento configurado, trechos do conteúdo — e propor um título.
/// Sem o modelo disponível, o chamador cai para Ollama/Claude/data.
enum LocalNamer {
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    static func title(for urls: [URL]) async -> String? {
        #if compiler(>=6.2)
        guard #available(macOS 26.0, *) else { return nil }
        guard SystemLanguageModel.default.availability == .available else { return nil }
        do {
            let session = LanguageModelSession()
            let prompt = await TitlePrompt.build(for: urls)
            let response = try await session.respond(to: prompt)
            let title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'."))
            guard !title.isEmpty else { return nil }
            return String(title.prefix(60))
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
