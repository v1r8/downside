import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

enum HotCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Detecta o mouse parado num canto da tela, espelhando a abordagem do
/// Mac: polling leve (~16x/s) da posição global do cursor via Win32
/// (sem hook elevado / UAC), com tempo de permanência (dwell) e
/// rearme só depois que o mouse sai do canto.
class HotCornerService {
  HotCornerService({required this.onTrigger});

  final void Function(HotCorner corner) onTrigger;

  /// Canto ativo (por enquanto fixo; vira configurável no M1c).
  HotCorner enabled = HotCorner.bottomRight;

  Timer? _timer;
  HotCorner? _dwellCorner;
  DateTime? _dwellStart;
  bool _armed = true;

  static const Duration _dwell = Duration(milliseconds: 120);
  static const int _zone = 6; // px físicos

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

    HotCorner? inCorner;
    if (x <= _zone && y <= _zone) {
      inCorner = HotCorner.topLeft;
    } else if (x >= w - 1 - _zone && y <= _zone) {
      inCorner = HotCorner.topRight;
    } else if (x <= _zone && y >= h - 1 - _zone) {
      inCorner = HotCorner.bottomLeft;
    } else if (x >= w - 1 - _zone && y >= h - 1 - _zone) {
      inCorner = HotCorner.bottomRight;
    }

    // Só o canto habilitado conta.
    final active = inCorner == enabled ? inCorner : null;

    if (active != null) {
      if (!_armed) return;
      if (_dwellCorner == active && _dwellStart != null) {
        if (DateTime.now().difference(_dwellStart!) >= _dwell) {
          _dwellStart = null;
          _dwellCorner = null;
          _armed = false; // só rearma quando sair do canto
          onTrigger(active);
        }
      } else {
        _dwellCorner = active;
        _dwellStart = DateTime.now();
      }
    } else {
      _dwellStart = null;
      _dwellCorner = null;
      _armed = true;
    }
  }
}
