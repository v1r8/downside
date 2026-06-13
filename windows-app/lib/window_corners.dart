import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Arredonda os cantos da janela como os apps nativos do Windows 11
/// (DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND). Necessário porque a
/// janela é WS_POPUP (sem moldura), que não arredonda sozinha.
void roundWindowCorners() {
  final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  try {
    final hwnd = FindWindow(cls, nullptr);
    if (hwnd == 0) return;
    final pref = calloc<Int32>()..value = 2; // DWMWCP_ROUND
    try {
      DwmSetWindowAttribute(
        hwnd,
        33, // DWMWA_WINDOW_CORNER_PREFERENCE
        pref.cast(),
        sizeOf<Int32>(),
      );
    } finally {
      calloc.free(pref);
    }
  } finally {
    calloc.free(cls);
  }
}
