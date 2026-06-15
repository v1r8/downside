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
import 'preview.dart';
import 'settings_screen.dart';
import 'single_instance.dart';
import 'stacks.dart';
import 'stacks_bar.dart';
import 'window_corners.dart';

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

  final options = WindowOptions(
    size: Size(Prefs.i.panelWidth.value, Prefs.i.panelHeight.value),
    minimumSize: const Size(380, 300),
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
    // Pode ser redimensionada; o tamanho é lembrado entre sessões.
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(380, 300));
    await windowManager.setSize(
        Size(Prefs.i.panelWidth.value, Prefs.i.panelHeight.value));
    try {
      await Window.setEffect(
        effect: WindowEffect.acrylic,
        color: const Color(0xCC1C1C1E),
        dark: true,
      );
    } catch (_) {}
    await windowManager.hide();
  });
  roundWindowCorners();

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

  /// Verificando atualizacao: baixamos o "sempre no topo" para o diálogo
  /// do atualizador aparecer na frente, e suspendemos o auto-fechar.
  bool updating = false;

  /// Chamado ao esconder — usado para fechar a tela de Configurações.
  VoidCallback? onHidden;

  DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Geometria atual da janela (lógica) e escala — para o fechamento
  /// por distância do mouse.
  Rect? bounds;
  double dpr = 1.0;

  /// Incrementa a cada abertura — dispara a animação de entrada.
  final ValueNotifier<int> showTick = ValueNotifier<int>(0);

  Future<void> showAt(String trigger) async {
    // Já aberto: não reabre nem re-anima (evita "piscar/novas aberturas"
    // ao mexer o mouse no canto repetidamente).
    if (visible) return;
    await windowManager.setAlignment(_alignmentFor(trigger));
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
    onHidden?.call();
  }

  /// Inicia a verificação de atualização garantindo que o diálogo do
  /// atualizador apareça na frente (baixa o alwaysOnTop) e sem o painel
  /// se fechar sozinho no meio.
  Future<void> beginUpdateCheck() async {
    updating = true;
    try {
      await windowManager.setAlwaysOnTop(false);
    } catch (_) {}
    try {
      await autoUpdater.checkForUpdates();
    } catch (_) {}
    // Rede de segurança: o normal é restaurar quando o foco volta ao
    // painel (onWindowFocus). Mas se nenhum diálogo aparecer (já atualizado)
    // o foco não muda — então destravamos depois de um tempo folgado.
    Future.delayed(const Duration(seconds: 60), endUpdateCheck);
  }

  void endUpdateCheck() {
    if (!updating) return;
    updating = false;
    try {
      windowManager.setAlwaysOnTop(true);
    } catch (_) {}
  }

  void handleBlur() {
    if (!visible || pinned || settingsOpen || updating) return;
    if (DateTime.now().difference(_shownAt) <
        const Duration(milliseconds: 400)) {
      return;
    }
    hide();
  }

  /// Fecha quando o mouse se afasta além da margem (chamado pelo vigia).
  /// Vale também nas Configurações (que são fechadas junto). Pode ser
  /// desligado e a distância é configurável.
  void checkAutoHide() {
    if (!visible || pinned || updating || bounds == null) return;
    if (!Prefs.i.autoHideOnLeave.value) return;
    if (DateTime.now().difference(_shownAt) <
        const Duration(milliseconds: 600)) {
      return;
    }
    final c = globalCursorPhysical();
    if (c == null) return;
    final cursorLogical = Offset(c.dx / dpr, c.dy / dpr);
    if (!bounds!.inflate(Prefs.i.hideMargin.value).contains(cursorLogical)) {
      hide();
    }
  }

  Alignment _alignmentFor(String t) {
    switch (t) {
      case 'topLeft':
        return Alignment.topLeft;
      case 'topRight':
        return Alignment.topRight;
      case 'bottomLeft':
        return Alignment.bottomLeft;
      case 'left':
        return Alignment.centerLeft;
      case 'right':
        return Alignment.centerRight;
      default:
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
            // Menu de contexto translúcido, arredondado e bonito.
            popupMenuTheme: PopupMenuThemeData(
              color: const Color(0xF21E1E24),
              surfaceTintColor: Colors.transparent,
              elevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
              ),
              textStyle: const TextStyle(fontSize: 12.5),
            ),
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
  bool _bookHot = false; // arrasto pairando sobre o livrinho

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
    DragWatch.active.addListener(_onDragChange);
    // Ao esconder o painel, fecha a tela de Configurações se estiver aberta.
    panel.onHidden = () {
      if (panel.settingsOpen && mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    };
    _initTray();
    _hotCorner = HotCornerService(
      onTrigger: (trigger) => panel.showAt(trigger),
      enabledTriggers: () => Prefs.i.triggers.value,
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
    PreviewController.i.dismiss();
    setState(() => _query = '');
    _anim.forward(from: 0);
  }

  void _onDragChange() {
    if (mounted) setState(() {});
  }

  String _defaultTrigger() {
    final t = Prefs.i.triggers.value;
    if (t.contains('bottomRight') || t.isEmpty) return 'bottomRight';
    return t.first;
  }

  @override
  void dispose() {
    panel.showTick.removeListener(_onShow);
    DragWatch.active.removeListener(_onDragChange);
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

  /// Soltar fora das zonas (ex.: na timeline) NÃO faz nada — só as
  /// zonas (nova pilha / chip / lixeira / fichário) executam ações.
  Future<void> _onPerformDrop(PerformDropEvent event) async {
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
  void onWindowBlur() {
    PreviewController.i.dismiss();
    panel.handleBlur();
  }

  @override
  void onWindowFocus() {
    // Voltou o foco para o painel (ex.: fechou o diálogo de atualização):
    // restaura o "sempre no topo".
    panel.endUpdateCheck();
  }

  @override
  void onWindowResized() {
    // Lembra o tamanho escolhido pelo usuário entre fechar/abrir e
    // atualiza a geometria usada pelo auto-fechar (distância do mouse).
    windowManager.getSize().then((s) => Prefs.i.setPanelSize(s.width, s.height));
    windowManager.getBounds().then((b) => panel.bounds = b);
  }

  @override
  void onTrayIconMouseDown() => panel.showAt(_defaultTrigger());

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        panel.showAt(_defaultTrigger());
        break;
      case 'settings':
        panel.showAt(_defaultTrigger());
        _openSettings();
        break;
      case 'check_updates':
        unawaited(panel.beginUpdateCheck());
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
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.55),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  // Alinhado ao arredondamento nativo do Windows (DWM).
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        _header(scheme),
                        Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06)),
                        const StacksBar(),
                        Expanded(
                          child: _showFichario
                              ? FicharioView(query: _query)
                              : DownloadsView(query: _query),
                        ),
                      ],
                    ),
                    const PreviewLayer(),
                    // Alça para redimensionar a janela (canto inferior direito).
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: _resizeGrip(scheme),
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
                ValueListenableBuilder<bool>(
                  valueListenable: Prefs.i.clipboardEnabled,
                  builder: (_, on, __) => _iconButton(
                    on ? Icons.content_paste : Icons.content_paste_outlined,
                    on ? 'Ocultar itens do clipboard' : 'Mostrar itens do clipboard',
                    () {
                      final next = !on;
                      Prefs.i.setClipboardEnabled(next);
                      if (next) {
                        ClipboardMonitor.i.start();
                      } else {
                        ClipboardMonitor.i.stop();
                      }
                    },
                    active: on,
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
        final hot = cand.isNotEmpty || _bookHot;
        final dragging = DragWatch.active.value || cand.isNotEmpty;
        return DropRegion(
          formats: const [Formats.fileUri],
          hitTestBehavior: HitTestBehavior.opaque,
          onDropOver: (_) {
            DragWatch.ping();
            if (!_bookHot) setState(() => _bookHot = true);
            return DropOperation.copy;
          },
          onDropLeave: (_) {
            if (_bookHot) setState(() => _bookHot = false);
          },
          onPerformDrop: (event) async {
            final paths = await readDroppedPaths(event);
            if (paths.isNotEmpty) FicharioStore.i.archive(FileStack(0, paths));
            setState(() => _bookHot = false);
            DragWatch.end();
          },
          child: AnimatedScale(
            scale: hot ? 1.32 : (dragging ? 1.14 : 1),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: hot
                    ? [
                        BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.6),
                            blurRadius: 14,
                            spreadRadius: 1),
                      ]
                    : const [],
              ),
              child: _iconButton(
                _showFichario ? Icons.menu_book : Icons.menu_book_outlined,
                'Fichário — solte uma pilha ou arquivos aqui para arquivar',
                () => setState(() => _showFichario = !_showFichario),
                active: _showFichario || hot || dragging,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Alça discreta no canto inferior direito para redimensionar a janela
  /// (a janela é sem moldura, então oferecemos uma pega própria).
  Widget _resizeGrip(ColorScheme scheme) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpLeftDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => windowManager.startResizing(ResizeEdge.bottomRight),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CustomPaint(
            painter: _GripPainter(Colors.white.withValues(alpha: 0.28)),
          ),
        ),
      ),
    );
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

/// Três tracinhos diagonais — a clássica pega de redimensionar.
class _GripPainter extends CustomPainter {
  _GripPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final d in [5.0, 10.0, 15.0]) {
      canvas.drawLine(
        Offset(size.width - 2, size.height - d),
        Offset(size.width - d, size.height - 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GripPainter old) => old.color != color;
}
