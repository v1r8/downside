import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Operacoes de shell do Windows: mover para a Lixeira (com desfazer) e
/// revelar um arquivo selecionado no Explorer.
class WinShell {
  /// Move arquivos para a Lixeira (FOF_ALLOWUNDO) - recuperavel.
  static bool moveToRecycleBin(List<String> paths) {
    if (paths.isEmpty) return true;
    // pFrom: lista separada por NUL e terminada por NUL extra
    // (toNativeUtf16 acrescenta o terminador final).
    final nul = String.fromCharCode(0);
    final joined = paths.join(nul) + nul;
    final pFrom = joined.toNativeUtf16();
    final op = calloc<SHFILEOPSTRUCT>();
    try {
      op.ref.wFunc = FO_DELETE;
      op.ref.pFrom = pFrom;
      op.ref.fFlags =
          FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;
      return SHFileOperation(op) == 0;
    } finally {
      calloc.free(pFrom);
      calloc.free(op);
    }
  }

  /// Abre o Explorer com o item selecionado.
  static void revealInExplorer(String path) {
    try {
      Process.run('explorer.exe', ['/select,$path']);
    } catch (_) {}
  }
}
