import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// Estado global "arrastando algo sobre o painel" — controla a exibicao
/// das zonas de drop. Debounce evita piscar ao transitar entre alvos
/// aninhados (DropRegions).
class DragWatch {
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);
  static Timer? _t;

  static void ping() {
    if (!active.value) active.value = true;
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), () => active.value = false);
  }

  static void end() {
    _t?.cancel();
    if (active.value) active.value = false;
  }
}

/// Le os caminhos de arquivo de um drop (DataReader usa getValue/callback).
Future<List<String>> readDroppedPaths(PerformDropEvent event) async {
  final paths = <String>[];
  for (final item in event.session.items) {
    final reader = item.dataReader;
    if (reader == null || !reader.canProvide(Formats.fileUri)) continue;
    final completer = Completer<Uri?>();
    reader.getValue<Uri>(
      Formats.fileUri,
      (value) => completer.complete(value),
      onError: (_) => completer.complete(null),
    );
    final uri = await completer.future;
    if (uri != null) paths.add(uri.toFilePath(windows: true));
  }
  return paths;
}
