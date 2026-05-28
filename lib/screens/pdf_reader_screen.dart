import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/book_model.dart';
import '../database/db_helper.dart';
import '../main.dart' show AppColors;

// ─────────────────────────────────────────────────────────────────────────────
//  Books PDF Reader
//  • UI like EPUB: dark canvas, cream text, serif font, immersive full-screen
//  • Scrolls continuously like a PDF (one long vertical scroll)
//  • Detects the visible page via ItemPositionsListener → saves to DB immediately
//  • Back button (‹) always pops back to the BookDetailScreen
//  • Font-size controls (A− / A+)
//  • Jump-to-page dialog
// ─────────────────────────────────────────────────────────────────────────────

class PdfReaderScreen extends StatefulWidget {
  final Book book;
  const PdfReaderScreen({super.key, required this.book});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen>
    with SingleTickerProviderStateMixin {
  // ── PDF document ──────────────────────────────────────────────
  PdfDocument? _document;
  bool _isLoading = true;
  String? _loadError;

  // ── Page state ────────────────────────────────────────────────
  int _currentPage = 1;
  int _totalPages = 0;

  // Per-page text cache: page# → extracted text ('' = image-only page)
  final Map<int, String> _textCache = {};
  // Track active extraction tasks to prevent redundant Future creation
  final Map<int, Future<String>> _extractionTasks = {};

  // ── Scroll ────────────────────────────────────────────────────
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  // ── UI ────────────────────────────────────────────────────────
  bool _showControls = true;
  double _fontSize = 17.0;
  late AnimationController _controlsAnim;

  // Reading theme
  static const _bgColor    = Color(0xFF0D0D14);
  static const _textColor  = Color(0xFFE8E4D9);
  static const _lineHeight = 1.78;

  // Debounce: last page we actually wrote to DB
  int _lastSavedPage = 0;

  @override
  void initState() {
    super.initState();
    _currentPage  = widget.book.currentPage > 0 ? widget.book.currentPage : 1;
    _lastSavedPage = _currentPage;

    _controlsAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadDocument();

    // Listen to scroll → update current page + save immediately
    _itemPositionsListener.itemPositions.addListener(_onScroll);
  }

  @override
  void dispose() {
    _saveProgress(_currentPage); // always save on exit
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    _controlsAnim.dispose();
    _document?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Load PDF ──────────────────────────────────────────────────

  Future<void> _loadDocument() async {
    // Add small delay to let navigation transition finish smoothly
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      final doc = await PdfDocument.openFile(widget.book.filePath);
      if (!mounted) return;

      setState(() {
        _document   = doc;
        _totalPages = doc.pages.length;
        _isLoading  = false;
      });

      // Jump to saved page after first frame renders
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToPage(_currentPage, animate: false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _isLoading  = false;
      });
    }
  }

  // ── Text extraction ───────────────────────────────────────────

  Future<String> _extractPageText(int pageNumber) {
    if (_textCache.containsKey(pageNumber)) {
      return Future.value(_textCache[pageNumber]!);
    }
    if (_extractionTasks.containsKey(pageNumber)) {
      return _extractionTasks[pageNumber]!;
    }

    final task = () async {
      if (_document == null) return '';
      try {
        final blocks = await _document!.pages[pageNumber - 1].loadText();
        final buf = StringBuffer();
        String prev = '';
        for (final frag in blocks.fragments) {
          final t = frag.text.trim();
          if (t.isEmpty) continue;
          if (prev.endsWith('.') || prev.endsWith('?') || prev.endsWith('!')) {
            buf.write('\n\n');
          } else if (buf.isNotEmpty) {
            buf.write(' ');
          }
          buf.write(t);
          prev = t;
        }
        final result = buf.toString().trim();
        _textCache[pageNumber] = result;
        return result;
      } catch (_) {
        _textCache[pageNumber] = '';
        return '';
      }
    }();

    _extractionTasks[pageNumber] = task;
    return task;
  }

  // ── Scroll listener → instant page detection ──────────────────

  void _onScroll() {
    if (_totalPages == 0) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // Find the item that is currently occupying the middle of the screen
    // An item's leading edge is < 0.5 and trailing edge is > 0.5
    int? bestPage;

    for (final pos in positions) {
      if (pos.itemLeadingEdge <= 0.5 && pos.itemTrailingEdge > 0.5) {
        bestPage = pos.index + 1; // index is 0-based
        break;
      }
    }

    // Fallback: finding the first visible item if none strictly covers the middle
    if (bestPage == null) {
      double minEdge = double.infinity;
      for (final pos in positions) {
        final dist = (pos.itemLeadingEdge - 0.5).abs();
        if (dist < minEdge) {
          minEdge = dist;
          bestPage = pos.index + 1;
        }
      }
    }

    if (bestPage != null && bestPage != _currentPage) {
      setState(() => _currentPage = bestPage!);
      _saveProgress(bestPage);
    }
  }

  // ── Save progress ─────────────────────────────────────────────

  Future<void> _saveProgress(int page) async {
    if (_totalPages == 0 || page == _lastSavedPage) return;
    _lastSavedPage = page;
    await DBHelper.instance.updateReadingProgress(
      bookId: widget.book.id!,
      currentPage: page,
      totalPages: _totalPages,
    );
  }

  // ── Jump to page ──────────────────────────────────────────────

  void _jumpToPage(int page, {bool animate = true}) {
    if (page < 1 || page > _totalPages) return;

    // Only animate if the distance is short. Animating a long jump in a
    // ScrollablePositionedList forces it to build all intermediate items,
    // which freezes the app.
    final isShortJump = (_currentPage - page).abs() <= 3;

    if (animate && isShortJump) {
      _itemScrollController.scrollTo(
        index: page - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.1, // Gives a little top padding
      );
    } else {
      _itemScrollController.jumpTo(
        index: page - 1,
        alignment: 0.1,
      );
    }

    setState(() => _currentPage = page);
    _saveProgress(page);
  }

  // ── Toggle overlay controls ───────────────────────────────────

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _controlsAnim.forward();
    } else {
      _controlsAnim.reverse();
    }
  }

  // ── Go-to-page dialog ─────────────────────────────────────────

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
          autofocus: false,
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

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      resizeToAvoidBottomInset: false, // Prevents layout lag when opening keyboard
      body: _isLoading
          ? _buildLoader()
          : _loadError != null
              ? _buildError()
              : _buildReader(),
    );
  }

  Widget _buildLoader() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text('Loading book…',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                size: 56, color: AppColors.red),
            const SizedBox(height: 16),
            const Text('Could not open this book',
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
    );
  }

  Widget _buildReader() {
    return Stack(
      children: [
        // ── Continuous scroll content ─────────────────────────────
        GestureDetector(
          onTap: _toggleControls,
          child: ScrollablePositionedList.builder(
            itemCount: _totalPages,
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(top: 56, bottom: 80),
            itemBuilder: (context, index) {
              return _buildPage(index + 1);
            },
          ),
        ),

        // ── Top bar ───────────────────────────────────────────────
        AnimatedSlide(
          offset: _showControls ? Offset.zero : const Offset(0, -1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _buildTopBar(),
        ),

        // ── Bottom bar ────────────────────────────────────────────
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
    );
  }

  // ── Single page widget ────────────────────────────────────────

  Widget _buildPage(int pageNum) {
    return FutureBuilder<String>(
      future: _extractPageText(pageNum),
      builder: (context, snap) {
        // Show a shimmer/loading while text is being extracted
        if (snap.connectionState == ConnectionState.waiting &&
            !_textCache.containsKey(pageNum)) {
          return _buildPageShimmer();
        }
        final text = snap.data ?? _textCache[pageNum] ?? '';
        return text.isNotEmpty
            ? _buildTextPage(pageNum, text)
            : _buildImagePage(pageNum);
      },
    );
  }

  // ── EPUB-style text page ──────────────────────────────────────

  Widget _buildTextPage(int pageNum, String text) {
    return Container(
      color: _bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subtle page divider line at top (not first page)
          if (pageNum > 1) ...[
            Container(
              height: 1,
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
            const SizedBox(height: 16),
          ],

          // Page number pill
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Text(
                'Page $pageNum',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 9,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Book text
          SelectableText(
            text,
            style: TextStyle(
              color: _textColor,
              fontSize: _fontSize,
              height: _lineHeight,
              fontFamily: 'Georgia',
              letterSpacing: 0.25,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Image fallback page ────────────────────────────────────────

  Widget _buildImagePage(int pageNum) {
    if (_document == null) return const SizedBox.shrink();
    return Container(
      color: _bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        children: [
          if (pageNum > 1)
            Container(
              height: 1,
              margin: const EdgeInsets.only(bottom: 16),
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
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Text(
                'Page $pageNum',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 9,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: PdfPageView(
              document: _document!,
              pageNumber: pageNum,
              alignment: Alignment.topCenter,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Shimmer placeholder ───────────────────────────────────────

  Widget _buildPageShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(10, (i) {
          return Container(
            height: 14,
            margin: const EdgeInsets.only(bottom: 12),
            width: i % 5 == 4 ? 180 : double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.92),
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
              // ← Back to book detail (not prev page!)
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
              // Font controls
              IconButton(
                icon: const Icon(Icons.text_decrease_rounded,
                    color: Colors.white70, size: 18),
                tooltip: 'Decrease font',
                onPressed: () => setState(
                    () => _fontSize = (_fontSize - 1).clamp(12.0, 28.0)),
              ),
              IconButton(
                icon: const Icon(Icons.text_increase_rounded,
                    color: Colors.white70, size: 18),
                tooltip: 'Increase font',
                onPressed: () => setState(
                    () => _fontSize = (_fontSize + 1).clamp(12.0, 28.0)),
              ),
              // Jump to page
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

  // ── Bottom bar ────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final progress = _totalPages > 0 ? _currentPage / _totalPages : 0.0;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.92),
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
            // Progress slider
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
                // Dragging = instant visual update + save
                onChanged: (v) {
                  final p = v.round();
                  if (_currentPage != p) {
                    setState(() => _currentPage = p);
                  }
                },
                // Released = actually scroll there + save
                onChangeEnd: (v) => _jumpToPage(v.round(), animate: false),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Prev page
                _navBtn(Icons.chevron_left_rounded,
                    () => _jumpToPage(_currentPage - 1),
                    enabled: _currentPage > 1),
                // Page info
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
                // Next page
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
