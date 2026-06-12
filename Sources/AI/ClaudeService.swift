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

    /// Título curto e informativo para uma pilha. O prompt (com
    /// conteúdo analisado) é montado UMA vez e tentado em ordem:
    /// Apple Intelligence (macOS 26) → Ollama local → Claude → data.
    static func stackTitle(for urls: [URL]) async -> String {
        let prompt = await TitlePrompt.build(for: urls)
        if let local = await LocalNamer.complete(prompt: prompt) {
            return local
        }
        if let ollama = await OllamaService.completeShort(prompt: prompt) {
            return ollama
        }
        let fallback = "Pilha de \(Date().formatted(date: .abbreviated, time: .shortened))"
        guard hasKey else { return fallback }
        let title = (try? await complete(
            prompt: prompt,
            model: "claude-haiku-4-5-20251001",
            maxTokens: 100
        )) ?? fallback
        return title.isEmpty ? fallback : title
    }
}

/// Cadeia de IA para tarefas LONGAS (resumos, palavras-chave):
/// respeita o motor escolhido nas configurações — automático (local
/// primeiro, Claude de reserva), sempre Claude ou só local.
enum AIChain {
    enum ChainError: Error {
        case unavailable
    }

    static func complete(prompt: String, maxTokens: Int = 1500) async throws -> String {
        let engine = Prefs.bulkAIEngine
        if engine != 2 {
            if let local = await LocalNamer.completeLong(prompt: prompt) {
                return local
            }
            if let ollama = await OllamaService.completeLong(
                prompt: prompt, numPredict: maxTokens
            ) {
                return ollama
            }
        }
        if engine != 3, ClaudeService.hasKey {
            return try await ClaudeService.complete(prompt: prompt, maxTokens: maxTokens)
        }
        throw ChainError.unavailable
    }
}
