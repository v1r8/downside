import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'file_icons.dart';
import 'holo_card.dart';
import 'prefs.dart';

const Set<String> _imageExt = {
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic'
};

/// Um arquivo desenhado como CARTA: retângulo opaco (sem vazamento
/// transparente), cantos arredondados, faixa/ícone na cor do tipo — ou a
/// miniatura real, no caso de imagens. O fundo pode ser claro (branco,
/// mais clean) ou escuro, conforme a preferência.
class FileCard extends StatelessWidget {
  const FileCard({
    super.key,
    required this.path,
    required this.name,
    this.isDir = false,
    this.height = 44,
    this.thumbnails = true,
  });

  final String path;
  final String name;
  final bool isDir;
  final double height;
  final bool thumbnails;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = Prefs.i.cardLightBackground.value;
    final w = height * 0.72;
    final radius = (height * 0.13).clamp(3.0, 8.0);
    var color = colorForName(name, scheme, isDir: isDir);
    // Em carta clara (branca), escurece cores muito claras (ex.: o cinza
    // padrão) para o ícone/faixa não sumirem.
    if (light && color.computeLuminance() > 0.55) {
      color = Color.lerp(color, const Color(0xFF3A3A42), 0.6)!;
    }
    final ext = p.extension(name);
    final isImage = thumbnails &&
        height >= 34 &&
        _imageExt.contains(ext.toLowerCase()) &&
        File(path).existsSync();

    Widget face;
    if (isImage) {
      face = Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: 220,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _typeFace(color, ext, light),
      );
    } else {
      face = _typeFace(color, ext, light);
    }

    return Container(
      width: w,
      height: height,
      decoration: BoxDecoration(
        // Base OPACA — cartas empilhadas não vazam umas nas outras.
        color: light ? const Color(0xFFF4F5F7) : const Color(0xFF2B2B32),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: light
              ? Colors.black.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.16),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: height * 0.12,
            offset: Offset(0, height * 0.045),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: face,
    );
  }

  /// Carta "de tipo": faixa colorida no topo + ícone do tipo no corpo.
  Widget _typeFace(Color color, String ext, bool light) {
    final band = (height * 0.22).clamp(4.0, 14.0);
    final iconSize = height * 0.42;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: band,
          color: color.withValues(alpha: 0.95),
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: height * 0.08),
          child: height >= 40 && ext.length > 1
              ? Text(
                  ext.substring(1).toUpperCase(),
                  style: TextStyle(
                    fontSize: (height * 0.16).clamp(6.0, 9.0),
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: Center(
            child: Icon(iconForName(name, isDir: isDir),
                size: iconSize, color: color),
          ),
        ),
      ],
    );
  }
}

/// Baralho/leque de até 3 cartas, opacas e sobrepostas com leve rotação.
/// Quando [holo] está ligado, uma cartinha holográfica fica ATRÁS do
/// baralho (espiando, perto das demais) — indica ação em massa.
class FileCardDeck extends StatelessWidget {
  const FileCardDeck(
      {super.key, required this.paths, this.height = 24, this.holo = false});

  final List<String> paths;
  final double height;
  final bool holo;

  @override
  Widget build(BuildContext context) {
    final shown = paths.take(3).toList();
    final n = shown.length;
    final cardW = height * 0.72;
    final step = cardW * 0.46; // deslocamento horizontal entre cartas
    final holoShift = holo ? cardW * 0.22 : 0.0;
    final totalW = holoShift + cardW + (n <= 1 ? 0 : (n - 1) * step);
    return SizedBox(
      width: totalW,
      height: height + height * 0.22,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Carta holográfica no fundo, levemente deslocada — ainda visível.
          if (holo)
            Positioned(
              left: 0,
              top: 0,
              child: Transform.rotate(
                angle: -0.22,
                child: HoloCard(width: cardW * 0.9, height: height * 0.96),
              ),
            ),
          for (var i = 0; i < n; i++)
            Positioned(
              left: holoShift + i * step,
              top: height * 0.08,
              child: Transform.rotate(
                angle: (i - (n - 1) / 2) * 0.16,
                child: FileCard(
                  path: shown[i],
                  name: p.basename(shown[i]),
                  height: height,
                  // cartinhas pequenas mostram o tipo (miniatura só nas grandes)
                  thumbnails: height >= 40,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
