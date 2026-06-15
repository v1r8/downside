import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_text.dart';
import 'prefs.dart';
// File e p já vêm de dart:io e package:path acima.

/// LLM local (Ollama) — gratis, no aparelho. Portado do Mac.
class OllamaService {
  static const _base = 'http://127.0.0.1:11434';

  /// Modelo escolhido nas preferencias (fallback para llama3.2:3b).
  static String get model {
    final m = Prefs.i.ollamaModel.value.trim();
    return m.isEmpty ? 'llama3.2:3b' : m;
  }

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

  /// Modelos ja baixados (nomes como 'llama3.2:3b'). Vazio se offline.
  static Future<List<String>> listModels() async {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await c.getUrl(Uri.parse('$_base/api/tags'));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      final body = await resp.transform(utf8.decoder).join();
      c.close();
      if (resp.statusCode != 200) return [];
      final json = jsonDecode(body) as Map<String, dynamic>;
      final models = (json['models'] as List?) ?? [];
      return models
          .map((m) => (m as Map<String, dynamic>)['name'] as String?)
          .whereType<String>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Baixa um modelo via /api/pull (NDJSON em stream). [onProgress] recebe
  /// um status textual e a fracao 0..1. Retorna true ao concluir.
  static Future<bool> pullModel(String name,
      {void Function(String status, double progress)? onProgress}) async {
    try {
      final c = HttpClient();
      final req = await c.postUrl(Uri.parse('$_base/api/pull'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({'model': name, 'stream': true})));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        c.close();
        return false;
      }
      var ok = false;
      await for (final line in resp
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          final status = (j['status'] as String?) ?? '';
          final total = (j['total'] as num?)?.toDouble();
          final completed = (j['completed'] as num?)?.toDouble();
          final prog = (total != null && total > 0 && completed != null)
              ? (completed / total).clamp(0.0, 1.0)
              : 0.0;
          onProgress?.call(status, prog);
          if (status.toLowerCase() == 'success') ok = true;
        } catch (_) {}
      }
      c.close();
      return ok;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> generate(String prompt,
      {String? model, int numPredict = 80}) async {
    model ??= OllamaService.model;
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

/// Texto longo (resumos, palavras-chave). Respeita o motor escolhido:
/// 1=automático (local→Claude), 2=só Claude, 3=só local (Ollama).
class AIText {
  static Future<String?> complete(String prompt, {int maxTokens = 800}) async {
    final engine = Prefs.i.bulkAIEngine.value;
    if (engine != 2 && await OllamaService.isRunning()) {
      final r = await OllamaService.generate(prompt, numPredict: maxTokens);
      if (r != null && r.trim().isNotEmpty) return r.trim();
    }
    if (engine != 3) {
      final key = Prefs.i.claudeKey.value.trim();
      if (key.isNotEmpty) {
        final r = await ClaudeService.complete(prompt, key,
            model: 'claude-sonnet-4-6', maxTokens: maxTokens);
        if (r != null && r.trim().isNotEmpty) return r.trim();
      }
    }
    return null;
  }
}

/// Cadeia de nomeacao: Ollama (local) -> Claude -> nulo (mantem data).
class AINamer {
  static Future<String?> titleFor(List<String> paths) async {
    final ctx = StringBuffer();
    for (final path in paths.take(8)) {
      ctx.writeln('- ${p.basename(path)}');
      final snip = await FileText.snippet(path, max: 350);
      if (snip.isNotEmpty) ctx.writeln('  conteúdo: $snip');
    }
    final prompt =
        'Estes arquivos foram reunidos numa mesma pilha de trabalho. '
        'Analise os NOMES e os TRECHOS de conteúdo e dê um título curto '
        '(3 a 6 palavras, em português, sem aspas nem pontuação final) que '
        'capture o tema/projeto/assunto comum — específico, não genérico. '
        'Responda APENAS com o título:\n\n$ctx';

    if (await OllamaService.isRunning()) {
      final t = _clean(await OllamaService.generate(prompt, numPredict: 40));
      if (t != null) return t;
    }
    final key = Prefs.i.claudeKey.value.trim();
    if (key.isNotEmpty) {
      final t = _clean(await ClaudeService.complete(prompt, key, maxTokens: 40));
      if (t != null) return t;
    }
    return null;
  }

  /// Apelido/nome para um ARQUIVO. Lê o conteúdo real (textos, Office e
  /// PDF aproximado) para propor um nome específico e descritivo.
  static Future<String?> nameForFile(String path) async {
    final base = p.basename(path);
    final folder = p.basename(p.dirname(path));
    final ext = p.extension(path);
    final content = await FileText.snippet(path, max: 2500);

    final ctx = StringBuffer()
      ..writeln('Nome atual: $base')
      ..writeln('Pasta: $folder')
      ..writeln(
          'Tipo: ${ext.isEmpty ? "desconhecido" : ext.substring(1).toUpperCase()}');
    if (content.isNotEmpty) {
      ctx
        ..writeln('Trecho do conteúdo:')
        ..writeln(content);
    }

    final prompt = content.isEmpty
        ? 'Não foi possível ler o conteúdo. Pelo nome e tipo, sugira um nome '
            'de arquivo curto e claro (3 a 6 palavras, em português, sem '
            'extensão, sem aspas nem barras). Responda APENAS com o nome:\n\n$ctx'
        : 'Você renomeia documentos. Leia o conteúdo abaixo e proponha um '
            'nome de arquivo curto, específico e descritivo em português '
            '(4 a 8 palavras), capturando o ASSUNTO real: tema, '
            'pessoas/empresas, datas e tipo de documento (contrato, nota, '
            'relatório, proposta…). Se houver número de documento/contrato/'
            'nota, inclua. Sem extensão, sem aspas, sem barras, sem pontuação '
            'final. Responda APENAS com o nome:\n\n$ctx';

    if (await OllamaService.isRunning()) {
      final r = _clean(await OllamaService.generate(prompt, numPredict: 40));
      if (r != null) return r;
    }
    final key = Prefs.i.claudeKey.value.trim();
    if (key.isNotEmpty) {
      final r = _clean(await ClaudeService.complete(prompt, key, maxTokens: 40));
      if (r != null) return r;
    }
    return null;
  }

  static String? _clean(String? raw) {
    if (raw == null) return null;
    var line = raw
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        // remove caracteres de controle (lixo de modelos quebrados)
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim()
        .replaceAll(RegExp(r'^["\x27.\s]+|["\x27.\s]+$'), '');
    if (line.isEmpty) return null;
    // Rejeita saídas sem conteúdo real (ex.: "@@@@@", "----", "####"),
    // que apareciam como lixo no nome — melhor manter o nome original.
    final letters = RegExp(r'[A-Za-zÀ-ÿ0-9]').allMatches(line).length;
    if (letters < 2 || letters < line.length * 0.4) return null;
    return line.length > 60 ? line.substring(0, 60) : line;
  }
}
