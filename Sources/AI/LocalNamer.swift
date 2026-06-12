import Foundation
import PDFKit
import Vision

#if compiler(>=6.2)
import FoundationModels
#endif

/// Prompt compartilhado de nomeação (Apple Intelligence, Ollama,
/// Claude). No detalhamento 2, lê textos, extrai texto de PDFs,
/// ANALISA imagens localmente (Vision) e resolve o TÍTULO real de
/// links (página/vídeo) para descrever o conteúdo de verdade.
enum TitlePrompt {
    static let textExtensions: Set<String> = ["txt", "md", "csv", "json", "xml", "log"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff"]

    static func build(for urls: [URL]) async -> String {
        let names = urls.prefix(15).map(\.lastPathComponent).joined(separator: "\n")
        let deep = Prefs.stackTitleDetail >= 2

        var excerpts = ""
        for url in urls.prefix(6) {
            if let line = await excerpt(for: url, deep: deep) {
                excerpts += "\n— \(line)"
            }
        }

        return """
        Dê um título curto (3 a 6 palavras, em português, sem aspas nem \
        pontuação final) que descreva o tema comum destes arquivos. \
        Baseie-se no CONTEÚDO analisado — não repita simplesmente os \
        nomes dos arquivos. Responda APENAS com o título:

        \(names)\(excerpts.isEmpty ? "" : "\n\nConteúdo analisado:\(excerpts)")
        """
    }

    /// Linha descritiva do conteúdo de um arquivo — usada na nomeação
    /// de pilhas e também na nomeação inteligente de documentos.
    static func excerpt(for url: URL, deep: Bool) async -> String? {
        let ext = url.pathExtension.lowercased()

        // Links: o conteúdo É a página. Com profundidade, busca o
        // título real (vídeo do YouTube, artigo etc.).
        if ext == "webloc", let link = LinkPeek.url(fromWebloc: url) {
            if deep, let title = await LinkPeek.pageTitle(for: link) {
                return "\(url.lastPathComponent) (link): \"\(title)\" — \(link.absoluteString.prefix(90))"
            }
            return "\(url.lastPathComponent) (link): \(link.absoluteString.prefix(120))"
        }

        guard deep else { return nil }

        if textExtensions.contains(ext),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return "\(url.lastPathComponent): \(condense(content, limit: 400))"
        }
        if ext == "pdf", let content = PDFDocument(url: url)?.string {
            return "\(url.lastPathComponent) (PDF): \(condense(content, limit: 700))"
        }
        if imageExtensions.contains(ext) {
            let labels = await imageLabels(url)
            if !labels.isEmpty {
                return "\(url.lastPathComponent) (imagem mostra): \(labels.joined(separator: ", "))"
            }
        }
        return nil
    }

    /// Colapsa espaços/quebras para caber mais conteúdo útil no prompt.
    private static func condense(_ text: String, limit: Int) -> String {
        let flat = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flat.prefix(limit))
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

/// Resolve o título real de um link salvo (.webloc): oEmbed no
/// YouTube (título do vídeo) e <title> da página no resto.
enum LinkPeek {
    static func url(fromWebloc url: URL) -> URL? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let raw = plist["URL"] as? String
        else { return nil }
        return URL(string: raw)
    }

    static func pageTitle(for link: URL) async -> String? {
        let host = link.host?.lowercased() ?? ""
        if host.contains("youtube.com") || host.contains("youtu.be"),
           let encoded = link.absoluteString.addingPercentEncoding(
               withAllowedCharacters: .alphanumerics
           ),
           let oembed = URL(string: "https://www.youtube.com/oembed?format=json&url=\(encoded)") {
            var request = URLRequest(url: oembed)
            request.timeoutInterval = 6
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let title = json["title"] as? String, !title.isEmpty {
                return String(title.prefix(120))
            }
        }

        var request = URLRequest(url: link)
        request.timeoutInterval = 6
        request.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        let html = String(decoding: data.prefix(160_000), as: UTF8.self)
        guard let range = html.range(
            of: "<title[^>]*>[^<]{1,300}</title>",
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let title = String(html[range])
            .replacingOccurrences(of: "<title[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</title>", with: "", options: .caseInsensitive)
        let clean = decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(120))
    }

    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

/// Nomeador local: usa o modelo on-device do Apple Intelligence
/// (macOS 26+) para responder prompts curtos de nomeação. Sem o
/// modelo disponível, o chamador cai para Ollama/Claude/data.
enum LocalNamer {
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Resposta curta de uma linha (título/nome), já limpa.
    static func complete(prompt: String) async -> String? {
        #if compiler(>=6.2)
        guard #available(macOS 26.0, *) else { return nil }
        guard SystemLanguageModel.default.availability == .available else { return nil }
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let title = response.content
                .components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.")) ?? ""
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
