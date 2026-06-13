import 'package:win32/win32.dart';

/// Numero de sequencia do clipboard do Windows — muda a cada copia.
/// Deteccao barata de mudanca, sem abrir o clipboard.
int clipboardSequence() => GetClipboardSequenceNumber();
