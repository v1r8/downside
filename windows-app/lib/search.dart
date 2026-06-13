import 'package:path/path.dart' as p;

enum FileKind {
  pdf,
  image,
  video,
  audio,
  archive,
  spreadsheet,
  document,
  presentation,
  folder,
  installer,
}

class ParsedQuery {
  Set<FileKind> kinds = {};
  DateTime? dateStart;
  DateTime? dateEnd;
  int? minSize;
  int? maxSize;
  List<String> nameTerms = [];

  bool get isEmpty =>
      kinds.isEmpty &&
      dateStart == null &&
      minSize == null &&
      maxSize == null &&
      nameTerms.isEmpty;
}

/// Interpretador local de buscas em linguagem natural (pt-BR + termos
/// comuns em ingles). Portado do NaturalSearch do app do Mac: tipo de
/// arquivo, periodos e tamanhos, alem de termos de nome/conteudo.
class NaturalSearch {
  static const Map<String, FileKind> _kindWords = {
    'pdf': FileKind.pdf, 'pdfs': FileKind.pdf,
    'imagem': FileKind.image, 'imagens': FileKind.image, 'foto': FileKind.image,
    'fotos': FileKind.image, 'print': FileKind.image, 'prints': FileKind.image,
    'screenshot': FileKind.image, 'png': FileKind.image, 'jpg': FileKind.image,
    'jpeg': FileKind.image, 'gif': FileKind.image,
    'video': FileKind.video, 'videos': FileKind.video, 'filme': FileKind.video,
    'mp4': FileKind.video, 'mov': FileKind.video,
    'audio': FileKind.audio, 'audios': FileKind.audio, 'musica': FileKind.audio,
    'mp3': FileKind.audio, 'wav': FileKind.audio,
    'zip': FileKind.archive, 'rar': FileKind.archive,
    'compactado': FileKind.archive, 'compactados': FileKind.archive,
    'planilha': FileKind.spreadsheet, 'planilhas': FileKind.spreadsheet,
    'excel': FileKind.spreadsheet, 'xls': FileKind.spreadsheet,
    'xlsx': FileKind.spreadsheet, 'csv': FileKind.spreadsheet,
    'documento': FileKind.document, 'documentos': FileKind.document,
    'doc': FileKind.document, 'docx': FileKind.document, 'word': FileKind.document,
    'texto': FileKind.document, 'txt': FileKind.document,
    'apresentacao': FileKind.presentation, 'ppt': FileKind.presentation,
    'pptx': FileKind.presentation, 'slides': FileKind.presentation,
    'pasta': FileKind.folder, 'pastas': FileKind.folder,
    'app': FileKind.installer, 'apps': FileKind.installer,
    'instalador': FileKind.installer, 'exe': FileKind.installer,
    'msi': FileKind.installer,
  };

  static const Map<String, FileKind> _extKinds = {
    'pdf': FileKind.pdf,
    'png': FileKind.image, 'jpg': FileKind.image, 'jpeg': FileKind.image,
    'gif': FileKind.image, 'heic': FileKind.image, 'webp': FileKind.image,
    'bmp': FileKind.image, 'tiff': FileKind.image,
    'mp4': FileKind.video, 'mov': FileKind.video, 'mkv': FileKind.video,
    'avi': FileKind.video, 'webm': FileKind.video,
    'mp3': FileKind.audio, 'wav': FileKind.audio, 'm4a': FileKind.audio,
    'flac': FileKind.audio, 'aac': FileKind.audio,
    'zip': FileKind.archive, 'rar': FileKind.archive, '7z': FileKind.archive,
    'tar': FileKind.archive, 'gz': FileKind.archive,
    'xls': FileKind.spreadsheet, 'xlsx': FileKind.spreadsheet,
    'csv': FileKind.spreadsheet,
    'doc': FileKind.document, 'docx': FileKind.document, 'txt': FileKind.document,
    'rtf': FileKind.document, 'md': FileKind.document,
    'ppt': FileKind.presentation, 'pptx': FileKind.presentation,
    'exe': FileKind.installer, 'msi': FileKind.installer,
  };

  static const Set<String> _stop = {
    'de', 'da', 'do', 'das', 'dos', 'a', 'o', 'as', 'os', 'um', 'uma',
    'que', 'com', 'sem', 'em', 'no', 'na', 'e', 'ou', 'para', 'me',
    'mostre', 'mostra', 'mostrar', 'liste', 'lista', 'busca', 'buscar',
    'procura', 'procurar', 'quero', 'ver', 'todos', 'todas', 'arquivo',
    'arquivos', 'item', 'itens', 'meu', 'meus', 'minha', 'minhas',
  };

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');

  static ParsedQuery parse(String text) {
    final q = ParsedQuery();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tokens = _norm(text)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (_kindWords.containsKey(t)) {
        q.kinds.add(_kindWords[t]!);
        continue;
      }
      switch (t) {
        case 'hoje':
          q.dateStart = today;
          q.dateEnd = today.add(const Duration(days: 1));
          continue;
        case 'ontem':
          q.dateStart = today.subtract(const Duration(days: 1));
          q.dateEnd = today;
          continue;
        case 'semana':
          q.dateStart = today.subtract(const Duration(days: 7));
          q.dateEnd = now.add(const Duration(days: 1));
          continue;
        case 'mes':
          q.dateStart = DateTime(now.year, now.month, 1);
          q.dateEnd = now.add(const Duration(days: 1));
          continue;
        case 'grande':
        case 'grandes':
        case 'pesado':
          q.minSize = 50 * 1000 * 1000;
          continue;
        case 'pequeno':
        case 'pequenos':
        case 'leve':
          q.maxSize = 1000 * 1000;
          continue;
      }
      // "maior/menor que X mb"
      if ((t == 'maior' || t == 'menor' || t == 'acima' || t == 'abaixo') &&
          i + 1 < tokens.length) {
        var j = i + 1;
        if (tokens[j] == 'que' || tokens[j] == 'de') j++;
        if (j + 1 < tokens.length) {
          final value = double.tryParse(tokens[j].replaceAll(',', '.'));
          final unit = tokens[j + 1];
          if (value != null) {
            final bytes = _bytes(value, unit);
            if (bytes != null) {
              if (t == 'maior' || t == 'acima') {
                q.minSize = bytes;
              } else {
                q.maxSize = bytes;
              }
              i = j + 1;
              continue;
            }
          }
        }
      }
      if (_stop.contains(t)) continue;
      if (t.length >= 2) q.nameTerms.add(t);
    }
    return q;
  }

  static int? _bytes(double v, String unit) {
    switch (unit) {
      case 'kb':
        return (v * 1000).round();
      case 'mb':
      case 'mega':
      case 'megas':
        return (v * 1000 * 1000).round();
      case 'gb':
      case 'giga':
      case 'gigas':
        return (v * 1000 * 1000 * 1000).round();
    }
    return null;
  }

  static bool matches({
    required String name,
    required bool isDir,
    required int size,
    required DateTime date,
    required ParsedQuery query,
    String? content,
  }) {
    if (query.kinds.isNotEmpty) {
      final k = isDir ? FileKind.folder : _extKinds[_ext(name)];
      if (k == null || !query.kinds.contains(k)) return false;
    }
    if (query.dateStart != null &&
        (date.isBefore(query.dateStart!) || date.isAfter(query.dateEnd!))) {
      return false;
    }
    if (query.minSize != null && size < query.minSize!) return false;
    if (query.maxSize != null && (isDir || size > query.maxSize!)) return false;
    if (query.nameTerms.isNotEmpty) {
      final hayName = _norm(name);
      final hayContent = content != null ? _norm(content) : '';
      for (final term in query.nameTerms) {
        if (!hayName.contains(term) && !hayContent.contains(term)) return false;
      }
    }
    return true;
  }

  static String _ext(String name) {
    final e = p.extension(name);
    return e.isEmpty ? '' : e.substring(1).toLowerCase();
  }
}
