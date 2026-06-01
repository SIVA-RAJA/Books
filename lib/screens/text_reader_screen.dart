import 'dart:io';
import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../database/db_helper.dart';
import '../widgets/translation_bottom_sheet.dart';
import '../main.dart' show AppColors;

// ─────────────────────────────────────────────────────────────────────────────
// TextReaderScreen
//
// In-app reader for plain-text (.txt) files.
//  • Dark / Sepia / Light reading themes
//  • Font size controls (A− / A+)
//  • Continuous scroll with progress indicator at the bottom
//  • Reading time tracking (mirrors pdf_reader_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────

enum _ReadingTheme { dark, sepia, light }

class TextReaderScreen extends StatefulWidget {
  final Book book;
  const TextReaderScreen({super.key, required this.book});

  @override
  State<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends State<TextReaderScreen>
    with WidgetsBindingObserver {
  // ── Content state ──────────────────────────────────────────────────────────
  bool _isLoading = true;
  String? _content;
  String? _loadError;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _showControls = true;
  double _fontSize = 16.0;
  _ReadingTheme _theme = _ReadingTheme.dark;

  // ── Scroll / progress ──────────────────────────────────────────────────────
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;

  // ── Reading time tracking ──────────────────────────────────────────────────
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
        return Colors.white.withValues(alpha: 0.9);
      case _ReadingTheme.sepia:
        return const Color(0xFFF5EDDC).withValues(alpha: 0.92);
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
    _scrollController.addListener(_onScroll);
    _loadFile();
  }

  @override
  void dispose() {
    _recordReadingTime();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
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
    _sessionStart = now;
  }

  // ── Scroll progress ────────────────────────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final progress = (_scrollController.offset / max).clamp(0.0, 1.0);
    if ((progress - _scrollProgress).abs() > 0.002) {
      setState(() => _scrollProgress = progress);
      _saveScrollProgress(progress);
    }
  }

  Future<void> _saveScrollProgress(double progress) async {
    // Map scroll progress to 1000 virtual units for DB granularity
    const totalVirtual = 1000;
    final currentVirtual = (progress * totalVirtual).round();
    await DBHelper.instance.updateReadingProgress(
      bookId: widget.book.id!,
      currentPage: currentVirtual,
      totalPages: totalVirtual,
    );
  }

  // ── Load file ──────────────────────────────────────────────────────────────

  Future<void> _loadFile() async {
    try {
      final file = File(widget.book.filePath);
      if (!await file.exists()) {
        if (!mounted) return;
        setState(() {
          _loadError = 'File not found:\n${widget.book.filePath}';
          _isLoading = false;
        });
        return;
      }
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _content = text;
        _isLoading = false;
      });

      // Restore scroll position from saved progress
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && widget.book.readingProgress > 0) {
          final max = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(max * widget.book.readingProgress);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // ── Content area ────────────────────────────────────────────
          if (_isLoading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Loading…',
                    style: TextStyle(
                      color: _textColor.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else if (_loadError != null)
            _buildErrorView()
          else
            GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(22, 80, 22, 100),
                child: SelectableText(
                  _content ?? '',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: _fontSize,
                    height: 1.75,
                    fontFamily: 'Georgia',
                    letterSpacing: 0.2,
                  ),
                  contextMenuBuilder: (context, editableTextState) {
                    final List<ContextMenuButtonItem> buttonItems = [];
                    // Keep only the default 'Copy' button to avoid clutter
                    for (final item in editableTextState.contextMenuButtonItems) {
                      if (item.type == ContextMenuButtonType.copy) {
                        buttonItems.add(item);
                        break;
                      }
                    }
                    
                    buttonItems.add(ContextMenuButtonItem(
                      label: 'Translate to Tamil',
                      onPressed: () {
                        ContextMenuController.removeAny();
                        final text = editableTextState.textEditingValue.selection.textInside(editableTextState.textEditingValue.text);
                        if (text.isNotEmpty) {
                          TranslationBottomSheet.show(context, text);
                        }
                      },
                    ));
                    
                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editableTextState.contextMenuAnchors,
                      buttonItems: buttonItems,
                    );
                  },
                ),
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
          if (_content != null)
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

  // ── Error view ─────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: AppColors.red),
            const SizedBox(height: 16),
            const Text(
              'Could not open this file',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? '',
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Go Back'),
            ),
          ],
        ),
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
          colors: [_overlayColor, _bgColor.withValues(alpha: 0)],
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
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.book.fileType.toUpperCase(),
                      style: TextStyle(
                          color: _iconColor.withValues(alpha: 0.5),
                          fontSize: 10),
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
              // Theme toggle
              IconButton(
                icon: Icon(_themeIcon,
                    color: _iconColor.withValues(alpha: 0.75), size: 18),
                tooltip: 'Toggle theme',
                onPressed: _cycleTheme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_overlayColor, _bgColor.withValues(alpha: 0)],
          stops: const [0.6, 1.0],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 3,
                    color: _iconColor.withValues(alpha: 0.15),
                  ),
                  FractionallySizedBox(
                    widthFactor: _scrollProgress,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(_scrollProgress * 100).toInt()}% complete',
              style: TextStyle(
                color: _iconColor.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
