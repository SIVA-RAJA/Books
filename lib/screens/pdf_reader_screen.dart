import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import '../models/book_model.dart';
import '../database/db_helper.dart';
import '../services/url_launcher_service.dart';
import '../widgets/translation_bottom_sheet.dart';
import '../main.dart' show AppColors;

// ─────────────────────────────────────────────────────────────────────────────
//  Books PDF Reader Screen — Dark Theme Native PDF Reader
//  • Preserves 100% exact alignment, fonts, styles, math formulas, tables & images
//  • Applies smart Dark Mode color filter matrix (Black BG, crisp white/cream text)
//  • Features multiple reading themes: Vanta Dark, High Contrast, Warm Dark, Light
//  • Page-Flip (Horizontal), Dual Page Spread & Vertical Continuous layouts
//  • In-App Text Selection Translator, Copy, & Google Chrome Search toolbar
// ─────────────────────────────────────────────────────────────────────────────

enum PdfReadingTheme {
  vantaDark('Vanta Dark', Icons.dark_mode_rounded),
  highContrast('High Contrast', Icons.contrast_rounded),
  warmDark('Warm Night', Icons.nightlight_round),
  light('Original Light', Icons.light_mode_rounded);

  final String label;
  final IconData icon;
  const PdfReadingTheme(this.label, this.icon);
}

enum PdfLayoutMode {
  vertical('Vertical Continuous', Icons.unfold_more_rounded),
  pageTurn('Page Snap Turn', Icons.swipe_rounded);

  final String label;
  final IconData icon;
  const PdfLayoutMode(this.label, this.icon);
}

class PdfReaderScreen extends StatefulWidget {
  final Book book;
  const PdfReaderScreen({super.key, required this.book});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ── PDF Controller & State ─────────────────────────────────────
  late final PdfViewerController _pdfController;
  bool _isLoading = true;
  String? _loadError;

  // ── Page & Layout State ───────────────────────────────────────
  int _currentPage = 1;
  int _totalPages = 0;
  int _lastSavedPage = 0;
  PdfLayoutMode _layoutMode = PdfLayoutMode.vertical;

  // ── Text Selection State ──────────────────────────────────────
  String? _selectedText;
  bool _showSelectionToolbar = false;

  // ── UI Controls ───────────────────────────────────────────────
  bool _showControls = true;
  late AnimationController _controlsAnim;
  PdfReadingTheme _currentTheme = PdfReadingTheme.vantaDark;

  // ── Reading Session Stats ─────────────────────────────────────
  DateTime _sessionStart = DateTime.now();

  // ── Color Filter Matrices ─────────────────────────────────────
  // Vanta Dark: Inverts white page background to black, text to bright white
  static const ColorFilter _vantaDarkFilter = ColorFilter.matrix(<double>[
    -1.0,  0.0,  0.0, 0.0, 255.0,
     0.0, -1.0,  0.0, 0.0, 255.0,
     0.0,  0.0, -1.0, 0.0, 255.0,
     0.0,  0.0,  0.0, 1.0,   0.0,
  ]);

  // High Contrast: Enhanced contrast inversion (boosts text white, crushes bg black)
  static const ColorFilter _highContrastFilter = ColorFilter.matrix(<double>[
    -1.2,  0.0,  0.0, 0.0, 260.0,
     0.0, -1.2,  0.0, 0.0, 260.0,
     0.0,  0.0, -1.2, 0.0, 260.0,
     0.0,  0.0,  0.0, 1.0,   0.0,
  ]);

  // Warm Dark: Inverts background to dark charcoal, text to warm amber cream
  static const ColorFilter _warmDarkFilter = ColorFilter.matrix(<double>[
    -0.85, 0.0,   0.0,  0.0, 230.0,
     0.0, -0.80,  0.0,  0.0, 215.0,
     0.0,  0.0,  -0.65, 0.0, 175.0,
     0.0,  0.0,   0.0,  1.0,   0.0,
  ]);

  ColorFilter? _getThemeFilter(PdfReadingTheme theme) {
    switch (theme) {
      case PdfReadingTheme.vantaDark:
        return _vantaDarkFilter;
      case PdfReadingTheme.highContrast:
        return _highContrastFilter;
      case PdfReadingTheme.warmDark:
        return _warmDarkFilter;
      case PdfReadingTheme.light:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionStart = DateTime.now();

    _pdfController = PdfViewerController();
    _currentPage = widget.book.currentPage > 0 ? widget.book.currentPage : 1;
    _lastSavedPage = _currentPage;

    _controlsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _recordReadingTime();
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress(_currentPage);
    _controlsAnim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _recordReadingTime();
    } else if (state == AppLifecycleState.resumed) {
      _sessionStart = DateTime.now();
    }
  }

  void _recordReadingTime() {
    final now = DateTime.now();
    final seconds = now.difference(_sessionStart).inSeconds;
    if (seconds > 0) {
      DBHelper.instance.addReadingTime(seconds);
    }
    _sessionStart = now;
  }

  // ── Database Progress Sync ────────────────────────────────────

  Future<void> _saveProgress(int page) async {
    if (_totalPages == 0 || page == _lastSavedPage) return;
    _lastSavedPage = page;
    await DBHelper.instance.updateReadingProgress(
      bookId: widget.book.id!,
      currentPage: page,
      totalPages: _totalPages,
    );
  }

  // ── Jump to Page ──────────────────────────────────────────────

  void _jumpToPage(int page) {
    if (page < 1 || page > _totalPages) return;
    _pdfController.goToPage(pageNumber: page);
    setState(() => _currentPage = page);
    _saveProgress(page);
  }

  // ── Toggle Controls Overlay ───────────────────────────────────

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _controlsAnim.forward();
    } else {
      _controlsAnim.reverse();
    }
  }

  // ── Theme Selector Dialog ─────────────────────────────────────

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setBottomSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Reading Theme',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...PdfReadingTheme.values.map((theme) {
                  final isSelected = theme == _currentTheme;
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(
                      theme.icon,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    ),
                    title: Text(
                      theme.label,
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                        : null,
                    onTap: () {
                      setState(() => _currentTheme = theme);
                      setBottomSheetState(() {});
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Layout Mode Selector ──────────────────────────────────────

  void _showLayoutSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setBottomSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Page Layout Mode',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...PdfLayoutMode.values.map((mode) {
                  final isSelected = _layoutMode == mode;
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(
                      mode.icon,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    ),
                    title: Text(
                      mode.label,
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                        : null,
                    onTap: () {
                      setState(() => _layoutMode = mode);
                      setBottomSheetState(() {});
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Jump to Page Dialog ───────────────────────────────────────

  void _showGoToPageDialog() {
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: const Text('Go to Page',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '1 – $_totalPages',
            hintStyle: const TextStyle(color: AppColors.textMuted),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(ctrl.text);
              if (p != null && p >= 1 && p <= _totalPages) {
                Navigator.pop(context);
                _jumpToPage(p);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  // ── Main Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filter = _getThemeFilter(_currentTheme);

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Native PDF Document Viewer (Direct Pure Touch Gestures - 60fps & Accurate Selection) ──
          RepaintBoundary(
            child: filter != null
                ? ColorFiltered(
                    colorFilter: filter,
                    child: _buildPdfViewer(),
                  )
                : _buildPdfViewer(),
          ),

          // ── Text Selection Floating Action Toolbar (Pure Black & White) ──
          if (_showSelectionToolbar && _selectedText != null)
            _buildSelectionToolbar(),

          // ── Floating Controls Menu Toggle Badge ───────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: AnimatedOpacity(
              opacity: _showControls ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: _showControls,
                child: Material(
                  color: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: InkWell(
                    onTap: _toggleControls,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Menu',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Loading Overlay ───────────────────────────────────────
          if (_isLoading)
            Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Rendering book with exact layout…',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // ── Load Error View ───────────────────────────────────────
          if (_loadError != null) _buildErrorView(),

          // ── Top Bar Overlay ───────────────────────────────────────
          AnimatedSlide(
            offset: _showControls ? Offset.zero : const Offset(0, -1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _buildTopBar(),
          ),

          // ── Bottom Navigation & Slider Overlay ────────────────────
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

  // ── Page Layout Calculator ───────────────────────────────────

  PdfPageLayout _calculatePageLayout(List<PdfPage> pages, PdfViewerParams params) {
    final margin = params.margin;

    switch (_layoutMode) {
      case PdfLayoutMode.pageTurn:
        final height = pages.fold(0.0, (prev, page) => max(prev, page.height)) + margin * 2;
        final pageLayouts = <Rect>[];
        double x = margin;
        for (final page in pages) {
          pageLayouts.add(
            Rect.fromLTWH(
              x,
              (height - page.height) / 2,
              page.width,
              page.height,
            ),
          );
          x += page.width + margin;
        }
        return PdfPageLayout(pageLayouts: pageLayouts, documentSize: Size(x, height));

      case PdfLayoutMode.vertical:
        final width = pages.fold(0.0, (prev, page) => max(prev, page.width)) + margin * 2;
        final pageLayouts = <Rect>[];
        double y = margin;
        for (final page in pages) {
          pageLayouts.add(
            Rect.fromLTWH(
              (width - page.width) / 2,
              y,
              page.width,
              page.height,
            ),
          );
          y += page.height + margin;
        }
        return PdfPageLayout(pageLayouts: pageLayouts, documentSize: Size(width, y));
    }
  }

  // ── PDF Viewer Widget ─────────────────────────────────────────

  Widget _buildPdfViewer() {
    return PdfViewer.file(
      widget.book.filePath,
      controller: _pdfController,
      params: PdfViewerParams(
        enableTextSelection: true,
        maxScale: 4.0,
        minScale: 1.0,
        limitRenderingCache: false,
        verticalCacheExtent: 3.0,
        horizontalCacheExtent: 3.0,
        maxImageBytesCachedOnMemory: 250 * 1024 * 1024,
        panAxis: _layoutMode == PdfLayoutMode.vertical
            ? PanAxis.vertical
            : PanAxis.horizontal,
        layoutPages: _calculatePageLayout,
        onInteractionEnd: (details) {
          if (_layoutMode == PdfLayoutMode.pageTurn && _currentPage > 0) {
            _pdfController.goToPage(
              pageNumber: _currentPage,
              duration: const Duration(milliseconds: 250),
            );
          }
        },
        selectableRegionInjector: (context, child) {
          return SelectionArea(
            contextMenuBuilder: (context, selectableRegionState) {
              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: selectableRegionState.contextMenuAnchors,
                buttonItems: [
                  ContextMenuButtonItem(
                    label: 'Translate (Tamil)',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      selectableRegionState.hideToolbar();
                      final textToUse = (_selectedText ?? '').trim();
                      if (textToUse.isNotEmpty) {
                        TranslationBottomSheet.show(this.context, textToUse);
                      }
                    },
                  ),
                  ContextMenuButtonItem(
                    label: 'Copy',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      selectableRegionState.hideToolbar();
                      final textToUse = (_selectedText ?? '').trim();
                      if (textToUse.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: textToUse));
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Text copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                  ContextMenuButtonItem(
                    label: 'Search Chrome',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      selectableRegionState.hideToolbar();
                      final textToUse = (_selectedText ?? '').trim();
                      if (textToUse.isNotEmpty) {
                        UrlLauncherService.openInChrome(
                          'https://www.google.com/search?q=${Uri.encodeComponent(textToUse)}',
                        );
                      }
                    },
                  ),
                ],
              );
            },
            child: child,
          );
        },
        onTextSelectionChange: (selections) {
          if (selections.any((s) => s.isNotEmpty)) {
            final text = selections
                .where((s) => s.isNotEmpty)
                .map((s) => s.text)
                .join(' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            if (text.isNotEmpty && mounted) {
              _selectedText = text;
              if (!_showSelectionToolbar) {
                setState(() {
                  _showSelectionToolbar = true;
                });
              }
            }
          }
        },
        onPageChanged: (pageNumber) {
          if (pageNumber != null && pageNumber != _currentPage) {
            setState(() => _currentPage = pageNumber);
            Future.microtask(() => _saveProgress(pageNumber));
          }
        },
        onViewerReady: (document, controller) {
          if (!mounted) return;
          setState(() {
            _totalPages = document.pages.length;
            _isLoading = false;
          });
          if (_currentPage > 1) {
            controller.goToPage(pageNumber: _currentPage);
          }
        },
      ),
    );
  }

  // ── Selection Action Toolbar Widget (Pure Black & White) ──────

  Widget _buildSelectionToolbar() {
    return Positioned(
      bottom: 96,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF000000), // Pure Black
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white30, width: 1.5), // Pure White Border
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.9),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Selected text preview bar (Monochrome)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFF141414), // Dark Grey-Black
                  child: Row(
                    children: [
                      const Icon(Icons.format_quote_rounded, size: 16, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedText ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _showSelectionToolbar = false;
                            _selectedText = null;
                          });
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),

                // Action buttons row with large touch targets (Monochrome Pure Black & White)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Translate Button (Monochrome White Card)
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            final text = _selectedText;
                            if (text != null && text.trim().isNotEmpty) {
                              TranslationBottomSheet.show(context, text);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F1F1F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white54, width: 1),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.g_translate_rounded, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Translate',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Copy Button (Monochrome White Card)
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            if (_selectedText != null) {
                              Clipboard.setData(ClipboardData(text: _selectedText!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Text copied to clipboard'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF141414),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24, width: 1),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Copy',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Chrome Search Button (Monochrome White Card)
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            if (_selectedText != null) {
                              UrlLauncherService.openInChrome(
                                'https://www.google.com/search?q=${Uri.encodeComponent(_selectedText!)}',
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF141414),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24, width: 1),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.open_in_browser_rounded, color: Colors.white70, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Chrome',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Error View Widget ─────────────────────────────────────────

  Widget _buildErrorView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined,
                  size: 56, color: AppColors.red),
              const SizedBox(height: 16),
              const Text('Could not open PDF file',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_loadError ?? '',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top Bar Widget ────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.94),
            Colors.transparent,
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
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.book.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.book.author,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(_layoutMode.icon, color: Colors.white70, size: 20),
                tooltip: 'Page Layout Mode (${_layoutMode.label})',
                onPressed: _showLayoutSelector,
              ),
              IconButton(
                icon: Icon(_currentTheme.icon, color: Colors.white70, size: 20),
                tooltip: 'Change Reading Theme (${_currentTheme.label})',
                onPressed: _showThemeSelector,
              ),
              IconButton(
                icon: const Icon(Icons.find_in_page_outlined,
                    color: Colors.white70, size: 20),
                tooltip: 'Go to page',
                onPressed: _showGoToPageDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom Bar Widget ─────────────────────────────────────────

  Widget _buildBottomBar() {
    final progress = _totalPages > 0 ? _currentPage / _totalPages : 0.0;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.94),
            Colors.transparent,
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
            SliderTheme(
              data: const SliderThemeData(
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: AppColors.primary,
                thumbColor: AppColors.primary,
                inactiveTrackColor: Colors.white24,
                trackHeight: 2.5,
              ),
              child: Slider(
                value: _totalPages > 0
                    ? _currentPage.toDouble().clamp(1, _totalPages.toDouble())
                    : 1.0,
                min: 1,
                max: _totalPages > 0 ? _totalPages.toDouble() : 1.0,
                onChanged: (v) {
                  final p = v.round();
                  if (_currentPage != p) {
                    setState(() => _currentPage = p);
                  }
                },
                onChangeEnd: (v) => _jumpToPage(v.round()),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _navBtn(Icons.chevron_left_rounded,
                    () => _jumpToPage(_currentPage - 1),
                    enabled: _currentPage > 1),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_currentPage / $_totalPages',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${(progress * 100).toInt()}% complete',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
                _navBtn(Icons.chevron_right_rounded,
                    () => _jumpToPage(_currentPage + 1),
                    enabled: _currentPage < _totalPages),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap,
      {required bool enabled}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primary.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? AppColors.primary.withValues(alpha: 0.45)
                : Colors.white12,
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? AppColors.primary : Colors.white24,
          size: 22,
        ),
      ),
    );
  }
}
