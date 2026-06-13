import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'clipboard.dart';
import 'downloads_view.dart';
import 'drop_util.dart';
import 'fichario.dart';
import 'fichario_view.dart';
import 'hot_corner.dart';
import 'prefs.dart';
import 'settings_screen.dart';
import 'single_instance.dart';
import 'stacks.dart';
import 'stacks_bar.dart';

const String kFeedURL =
    'https://github.com/v1r8/downside/releases/download/windows/appcast-win.xml';
const String kTrayIcon = 'assets/tray.ico';

final PanelController panel = PanelController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Instância única: se já há um Downside aberto, encerra este.
  if (await anotherInstanceRunning()) {
    exit(0);
  }
  await windowManager.ensureInitialized();
  await Window.initialize();
  await Prefs.i.load();

  const options = WindowOptions(
    size: Size(560, 430),
    skipTaskbar: true,
    alwaysOnTop: true,
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Colors.transparent,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    // Esconde os botões nativos (minimizar/maximizar/fechar) e remove
    // a moldura — é um painel, não uma janela comum.
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    try {
      await Window.setEffect(
        effect: WindowEffect.acrylic,
        color: const Color(0xCC1C1C1E),
        dark: true,
      );
    } catch (_) {}
    await windowManager.hide();
  });

  if (Prefs.i.clipboardEnabled.value) {
    ClipboardMonitor.i.start();
  }

  unawaited(_setupUpdater());
  runApp(const DownsideApp());
}

Future<void> _setupUpdater() async {
  try {
    await autoUpdater.setFeedURL(kFeedURL);
    // Canal de teste: checa com frequencia para pegar builds novas
    // quase na hora enquanto o app esta aberto.
    await autoUpdater.setScheduledCheckInterval(120);
    await autoUpdater.checkForUpdates();
  } catch (_) {}
}

/// Controla a janela em modo painel.
class PanelController {
  bool visible = false;
  bool pinned = false;
  bool settingsOpen = false;
  DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Geometria atual da janela (lógica) e escala — para o fechamento
  /// por distância do mouse.
  Rect? bounds;
  double dpr = 1.0;

  /// Distância (px lógicos) que o mouse pode se afastar do painel antes
  /// de ele fechar sozinho (espelha o hideMargin do Mac).
  static const double margin = 220;

  /// Incrementa a cada abertura — dispara a animação de entrada.
  final ValueNotifier<int> showTick = ValueNotifier<int>(0);

  Future<void> showAt(HotCorner corner) async {
    // Já aberto: não reabre nem re-anima (evita "piscar/novas aberturas"
    // ao mexer o mouse no canto repetidamente).
    if (visible) return;
    await windowManager.setAlignment(_alignmentFor(corner));
    await windowManager.show();
    await windowManager.focus();
    visible = true;
    _shownAt = DateTime.now();
    showTick.value++;
    try {
      bounds = await windowManager.getBounds();
    } catch (_) {}
  }

  Future<void> hide() async {
    if (!visible) return;
    visible = false;
    await windowManager.hide();
  }

  void handleBlur() {
    if (!visible || pinned || settingsOpen) return;
    if (DateTime.now().difference(_shownAt) <
        const Duration(milliseconds: 400)) {
      return;
    }
    hide();
  }

  /// Fecha quando o mouse se afasta além da margem (chamado pelo vigia).
  void checkAutoHide() {
    if (!visible || pinned || settingsOpen || bounds == null) return;
    if (DateTime.now().difference(_shownAt) <
        const Duration(milliseconds: 600)) {
      return;
    }
    final c = globalCursorPhysical();
    if (c == null) return;
    final cursorLogical = Offset(c.dx / dpr, c.dy / dpr);
    if (!bounds!.inflate(margin).contains(cursorLogical)) {
      hide();
    }
  }

  Alignment _alignmentFor(HotCorner c) {
    switch (c) {
      case HotCorner.topLeft:
        return Alignment.topLeft;
      case HotCorner.topRight:
        return Alignment.topRight;
      case HotCorner.bottomLeft:
        return Alignment.bottomLeft;
      case HotCorner.bottomRight:
        return Alignment.bottomRight;
    }
  }
}

class DownsideApp extends StatelessWidget {
  const DownsideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: Prefs.i.accent,
      builder: (_, accent, __) {
        return MaterialApp(
          title: 'Downside',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.transparent,
            colorScheme: ColorScheme.fromSeed(
              seedColor: accent,
              brightness: Brightness.dark,
            ),
          ),
          // Cantos arredondados do painel em todas as telas.
          builder: (context, child) => ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: child,
          ),
          home: const PanelScaffold(),
        );
      },
    );
  }
}

class PanelScaffold extends StatefulWidget {
  const PanelScaffold({super.key});

  @override
  State<PanelScaffold> createState() => _PanelScaffoldState();
}

class _PanelScaffoldState extends State<PanelScaffold>
    with TrayListener, WindowListener, SingleTickerProviderStateMixin {
  late final HotCornerService _hotCorner;
  late final AnimationController _anim;
  Timer? _autoHide;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _showFichario = false;

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1,
    );
    panel.showTick.addListener(_onShow);
    _initTray();
    _hotCorner = HotCornerService(
      onTrigger: (corner) => panel.showAt(corner),
      enabledCorner: () => Prefs.i.corner.value,
    );
    _hotCorner.start();
    // Vigia de fechamento por distância do mouse (como no Mac).
    _autoHide = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => panel.checkAutoHide(),
    );
  }

  void _onShow() {
    _searchCtrl.clear();
    setState(() => _query = '');
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    panel.showTick.removeListener(_onShow);
    _hotCorner.stop();
    _autoHide?.cancel();
    _anim.dispose();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _focusNode.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon(kTrayIcon);
      await trayManager.setToolTip('Downside');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Mostrar painel'),
            MenuItem(key: 'settings', label: 'Configurações'),
            MenuItem(key: 'check_updates', label: 'Verificar atualizações'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Sair'),
          ],
        ),
      );
    } catch (_) {}
  }

  /// Arrastar arquivos para o painel (fora dos chips) cria uma pilha.
  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final paths = await readDroppedPaths(event);
    if (paths.isNotEmpty) StacksController.i.createWith(paths);
    DragWatch.end();
  }

  Future<void> _openSettings() async {
    panel.settingsOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    panel.settingsOpen = false;
  }

  @override
  void onWindowBlur() => panel.handleBlur();

  @override
  void onTrayIconMouseDown() => panel.showAt(Prefs.i.corner.value);

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        panel.showAt(Prefs.i.corner.value);
        break;
      case 'settings':
        panel.showAt(Prefs.i.corner.value);
        _openSettings();
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
    panel.dpr = MediaQuery.devicePixelRatioOf(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FadeTransition(
        opacity: _anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(
            CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
          ),
          alignment: Alignment.bottomRight,
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                panel.hide();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: DropRegion(
              formats: const [Formats.fileUri],
              hitTestBehavior: HitTestBehavior.opaque,
              onDropOver: (_) {
                DragWatch.ping();
                return DropOperation.copy;
              },
              onDropLeave: (_) => DragWatch.ping(),
              onPerformDrop: _onPerformDrop,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.55),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _header(scheme),
                    Divider(
                        height: 1, color: Colors.white.withValues(alpha: 0.06)),
                    const StacksBar(),
                    Expanded(
                      child: _showFichario
                          ? const FicharioView()
                          : DownloadsView(query: _query),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return SizedBox(
      height: 50,
      child: Stack(
        children: [
          // Fundo arrastavel (mover a janela) atras dos controles.
          Positioned.fill(
            child: DragToMoveArea(child: const SizedBox.expand()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                _ficharioButton(scheme),
                const SizedBox(width: 6),
                Expanded(child: _searchField(scheme)),
                const SizedBox(width: 6),
                ValueListenableBuilder<String>(
                  valueListenable: Prefs.i.viewMode,
                  builder: (_, mode, __) => _iconButton(
                    _viewIcon(mode),
                    'Visualização: ${_viewLabel(mode)}',
                    _cycleView,
                  ),
                ),
                _iconButton(
                  panel.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  panel.pinned ? 'Liberar' : 'Fixar',
                  () => setState(() => panel.pinned = !panel.pinned),
                  active: panel.pinned,
                ),
                _iconButton(
                    Icons.settings_outlined, 'Configurações', _openSettings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Livrinho do fichário: abre o histórico ao tocar; durante arrastos
  /// é alvo para arquivar arquivos (drop) ou uma pilha inteira (chip).
  Widget _ficharioButton(ColorScheme scheme) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        final list =
            StacksController.i.stacks.value.where((s) => s.id == d.data).toList();
        if (list.isNotEmpty) {
          FicharioStore.i.archive(list.first);
          StacksController.i.clearStack(d.data);
        }
      },
      builder: (context, cand, rej) {
        final hot = cand.isNotEmpty;
        return DropRegion(
          formats: const [Formats.fileUri],
          hitTestBehavior: HitTestBehavior.opaque,
          onDropOver: (_) {
            DragWatch.ping();
            return DropOperation.copy;
          },
          onPerformDrop: (event) async {
            final paths = await readDroppedPaths(event);
            if (paths.isNotEmpty) FicharioStore.i.archive(FileStack(0, paths));
            DragWatch.end();
          },
          child: _iconButton(
            _showFichario ? Icons.menu_book : Icons.menu_book_outlined,
            'Fichário — solte uma pilha ou arquivos aqui para arquivar',
            () => setState(() => _showFichario = !_showFichario),
            active: _showFichario || hot,
          ),
        );
      },
    );
  }

  void _cycleView() {
    const order = ['timeline', 'grid', 'list'];
    final next = order[(order.indexOf(Prefs.i.viewMode.value) + 1) % order.length];
    Prefs.i.setViewMode(next);
  }

  IconData _viewIcon(String mode) {
    switch (mode) {
      case 'grid':
        return Icons.grid_view_rounded;
      case 'list':
        return Icons.view_list_rounded;
      default:
        return Icons.calendar_view_day_rounded;
    }
  }

  String _viewLabel(String mode) {
    switch (mode) {
      case 'grid':
        return 'grade';
      case 'list':
        return 'lista';
      default:
        return 'linha do tempo';
    }
  }

  Widget _searchField(ColorScheme scheme) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Buscar',
          prefixIcon: const Icon(Icons.search, size: 16),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, String tip, VoidCallback onTap,
      {bool active = false}) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      color: active ? scheme.primary : null,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }
}
