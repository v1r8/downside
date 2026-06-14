import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Extrai um trecho de texto representativo de um arquivo para a IA
/// entender o CONTEUDO (nao so o nome). Best-effort por tipo: textos,
/// documentos do Office (docx/pptx/xlsx) e PDF (aproximado).
class FileText {
  static const _textExt = {
    '.txt', '.md', '.markdown', '.csv', '.tsv', '.json', '.log', '.xml',
    '.html', '.htm', '.yaml', '.yml', '.ini', '.cfg', '.conf', '.rtf',
    '.srt', '.vtt', '.dart', '.py', '.js', '.ts', '.java', '.c', '.cpp',
    '.h', '.cs', '.go', '.rb', '.php', '.sql', '.sh', '.bat', '.ps1',
    '.css', '.scss', '.tex',
  };

  /// Retorna ate [max] caracteres de texto limpo, ou '' se nao der.
  static Future<String> snippet(String path, {int max = 2500}) async {
    final ext = p.extension(path).toLowerCase();
    try {
      if (_textExt.contains(ext)) {
        final raw = await File(path).readAsString();
        return _clean(raw, max);
      }
      if (ext == '.docx' || ext == '.pptx' || ext == '.xlsx') {
        return _clean(await _office(path, ext), max);
      }
      if (ext == '.pdf') {
        return _clean(await _pdf(path), max);
      }
    } catch (_) {}
    return '';
  }

  static String _clean(String s, int max) {
    final clean = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > max ? clean.substring(0, max) : clean;
  }

  // --- Office (OOXML = zip de XMLs) ---
  static Future<String> _office(String path, String ext) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final parts = <String>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final n = f.name;
      final keep = (ext == '.docx' && n == 'word/document.xml') ||
          (ext == '.pptx' &&
              n.startsWith('ppt/slides/slide') &&
              n.endsWith('.xml')) ||
          (ext == '.xlsx' && n == 'xl/sharedStrings.xml');
      if (!keep) continue;
      final content =
          utf8.decode(f.content as List<int>, allowMalformed: true);
      parts.add(_stripXml(content));
      if (parts.length >= 12) break;
    }
    return parts.join(' ');
  }

  static String _stripXml(String xml) {
    // Tags de paragrafo/quebra viram espaco; o resto das tags some.
    final spaced = xml.replaceAll(
        RegExp(r'</?(w:p|a:p|w:br|w:tab|a:br|tr|td)[^>]*>'), ' ');
    return spaced.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  // --- PDF (aproximado: infla streams e pega texto entre parenteses) ---
  static Future<String> _pdf(String path) async {
    final data = await File(path).readAsBytes();
    final out = StringBuffer();
    final stream = utf8.encode('stream');
    final endStream = utf8.encode('endstream');
    var i = 0;
    var found = 0;
    while (i < data.length - stream.length && found < 60) {
      final s = _indexOf(data, stream, i);
      if (s < 0) break;
      var start = s + stream.length;
      if (start < data.length && data[start] == 13) start++; // CR
      if (start < data.length && data[start] == 10) start++; // LF
      final e = _indexOf(data, endStream, start);
      if (e < 0) break;
      final chunk = data.sublist(start, e);
      List<int>? inflated;
      try {
        // zlib do dart:io (evita conflito de nome com o pacote archive).
        inflated = zlib.decode(chunk);
      } catch (_) {
        inflated = null;
      }
      final text = _pdfStrings(inflated ?? chunk);
      if (text.isNotEmpty) {
        out.write(text);
        out.write(' ');
        found++;
      }
      i = e + endStream.length;
    }
    return out.toString();
  }

  static String _pdfStrings(List<int> bytes) {
    final s = String.fromCharCodes(bytes.where((b) => b == 9 || b == 10 || (b >= 32 && b < 127)));
    final sb = StringBuffer();
    for (final m in RegExp(r'\(((?:\\.|[^\\()])*)\)').allMatches(s)) {
      final t = m.group(1) ?? '';
      if (RegExp(r'[A-Za-zÀ-ÿ]{2,}').hasMatch(t)) {
        sb.write(t
            .replaceAll(RegExp(r'\\[rnt]'), ' ')
            .replaceAll(RegExp(r'\\(\d{1,3})'), ' ')
            .replaceAll(r'\', ''));
        sb.write(' ');
      }
    }
    return sb.toString();
  }

  static int _indexOf(List<int> data, List<int> pat, int from) {
    outer:
    for (var i = from; i <= data.length - pat.length; i++) {
      for (var j = 0; j < pat.length; j++) {
        if (data[i + j] != pat[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
