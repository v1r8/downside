import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Feed de atualização do Windows. Fica num release de tag fixa
/// ("windows"), com URL estável — independente de qual release é a
/// "latest" do GitHub (o canal do Mac usa /releases/latest e não pode
/// ser afetado pelas releases do Windows).
const String kFeedURL =
    'https://github.com/v1r8/downside/releases/download/windows/appcast-win.xml';

const String kTrayIcon = 'assets/tray.ico';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(460, 340),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'Downside',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  // Fechar a janela esconde na bandeja (comportamento de app de bandeja),
  // em vez de encerrar o app. Sair de verdade só pelo menu da bandeja.
  await windowManager.setPreventClose(true);

  // Auto-update (WinSparkle). Defensivo: nunca pode derrubar o app se
  // o feed ainda não existir ou a verificação falhar.
  unawaited(_setupUpdater());

  runApp(const DownsideApp());
}

Future<void> _setupUpdater() async {
  try {
    await autoUpdater.setFeedURL(kFeedURL);
    await autoUpdater.setScheduledCheckInterval(3600);
    await autoUpdater.checkForUpdates();
  } catch (_) {
    // Sem rede / feed ausente: silencioso no M0.
  }
}

class DownsideApp extends StatelessWidget {
  const DownsideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Downside',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7DF6),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TrayListener, WindowListener {
  String _version = '…';

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
    _loadVersion();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (_) {
      if (mounted) setState(() => _version = '?');
    }
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon(kTrayIcon);
      await trayManager.setToolTip('Downside');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Mostrar painel'),
            MenuItem(key: 'check_updates', label: 'Verificar atualizações'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Sair'),
          ],
        ),
      );
    } catch (_) {
      // Sem ícone: o app ainda abre a janela.
    }
  }

  @override
  void onWindowClose() {
    // Esconde em vez de encerrar (setPreventClose está ativo).
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
        break;
      case 'check_updates':
        unawaited(autoUpdater.checkForUpdates());
        break;
      case 'quit':
        windowManager.destroy();
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.surface, scheme.surfaceContainerHighest],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_for_offline_outlined,
                  size: 56, color: scheme.primary),
              const SizedBox(height: 12),
              const Text('Downside para Windows',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('versão $_version',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('M0 — base + auto-update',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () => unawaited(autoUpdater.checkForUpdates()),
                child: const Text('Verificar atualizações'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
