import 'dart:io';

/// Instância única sem dependências nativas: a primeira instância
/// reserva uma porta de loopback; se a reserva falhar, já há outro
/// Downside rodando e o chamador deve encerrar este processo.
///
/// O socket é mantido aberto durante toda a execução (não fechar).
ServerSocket? _instanceLock;

Future<bool> anotherInstanceRunning() async {
  try {
    _instanceLock =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 47615);
    return false;
  } catch (_) {
    return true;
  }
}
