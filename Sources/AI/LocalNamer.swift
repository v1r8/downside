import Foundation

#if compiler(>=6.2)
import FoundationModels
#endif

/// Nomeador local de pilhas: usa o modelo on-device do Apple
/// Intelligence (macOS 26+) para ler nomes — e, conforme o nível de
/// detalhamento configurado, trechos do conteúdo — e propor um título.
/// Sem o modelo disponível, o chamador cai para a API do Claude/data.
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
            let response = try await session.respond(to: prompt(for: urls))
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

    private static func prompt(for urls: [URL]) -> String {
        let names = urls.prefix(15).map(\.lastPathComponent).joined(separator: "\n")

        var excerpts = ""
        if Prefs.stackTitleDetail >= 2 {
            let textExtensions: Set<String> = ["txt", "md", "csv", "json", "xml", "log"]
            for url in urls.prefix(3)
            where textExtensions.contains(url.pathExtension.lowercased()) {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    excerpts += "\n— \(url.lastPathComponent): \(String(content.prefix(280)))"
                }
            }
        }

        return """
        Dê um título curto (3 a 6 palavras, em português, sem aspas nem \
        pontuação final) que descreva o tema comum destes arquivos:

        \(names)\(excerpts.isEmpty ? "" : "\n\nTrechos do conteúdo:\(excerpts)")
        """
    }
}
