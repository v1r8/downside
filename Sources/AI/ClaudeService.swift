import Foundation

/// Cliente mínimo da API do Claude (Messages). Os recursos de IA são
/// opcionais e exigem a chave configurada em Configurações → IA.
enum ClaudeService {
    enum ServiceError: Error {
        case missingKey
        case badResponse
    }

    static var hasKey: Bool { Prefs.claudeAPIKey != nil }

    static func complete(
        prompt: String,
        model: String = "claude-sonnet-4-6",
        maxTokens: Int = 1500
    ) async throws -> String {
        guard let key = Prefs.claudeAPIKey else { throw ServiceError.missingKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 90

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ServiceError.badResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else {
            throw ServiceError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Título curto e informativo para uma pilha, a partir dos nomes
    /// dos arquivos (modelo rápido). Sem chave, usa a data.
    static func stackTitle(for urls: [URL]) async -> String {
        let fallback = "Pilha de \(Date().formatted(date: .abbreviated, time: .shortened))"
        guard hasKey else { return fallback }
        let names = urls.prefix(20).map(\.lastPathComponent).joined(separator: "\n")
        let prompt = """
        Dê um título curto (3 a 6 palavras, em português, sem aspas nem \
        pontuação final) que descreva o tema comum destes arquivos:

        \(names)
        """
        let title = (try? await complete(
            prompt: prompt,
            model: "claude-haiku-4-5-20251001",
            maxTokens: 60
        )) ?? fallback
        return title.isEmpty ? fallback : title
    }
}
