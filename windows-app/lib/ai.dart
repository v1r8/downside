import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'prefs.dart';

/// LLM local (Ollama) — gratis, no aparelho. Portado do Mac.
class OllamaService {
  static const _base = 'http://127.0.0.1:11434';

  static Future<bool> isRunning() async {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await c.getUrl(Uri.parse('$_base/api/tags'));
      final resp = await req.close().timeout(const Duration(seconds: 2));
      c.close();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> generate(String prompt,
      {String model = 'llama3.2:3b', int numPredict = 80}) async {
    try {
      final c = HttpClient();
      final req = await c.postUrl(Uri.parse('$_base/api/generate'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'model': model,
        'prompt': prompt,
        'stream': false,
        'options': {'temperature': 0.3, 'num_predict': numPredict},
      })));
      final resp = await req.close().timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) {
        c.close();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      c.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['response'] as String?)?.trim();
    } catch (_) {
      return null;
    }
  }
}

/// API do Claude (opcional, com chave). Portado do Mac.
class ClaudeService {
  static Future<String?> complete(String prompt, String key,
      {String model = 'claude-haiku-4-5-20251001', int maxTokens = 80}) async {
    try {
      final c = HttpClient();
      final req =
          await c.postUrl(Uri.parse('https://api.anthropic.com/v1/messages'));
      req.headers.set('x-api-key', key);
      req.headers.set('anthropic-version', '2023-06-01');
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      })));
      final resp = await req.close().timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) {
        c.close();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      c.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final content = json['content'] as List?;
      final text = content != null && content.isNotEmpty
          ? (content.first as Map<String, dynamic>)['text'] as String?
          : null;
      return text?.trim();
    } catch (_) {
      return null;
    }
  }
}

/// Texto longo (resumos, palavras-chave): Ollama local -> Claude.
class AIText {
  static Future<String?> complete(String prompt, {int maxTokens = 800}) async {
    if (await OllamaService.isRunning()) {
      final r = await OllamaService.generate(prompt, numPredict: maxTokens);
      if (r != null && r.trim().isNotEmpty) return r.trim();
    }
    final key = Prefs.i.claudeKey.value.trim();
    if (key.isNotEmpty) {
      final r = await ClaudeService.complete(prompt, key,
          model: 'claude-sonnet-4-6', maxTokens: maxTokens);
      if (r != null && r.trim().isNotEmpty) return r.trim();
    }
    return null;
  }
}

/// Cadeia de nomeacao: Ollama (local) -> Claude -> nulo (mantem data).
class AINamer {
  static Future<String?> titleFor(List<String> paths) async {
    final names = paths.take(15).map((path) => p.basename(path)).join('\n');
    final prompt = 'Dê um título curto (3 a 6 palavras, em português, sem '
        'aspas nem pontuação final) que descreva o tema comum destes '
        'arquivos. Responda APENAS com o título:\n\n$names';

    if (await OllamaService.isRunning()) {
      final t = _clean(await OllamaService.generate(prompt));
      if (t != null) return t;
    }
    final key = Prefs.i.claudeKey.value.trim();
    if (key.isNotEmpty) {
      final t = _clean(await ClaudeService.complete(prompt, key));
      if (t != null) return t;
    }
    return null;
  }

  static String? _clean(String? raw) {
    if (raw == null) return null;
    final line = raw
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .trim()
        .replaceAll(RegExp(r'^["\x27.]+|["\x27.]+$'), '');
    if (line.isEmpty) return null;
    return line.length > 60 ? line.substring(0, 60) : line;
  }
}
