import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Icone e cor por tipo de arquivo — compartilhado entre a grade da
/// pasta e o deck das pilhas.
IconData iconForName(String name, {bool isDir = false}) {
  if (isDir) return Icons.folder;
  switch (p.extension(name).toLowerCase()) {
    case '.pdf':
      return Icons.picture_as_pdf;
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.gif':
    case '.webp':
    case '.heic':
      return Icons.image;
    case '.mp4':
    case '.mov':
    case '.mkv':
    case '.avi':
      return Icons.movie;
    case '.mp3':
    case '.wav':
    case '.m4a':
    case '.flac':
      return Icons.audiotrack;
    case '.zip':
    case '.rar':
    case '.7z':
    case '.tar':
    case '.gz':
      return Icons.folder_zip;
    case '.xls':
    case '.xlsx':
    case '.csv':
      return Icons.table_chart;
    case '.doc':
    case '.docx':
    case '.txt':
    case '.md':
      return Icons.description;
    case '.exe':
    case '.msi':
      return Icons.terminal;
    default:
      return Icons.insert_drive_file;
  }
}

Color colorForName(String name, ColorScheme scheme, {bool isDir = false}) {
  if (isDir) return const Color(0xFF6FB1FC);
  switch (p.extension(name).toLowerCase()) {
    case '.pdf':
      return const Color(0xFFE5534B);
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.gif':
    case '.webp':
    case '.heic':
      return const Color(0xFF55B973);
    case '.xls':
    case '.xlsx':
    case '.csv':
      return const Color(0xFF3FA06B);
    default:
      return scheme.onSurfaceVariant;
  }
}
