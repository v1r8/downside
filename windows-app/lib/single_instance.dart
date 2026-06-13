import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Instância única: cria um mutex nomeado. Se já existir, há outro
/// Downside rodando — o chamador deve encerrar este processo.
bool anotherInstanceRunning() {
  final name = 'Downside_SingleInstance_Mutex_v1'.toNativeUtf16();
  // Mantém o mutex vivo durante toda a execução (não liberar).
  CreateMutexW(nullptr, 1, name);
  return GetLastError() == ERROR_ALREADY_EXISTS;
}
