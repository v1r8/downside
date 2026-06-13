import 'dart:io';

import 'package:path/path.dart' as p;

import 'ai.dart';
import 'stacks.dart';

/// Erro quando nenhuma IA (Ollama/Claude) está disponível.
class NoAIException implements Exception {}

/// Ações em massa sobre uma pilha (portado do Mac). Os arquivos gerados
/// vão para o cofre %APPDATA%\Downside\Pilhas e entram na pilha como
/// outputs (marcam hadBulkAction → carta holográfica).
class BulkRunner {
  static const _textExt = {'.txt', '.md', '.csv', '.json', '.xml', '.log'};

  static String get _vault {
    final appdata = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final dir = p.join(appdata, 'Downside', 'Pilhas');
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  /// Baixa os links (http/https) encontrados nos textos/.url da pilha.
  static Future<List<String>> downloadLinks(FileStack s) async {
    final urls = <String>{};
    final re = RegExp(r'https?://[^\s"<>)]+');
    for (final path in s.paths) {
      final ext = p.extension(path).toLowerCase();
      if (_textExt.contains(ext) || ext == '.url' || ext == '.webloc') {
        try {
          for (final m in re.allMatches(File(path).readAsStringSync())) {
            urls.add(m.group(0)!);
          }
        } catch (_) {}
      }
    }
    final out = <String>[];
    for (final url in urls.take(10)) {
      try {
        final c = HttpClient();
        final req = await c.getUrl(Uri.parse(url));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          final dest = _unique(_safeName(url));
          final sink = File(dest).openWrite();
          await resp.pipe(sink);
          out.add(dest);
        }
        c.close();
      } catch (_) {}
    }
    return out;
  }

  /// Resumo denso do conteúdo textual da pilha (IA).
  static Future<List<String>> summarize(FileStack s) async {
    final text = _gatherText(s);
    if (text.isEmpty) return [];
    final summary = await AIText.complete(
      'Resuma em português, em tópicos claros e curtos, o conteúdo dos '
      'documentos a seguir. Cite números, datas e nomes próprios. Termine '
      'com uma linha "Em uma frase: …".\n\n$text',
      maxTokens: 1400,
    );
    if (summary == null) throw NoAIException();
    return [_writeText('Resumo ${_stamp()}.md', summary)];
  }

  /// Palavras-chave do conteúdo (IA).
  static Future<List<String>> keywords(FileStack s) async {
    final text = _gatherText(s);
    if (text.isEmpty) return [];
    final result = await AIText.complete(
      'Liste de 8 a 12 palavras-chave em português (uma por linha, sem '
      'numeração) que caracterizem os documentos a seguir, seguidas de uma '
      'frase única de caracterização geral.\n\n$text',
      maxTokens: 500,
    );
    if (result == null) throw NoAIException();
    return [_writeText('Palavras-chave ${_stamp()}.md', result)];
  }

  static String _gatherText(FileStack s) {
    final parts = <String>[];
    var budget = 14000;
    for (final path in s.paths) {
      if (budget < 200) break;
      if (!_textExt.contains(p.extension(path).toLowerCase())) continue;
      try {
        var content = File(path).readAsStringSync();
        if (content.isEmpty) continue;
        if (content.length > budget) content = content.substring(0, budget);
        budget -= content.length;
        parts.add('— ${p.basename(path)}:\n$content');
      } catch (_) {}
    }
    return parts.join('\n\n');
  }

  static String _writeText(String name, String content) {
    final dest = _unique(name);
    File(dest).writeAsStringSync(content);
    return dest;
  }

  static String _stamp() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}.${two(d.minute)}';
  }

  static String _safeName(String url) {
    var name = Uri.parse(url).pathSegments.isNotEmpty
        ? Uri.parse(url).pathSegments.last
        : '';
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (name.isEmpty) name = 'Download ${_stamp()}';
    return name;
  }

  static String _unique(String name) {
    var candidate = p.join(_vault, name);
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var n = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(_vault, '$base $n$ext');
      n++;
    }
    return candidate;
  }
}
