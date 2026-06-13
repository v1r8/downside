import 'dart:async';
import 'dart:ffi';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Posição global do cursor em pixels físicos (ou null em falha).
Offset? globalCursorPhysical() {
  final p = calloc<POINT>();
  try {
    if (GetCursorPos(p) == 0) return null;
    return Offset(p.ref.x.toDouble(), p.ref.y.toDouble());
  } finally {
    calloc.free(p);
  }
}

/// Detecta o mouse parado num canto OU numa lateral da tela. Polling
/// leve (~16x/s) da posição global do cursor via Win32 (sem hook), com
/// tempo de permanência (dwell) e rearme ao sair. O conjunto de
/// gatilhos ativos é lido das preferências a cada verificação.
class HotCornerService {
  HotCornerService({required this.onTrigger, required this.enabledTriggers});

  final void Function(String trigger) onTrigger;
  final Set<String> Function() enabledTriggers;

  Timer? _timer;
  String? _dwellKey;
  DateTime? _dwellStart;
  bool _armed = true;

  static const Duration _dwell = Duration(milliseconds: 120);
  static const int _zone = 6; // px físicos (cantos)
  static const int _edge = 2; // px físicos (laterais)
  static const int _band = 120; // margem que separa lateral dos cantos

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    final point = calloc<POINT>();
    int x, y;
    try {
      if (GetCursorPos(point) == 0) return;
      x = point.ref.x;
      y = point.ref.y;
    } finally {
      calloc.free(point);
    }

    final w = GetSystemMetrics(SM_CXSCREEN);
    final h = GetSystemMetrics(SM_CYSCREEN);
    if (w <= 0 || h <= 0) return;

    final enabled = enabledTriggers();
    String? key;

    // Cantos primeiro.
    if (x <= _zone && y <= _zone) {
      key = 'topLeft';
    } else if (x >= w - 1 - _zone && y <= _zone) {
      key = 'topRight';
    } else if (x <= _zone && y >= h - 1 - _zone) {
      key = 'bottomLeft';
    } else if (x >= w - 1 - _zone && y >= h - 1 - _zone) {
      key = 'bottomRight';
    } else if (y > _band && y < h - _band) {
      // Laterais (fora da faixa dos cantos).
      if (x <= _edge) {
        key = 'left';
      } else if (x >= w - 1 - _edge) {
        key = 'right';
      }
    }

    final active = (key != null && enabled.contains(key)) ? key : null;

    if (active != null) {
      if (!_armed) return;
      if (_dwellKey == active && _dwellStart != null) {
        if (DateTime.now().difference(_dwellStart!) >= _dwell) {
          _dwellStart = null;
          _dwellKey = null;
          _armed = false;
          onTrigger(active);
        }
      } else {
        _dwellKey = active;
        _dwellStart = DateTime.now();
      }
    } else {
      _dwellStart = null;
      _dwellKey = null;
      _armed = true;
    }
  }
}
