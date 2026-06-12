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
        Escreva um título ESPECÍFICO e informativo (5 a 10 palavras, em \
        português, sem aspas nem pontuação final) que identifique estes \
        arquivos como uma pessoa resumiria numa frase curta. CITE os \
        nomes próprios que aparecem no conteúdo — empresa, programa, \
        pessoas, projeto, produto (ex.: "Podcast Outliers com a Genoa \
        Capital", "Demonstrações financeiras da Vale 2T26"). NUNCA use \
        genéricos como "relatório financeiro", "link da internet" ou \
        "documentos diversos". Responda APENAS com o título:

        \(names)\(excerpts.isEmpty ? "" : "\n\nConteúdo analisado:\(excerpts)")
        """
    }

    /// Linha descritiva do conteúdo de um arquivo — usada na nomeação
    /// de pilhas e também na nomeação inteligente de documentos.
    static func excerpt(for url: URL, deep: Bool) async -> String? {
        let ext = url.pathExtension.lowercased()

        // Links: o conteúdo É a página. Com profundidade, busca o
        // título real + canal/autor + descrição (vídeo, artigo etc.).
        if ext == "webloc", let link = LinkPeek.url(fromWebloc: url) {
            if deep, let summary = await LinkPeek.pageSummary(for: link) {
                return "\(url.lastPathComponent) (link): \(summary) — \(link.absoluteString.prefix(90))"
            }
            return "\(url.lastPathComponent) (link): \(link.absoluteString.prefix(120))"
        }

        guard deep else { return nil }

        if textExtensions.contains(ext),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return "\(url.lastPathComponent): \(condense(content, limit: 1000))"
        }
        if ext == "pdf", let content = PDFDocument(url: url)?.string {
            return "\(url.lastPathComponent) (PDF): \(condense(content, limit: 1600))"
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

    /// Dossiê da página para a IA nomear com especificidade.
    /// YouTube: título + canal (oEmbed) + DESCRIÇÃO do vídeo (extraída
    /// do HTML da página). Outras páginas: título + descrição (og:/
    /// meta) + site + um trecho do texto visível.
    static func pageSummary(for link: URL) async -> String? {
        let host = link.host?.lowercased() ?? ""
        if host.contains("youtube.com") || host.contains("youtu.be") {
            var parts: [String] = []
            if let encoded = link.absoluteString.addingPercentEncoding(
                   withAllowedCharacters: .alphanumerics
               ),
               let oembed = URL(string: "https://www.youtube.com/oembed?format=json&url=\(encoded)") {
                var request = URLRequest(url: oembed)
                request.timeoutInterval = 6
                if let (data, _) = try? await URLSession.shared.data(for: request),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let title = json["title"] as? String, !title.isEmpty {
                    let author = (json["author_name"] as? String) ?? ""
                    let suffix = author.isEmpty ? "" : " (vídeo do canal \(author))"
                    parts.append("\"\(String(title.prefix(140)))\"\(suffix)")
                }
            }
            if let html = await fetchHTML(link),
               let description = firstMatch(
                   in: html,
                   pattern: "\"shortDescription\":\"((?:\\\\.|[^\"\\\\]){1,1200})\""
               ) {
                parts.append("descrição do vídeo: \(unescapeJSON(description).prefix(600))")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " — ")
        }

        guard let html = await fetchHTML(link) else { return nil }

        var parts: [String] = []
        if let title = firstMatch(in: html, pattern: "<title[^>]*>([^<]{1,300})</title>") {
            parts.append("\"\(String(title.prefix(140)))\"")
        }
        if let site = firstMatch(
            in: html,
            pattern: "<meta[^>]+property=[\"']og:site_name[\"'][^>]+content=[\"']([^\"']{1,120})[\"']"
        ) {
            parts.append("site: \(site)")
        }
        let description = firstMatch(
            in: html,
            pattern: "<meta[^>]+(?:property=[\"']og:description[\"']|name=[\"']description[\"'])[^>]+content=[\"']([^\"']{1,400})[\"']"
        ) ?? firstMatch(
            in: html,
            pattern: "<meta[^>]+content=[\"']([^\"']{1,400})[\"'][^>]+(?:property=[\"']og:description[\"']|name=[\"']description[\"'])"
        )
        if let description {
            parts.append(String(description.prefix(260)))
        }
        // Sem descrição? Um trecho do texto visível da página ajuda.
        if description == nil, let body = visibleText(from: html) {
            parts.append("trecho da página: \(body.prefix(400))")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " — ")
    }

    private static func fetchHTML(_ link: URL) async -> String? {
        var request = URLRequest(url: link)
        request.timeoutInterval = 7
        request.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
        request.setValue("pt-BR,pt;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        return String(decoding: data.prefix(600_000), as: UTF8.self)
    }

    /// Texto visível da página: remove scripts/styles/tags e colapsa
    /// espaços — o suficiente para a IA entender do que se trata.
    private static func visibleText(from html: String) -> String? {
        var text = html
        for block in ["script", "style", "noscript", "svg", "head"] {
            text = text.replacingOccurrences(
                of: "<\(block)[\\s\\S]*?</\(block)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decodeEntities(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 40 ? text : nil
    }

    /// Desfaz escapes de string JSON (\n, \", &…).
    private static func unescapeJSON(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\\\", with: "\\")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Primeiro grupo de captura do padrão, com entidades decodificadas.
    private static func firstMatch(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: html)
        else { return nil }
        let clean = decodeEntities(String(html[captured]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
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
            return String(title.prefix(90))
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Resposta longa (resumos etc.), sem truncar na primeira linha.
    static func completeLong(prompt: String) async -> String? {
        #if compiler(>=6.2)
        guard #available(macOS 26.0, *) else { return nil }
        guard SystemLanguageModel.default.availability == .available else { return nil }
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
