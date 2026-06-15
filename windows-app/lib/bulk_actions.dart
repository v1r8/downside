import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'ai.dart';
import 'file_text.dart';
import 'prefs.dart';
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

  /// Combina os arquivos da pilha num ÚNICO PDF (imagens viram páginas;
  /// textos, Office e PDFs entram pelo conteúdo extraído). Sem IA.
  static Future<List<String>> makePdf(FileStack s) async {
    const imgExt = {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp'};
    final doc = pw.Document();
    var pages = 0;
    for (final path in s.paths) {
      final ext = p.extension(path).toLowerCase();
      try {
        if (imgExt.contains(ext)) {
          final bytes = await File(path).readAsBytes();
          final img = pw.MemoryImage(bytes);
          doc.addPage(pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (_) => pw.Center(child: pw.Image(img)),
          ));
          pages++;
        } else {
          final text = await FileText.snippet(path, max: 3500);
          if (text.trim().isEmpty) continue;
          doc.addPage(pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            build: (_) => [
              pw.Header(level: 0, child: pw.Text(p.basename(path))),
              pw.Paragraph(text: text),
            ],
          ));
          pages++;
        }
      } catch (_) {}
    }
    if (pages == 0) return [];
    final dest = _unique('Pilha ${_stamp()}.pdf');
    await File(dest).writeAsBytes(await doc.save());
    return [dest];
  }

  /// Resumo do conteúdo da pilha (IA). Profundidade configurável (curto/denso).
  static Future<List<String>> summarize(FileStack s) async {
    final text = await _gatherText(s);
    if (text.isEmpty) return [];
    final dense = Prefs.i.summaryDepth.value >= 2;
    final prompt = dense
        ? 'Produza um RESUMO DENSO em português, em markdown, dos documentos '
            'a seguir:\n'
            '1. Comece com "# Resumo" e uma visão geral de 2 a 3 frases.\n'
            '2. Liste os pontos principais em bullet points densos, citando '
            'os dados, números, datas, nomes e decisões que aparecem no '
            'texto.\n'
            '3. Inclua uma seção "## Nomes e entidades" com as pessoas, '
            'empresas, produtos e programas citados.\n'
            '4. Termine com uma linha "Em uma frase: …".\n\n$text'
        : 'Resuma em português, em tópicos claros e curtos, o conteúdo dos '
            'documentos a seguir. Termine com uma linha "Em uma frase: …".'
            '\n\n$text';
    final summary = await AIText.complete(prompt, maxTokens: 1800);
    if (summary == null) throw NoAIException();
    return [_writeText('Resumo ${_stamp()}.md', summary)];
  }

  /// Palavras-chave do conteúdo (IA). Quantidade configurável (5–20).
  static Future<List<String>> keywords(FileStack s) async {
    final text = await _gatherText(s);
    if (text.isEmpty) return [];
    final count = Prefs.i.keywordCount.value;
    final result = await AIText.complete(
      'Caracterize os documentos a seguir em $count a ${count + 2} '
      'palavras-chave em português (uma por linha, sem numeração), seguidas '
      'de uma frase única de caracterização geral.\n\n$text',
      maxTokens: 500,
    );
    if (result == null) throw NoAIException();
    return [_writeText('Palavras-chave ${_stamp()}.md', result)];
  }

  /// Junta o conteúdo (texto, Office e PDF) respeitando um orçamento.
  static Future<String> _gatherText(FileStack s) async {
    final parts = <String>[];
    var budget = 14000;
    for (final path in s.paths) {
      if (budget < 200) break;
      final snip = await FileText.snippet(path, max: budget);
      if (snip.isEmpty) continue;
      final content = snip.length > budget ? snip.substring(0, budget) : snip;
      budget -= content.length;
      parts.add('— ${p.basename(path)}:\n$content');
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
