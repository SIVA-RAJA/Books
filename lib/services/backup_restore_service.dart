import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import '../database/db_helper.dart';
import '../models/book_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BackupRestoreService
//
// Handles three operations:
//   1. backup()  — copy internal SQLite file → external backup.db
//   2. restore() — copy external backup.db   → internal SQLite file
//   3. syncLibraryFolder() — scan a folder for PDFs, match each file by
//                            filename to the DB, insert new entries if needed,
//                            and update filePath for all existing entries.
//
// The backup file is PERMANENT external storage — it survives APK reinstalls.
// The matching key is the PDF filename (never rename your files!).
// ─────────────────────────────────────────────────────────────────────────────

class BackupRestoreService {
  // Fixed external backup path — matches the description in the spec
  static const String _backupPath = '/storage/emulated/0/MyLibrary/backup.db';

  // ─── Backup ────────────────────────────────────────────────────────────────

  /// Copies the internal SQLite database to [_backupPath].
  /// Returns the destination path on success.
  /// Throws on error.
  Future<String> backup() async {
    await DBHelper.instance.backupTo(_backupPath);
    return _backupPath;
  }

  // ─── Restore ───────────────────────────────────────────────────────────────

  /// Restores the database from [_backupPath] and then re-scans [libraryFolder]
  /// (if provided) to update file paths and add any PDFs that are in the folder
  /// but not in the backup.
  ///
  /// Returns the number of books processed (added + updated).
  Future<int> restore({String? libraryFolderPath}) async {
    // Step 1: overwrite internal DB with the backup
    await DBHelper.instance.restoreFrom(_backupPath);

    // Step 2: if we know the library folder, re-scan to add missing files and fix file paths
    final folderToScan = libraryFolderPath ?? '/storage/emulated/0/MyLibrary';
    final result = await scanLibraryFolder(folderToScan);
    return result.added + result.updated;
  }

  // ─── Sync / Scan library folder ────────────────────────────────────────────

  /// Scans [folderPath] for PDF/EPUB/DOC/TXT files.
  ///
  /// For each file found:
  ///   • If a DB row with that filename already exists → update its filePath.
  ///   • If no DB row exists → insert a minimal entry (title from filename).
  ///
  /// Returns a [ScanResult] with counts of added and updated books.
  Future<ScanResult> scanLibraryFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      throw Exception('Folder not found: $folderPath');
    }

    int added = 0;
    int updated = 0;

    final supportedExts = {'.pdf', '.epub', '.txt'};

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      final ext = p.extension(entity.path).toLowerCase();
      if (!supportedExts.contains(ext)) continue;

      final fileName = p.basename(entity.path);
      final fileType = ext.replaceAll('.', ''); // 'pdf', 'epub', etc.

      final existing = await DBHelper.instance.getBookByFileName(fileName);

      if (existing != null) {
        // Already in DB — make sure filePath is current and cover exists
        bool needsUpdate = false;
        String? newFilePath = existing.filePath;
        String? newCoverPath = existing.coverImagePath;

        if (existing.filePath != entity.path) {
          newFilePath = entity.path;
          needsUpdate = true;
        }

        // If it's a PDF and the cover is missing (e.g. after a reinstall/restore)
        if (fileType == 'pdf' &&
            (newCoverPath == null || !await File(newCoverPath).exists())) {
          newCoverPath = await _extractPdfCover(entity.path, folderPath);
          if (newCoverPath != null) {
            needsUpdate = true;
          }
        }

        if (needsUpdate) {
          final updatedBook = existing.copyWith(
            filePath: newFilePath,
            coverImagePath: newCoverPath,
          );
          await DBHelper.instance.updateBook(updatedBook);
          updated++;
        }
      } else {
        // New file — insert with minimal metadata (user can edit later)
        final title = p
            .basenameWithoutExtension(fileName)
            .replaceAll('_', ' ')
            .replaceAll('-', ' ');

        // Auto-extract PDF cover
        String? coverPath;
        if (fileType == 'pdf') {
          coverPath = await _extractPdfCover(entity.path, folderPath);
        }

        final book = Book(
          fileName: fileName,
          title: title,
          author: 'Unknown',
          genre: 'Other',
          filePath: entity.path,
          fileType: fileType,
          coverImagePath: coverPath,
          dateAdded: DateTime.now(),
        );
        await DBHelper.instance.insertBook(book);
        added++;
      }
    }

    return ScanResult(added: added, updated: updated);
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Returns true if a backup file already exists at [_backupPath].
  Future<bool> get backupExists => File(_backupPath).exists();

  /// Returns the last-modified time of the backup file, or null if it doesn't exist.
  Future<DateTime?> get backupLastModified async {
    final file = File(_backupPath);
    if (!await file.exists()) return null;
    return file.lastModified();
  }

  // ─── PDF Cover Extraction ──────────────────────────────────────────────────

  Future<String?> _extractPdfCover(String pdfPath, String libraryPath) async {
    // Yield to the event loop to prevent freezing/OOM when scanning hundreds of PDFs
    await Future.delayed(const Duration(milliseconds: 100));
    PdfDocument? doc;
    dynamic pageImage;
    ui.Image? uiImage;
    try {
      doc = await PdfDocument.openFile(pdfPath).timeout(const Duration(seconds: 10));
      final page = doc.pages[0];

      const targetWidth = 300.0;
      final scale = targetWidth / page.width;
      final targetHeight = page.height * scale;

      pageImage = await page.render(
        fullWidth: targetWidth,
        fullHeight: targetHeight,
        backgroundColor: Colors.white,
      ).timeout(const Duration(seconds: 10));
      if (pageImage == null) return null;

      uiImage = await pageImage.createImage();
      final byteData =
          await uiImage!.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return null;

      // Save to .covers inside the external library folder so it survives uninstalls
      final coversDir = Directory('$libraryPath/.covers');
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }
      final coverName =
          'scan_cover_${DateTime.now().millisecondsSinceEpoch}.png';
      final coverFile = File('${coversDir.path}/$coverName');
      await coverFile.writeAsBytes(byteData.buffer.asUint8List());
      return coverFile.path;
    } catch (_) {
      return null; // silently skip — cover just stays null
    } finally {
      uiImage?.dispose();
      pageImage?.dispose();
      if (doc != null) {
        await doc.dispose();
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ScanResult {
  final int added; // new books inserted
  final int updated; // existing books whose filePath was refreshed

  const ScanResult({required this.added, required this.updated});
}
