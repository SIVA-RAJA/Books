import 'package:flutter/material.dart';
import 'package:epub_view/epub_view.dart';
import 'dart:io';
import '../models/book_model.dart';
import '../database/db_helper.dart';
import '../main.dart' show AppColors;

// ─────────────────────────────────────────────────────────────────────────────
// EpubReaderScreen
//  • Reading time tracking (mirrors pdf_reader_screen.dart)
//  • Font size controls (A− / A+)
//  • Three reading themes: dark / sepia / light
//  • Bottom chapter progress bar
//  • Table of contents sheet
// ─────────────────────────────────────────────────────────────────────────────

enum _ReadingTheme { dark, sepia, light }

class EpubReaderScreen extends StatefulWidget {
  final Book book;

  const EpubReaderScreen({super.key, required this.book});

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen>
    with WidgetsBindingObserver {
  EpubController? _epubController;
  bool _showControls = true;
  bool _isLoading = true;
  int _currentChapter = 0;
  int _totalChapters = 0;

  // ── Font size ─────────────────────────────────────────────────────────────
  double _fontSize = 16.0;

  // ── Theme ─────────────────────────────────────────────────────────────────
  _ReadingTheme _theme = _ReadingTheme.dark;

  // ── Reading time tracking ─────────────────────────────────────────────────
  DateTime _sessionStart = DateTime.now();

  // ── Theme helpers ──────────────────────────────────────────────────────────
  Color get _bgColor {
    switch (_theme) {
      case _ReadingTheme.sepia:
        return const Color(0xFFF5EDDC);
      case _ReadingTheme.light:
        return const Color(0xFFF8F8F8);
      case _ReadingTheme.dark:
        return Colors.black;
    }
  }

  Color get _textColor {
    switch (_theme) {
      case _ReadingTheme.sepia:
        return const Color(0xFF3B2F1E);
      case _ReadingTheme.light:
        return const Color(0xFF1A1A1A);
      case _ReadingTheme.dark:
        return const Color(0xFFE8E4D9);
    }
  }

  Color get _overlayColor {
    switch (_theme) {
      case _ReadingTheme.light:
        return Colors.white.withValues(alpha: 0.85);
      case _ReadingTheme.sepia:
        return const Color(0xFFF5EDDC).withValues(alpha: 0.90);
      case _ReadingTheme.dark:
        return Colors.black.withValues(alpha: 0.88);
    }
  }

  Color get _iconColor {
    switch (_theme) {
      case _ReadingTheme.light:
        return Colors.black87;
      case _ReadingTheme.sepia:
        return const Color(0xFF3B2F1E);
      case _ReadingTheme.dark:
        return Colors.white;
    }
  }

  IconData get _themeIcon {
    switch (_theme) {
      case _ReadingTheme.dark:
        return Icons.dark_mode_rounded;
      case _ReadingTheme.sepia:
        return Icons.wb_sunny_rounded;
      case _ReadingTheme.light:
        return Icons.light_mode_rounded;
    }
  }

  void _cycleTheme() {
    setState(() {
      _theme = _ReadingTheme.values[(_theme.index + 1) % _ReadingTheme.values.length];
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionStart = DateTime.now();
    _initEpub();
  }

  @override
  void dispose() {
    _recordReadingTime();
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress();
    _epubController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _recordReadingTime();
    } else if (state == AppLifecycleState.resumed) {
      _sessionStart = DateTime.now();
    }
  }

  // ── Reading time ───────────────────────────────────────────────────────────

  void _recordReadingTime() {
    final now = DateTime.now();
    final seconds = now.difference(_sessionStart).inSeconds;
    if (seconds > 0) {
      DBHelper.instance.addReadingTime(seconds);
    }
    _sessionStart = now; // reset for next segment
  }

  // ── Load EPUB ──────────────────────────────────────────────────────────────

  Future<void> _initEpub() async {
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      final file = File(widget.book.filePath);
      final bytes = await file.readAsBytes();

      final controller = EpubController(
        document: EpubDocument.openData(bytes),
      );

      if (!mounted) return;
      setState(() {
        _epubController = controller;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load EPUB: $e'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  // ── Progress ───────────────────────────────────────────────────────────────

  Future<void> _saveProgress() async {
    if (_totalChapters > 0) {
      await DBHelper.instance.updateReadingProgress(
        bookId: widget.book.id!,
        currentPage: _currentChapter,
        totalPages: _totalChapters,
      );
    }
  }

  Future<void> _saveAndNotify() async {
    _recordReadingTime();
    await _saveProgress();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Progress saved!'),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _toggleControls() => setState(() => _showControls = !_showControls);

  // ── Table of Contents ──────────────────────────────────────────────────────

  void _showTableOfContents() {
    final controller = _epubController;
    if (controller == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.borderBright,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.list_rounded,
                        size: 16, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Table of Contents',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border),
            Expanded(
              child: EpubViewTableOfContents(controller: controller),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // ── EPUB content ────────────────────────────────────────────
          if (_isLoading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Loading book…',
                    style: TextStyle(
                      color: _textColor.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else if (_epubController == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined,
                      size: 56, color: AppColors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load book',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Go Back'),
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: _toggleControls,
              child: EpubView(
                controller: _epubController!,
                builders: EpubViewBuilders<DefaultBuilderOptions>(
                  options: DefaultBuilderOptions(
                    textStyle: TextStyle(
                      color: _textColor,
                      fontSize: _fontSize,
                      height: 1.75,
                      fontFamily: 'Georgia',
                      letterSpacing: 0.2,
                    ),
                  ),
                  chapterDividerBuilder: (_) => Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.primary.withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                onChapterChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _currentChapter = value.chapterNumber + 1;
                    });
                    _saveProgress();
                  }
                },
                onDocumentLoaded: (document) {
                  setState(() {
                    _totalChapters = document.Chapters?.length ?? 0;
                  });
                },
                onDocumentError: (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $error'),
                      backgroundColor: AppColors.red,
                    ),
                  );
                },
              ),
            ),

          // ── Top bar ──────────────────────────────────────────────────
          AnimatedSlide(
            offset: _showControls ? Offset.zero : const Offset(0, -1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _buildTopBar(),
          ),

          // ── Bottom bar ────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: _showControls ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: _buildBottomBar(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _overlayColor,
            _bgColor.withValues(alpha: 0),
          ],
          stops: const [0.65, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              // Back
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: _iconColor, size: 20),
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              ),

              // Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.book.title,
                      style: TextStyle(
                        color: _iconColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_totalChapters > 0)
                      Text(
                        'Ch. $_currentChapter of $_totalChapters',
                        style: TextStyle(
                          color: _iconColor.withValues(alpha: 0.55),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),

              // Font decrease
              IconButton(
                icon: Icon(Icons.text_decrease_rounded,
                    color: _iconColor.withValues(alpha: 0.75), size: 18),
                tooltip: 'Decrease font',
                onPressed: () =>
                    setState(() => _fontSize = (_fontSize - 1).clamp(12.0, 28.0)),
              ),

              // Font increase
              IconButton(
                icon: Icon(Icons.text_increase_rounded,
                    color: _iconColor.withValues(alpha: 0.75), size: 18),
                tooltip: 'Increase font',
                onPressed: () =>
                    setState(() => _fontSize = (_fontSize + 1).clamp(12.0, 28.0)),
              ),

              // Theme cycle
              IconButton(
                icon: Icon(_themeIcon,
                    color: _iconColor.withValues(alpha: 0.75), size: 18),
                tooltip: 'Toggle theme',
                onPressed: _cycleTheme,
              ),

              // Table of Contents
              IconButton(
                icon: Icon(Icons.list_rounded,
                    color: _iconColor.withValues(alpha: 0.75), size: 20),
                tooltip: 'Table of Contents',
                onPressed: _showTableOfContents,
              ),

              // Save bookmark
              IconButton(
                icon: Icon(Icons.bookmark_add_outlined,
                    color: _iconColor.withValues(alpha: 0.75), size: 20),
                tooltip: 'Save progress',
                onPressed: _saveAndNotify,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final progress =
        _totalChapters > 0 ? _currentChapter / _totalChapters : 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            _overlayColor,
            _bgColor.withValues(alpha: 0),
          ],
          stops: const [0.6, 1.0],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress slider (chapter-based)
            SliderTheme(
              data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: AppColors.primary,
                thumbColor: AppColors.primary,
                inactiveTrackColor: _iconColor.withValues(alpha: 0.18),
                trackHeight: 2.5,
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: null, // read-only — chapter nav via TOC
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _totalChapters > 0
                      ? 'Chapter $_currentChapter of $_totalChapters  ·  ${(progress * 100).toInt()}%'
                      : 'Loading…',
                  style: TextStyle(
                    color: _iconColor.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
