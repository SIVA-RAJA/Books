import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui';
import '../models/book_model.dart';
import '../database/db_helper.dart';
import 'pdf_reader_screen.dart';
import 'epub_reader_screen.dart';
import '../main.dart' show AppColors;

class BookDetailScreen extends StatefulWidget {
  final Book book;

  const BookDetailScreen({super.key, required this.book});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late Book _book;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _refreshBook();
  }

  Future<void> _refreshBook() async {
    if (!mounted) return;
    final updated = await DBHelper.instance.getBookById(_book.id!);
    if (updated != null && mounted) {
      setState(() => _book = updated);
    }
  }

  void _openReader() async {
    final type = _book.fileType.toLowerCase();
    if (type == 'pdf') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PdfReaderScreen(book: _book)),
      );
    } else if (type == 'epub') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EpubReaderScreen(book: _book)),
      );
    } else {
      _showSnackbar('Opening with external app...');
      return;
    }
    if (mounted) _refreshBook();
  }

  Future<void> _toggleFavorite() async {
    await DBHelper.instance.toggleFavorite(_book.id!, !_book.isFavorite);
    _refreshBook();
  }

  Future<void> _deleteBook() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Book',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete "${_book.title}" permanently?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await DBHelper.instance.deleteBook(_book.id!);

    try {
      final file = File(_book.filePath);
      if (await file.exists()) await file.delete();
      final coverPath = _book.coverImagePath;
      if (coverPath != null) {
        final cover = File(coverPath);
        if (await cover.exists()) await cover.delete();
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.pop(context);
  }

  void _showSnackbar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Never';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _getProgressText() {
    if (_book.isCompleted && _book.readingProgress >= 1) return 'Completed ✓';
    if (_book.isCompleted) return 'Completed ✓  •  ${(_book.readingProgress * 100).toInt()}% Reread';
    if (_book.readingProgress == 0) return 'Not Started';
    return '${(_book.readingProgress * 100).toInt()}%  •  Page ${_book.currentPage} of ${_book.totalPages}';
  }

  Color _getProgressColor() {
    if (_book.isCompleted) return AppColors.green;
    if (_book.readingProgress > 0) return AppColors.primary;
    return AppColors.textMuted;
  }

  String _getETAText() {
    if (_book.isCompleted) return 'Finished';
    if (_book.totalPages <= 0) return 'Unknown';
    
    final remainingPages = _book.totalPages - _book.currentPage;
    if (remainingPages <= 0) return 'Finished';
    
    // Average reading speed: ~1.5 minutes per page
    final remainingMinutes = (remainingPages * 1.5).round();
    
    if (remainingMinutes < 60) return '$remainingMinutes m';
    final hours = remainingMinutes ~/ 60;
    final mins = remainingMinutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          // ── Hero AppBar ──
          SliverAppBar(
            expandedHeight: size.height * 0.4,
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.surface,
            foregroundColor: Colors.white,
            actions: [
              // Favorite
              GestureDetector(
                onTap: _toggleFavorite,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _book.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_outline_rounded,
                    color: _book.isFavorite ? AppColors.red : Colors.white,
                    size: 20,
                  ),
                ),
              ),
              // More
              PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_vert_rounded,
                      color: Colors.white, size: 20),
                ),
                onSelected: (value) {
                  if (value == 'delete') _deleteBook();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            color: AppColors.red, size: 18),
                        SizedBox(width: 10),
                        Text('Delete',
                            style: TextStyle(color: AppColors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover image or gradient
                  _book.coverImagePath != null
                      ? Image.file(
                          File(_book.coverImagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildGradientBg(),
                        )
                      : _buildGradientBg(),

                  // Dark gradient overlay bottom
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0xCC000000),
                        ],
                        stops: [0.4, 1.0],
                      ),
                    ),
                  ),

                  // Title + Author at bottom
                  Positioned(
                    bottom: 20,
                    left: 18,
                    right: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _book.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'by ${_book.author}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Content ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Genre + file type chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        label: _book.genre.split(',').first.trim(),
                        icon: Icons.local_offer_rounded,
                        color: AppColors.primary,
                      ),
                      _buildChip(
                        label: _book.fileType.toUpperCase(),
                        icon: Icons.insert_drive_file_rounded,
                        color: AppColors.orange,
                      ),
                      if (_book.isFavorite)
                        _buildChip(
                          label: 'Favorite',
                          icon: Icons.favorite_rounded,
                          color: AppColors.red,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Reading Progress Card ──
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _getProgressColor()
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.auto_stories_rounded,
                                  color: _getProgressColor(), size: 16),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Reading Progress',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _getProgressText(),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: _getProgressColor(),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(children: [
                            Container(
                                height: 8, color: AppColors.surface3),
                            FractionallySizedBox(
                              widthFactor:
                                  _book.readingProgress.clamp(0.0, 1.0),
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: _book.isCompleted
                                        ? [AppColors.green, AppColors.green]
                                        : [AppColors.primary, AppColors.accent],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Book Info Card ──
                  _card(
                    child: Column(
                      children: [
                        _infoRow(Icons.calendar_today_rounded, 'Added',
                            _formatDate(_book.dateAdded)),
                        const Divider(color: AppColors.border, height: 20),
                        _infoRow(Icons.history_rounded, 'Last Read',
                            _formatDate(_book.lastRead)),
                        if (_book.totalPages > 0) ...[
                          const Divider(color: AppColors.border, height: 20),
                          _infoRow(Icons.auto_stories_rounded, 'Pages',
                              '${_book.totalPages}'),
                          const Divider(color: AppColors.border, height: 20),
                          _infoRow(Icons.hourglass_bottom_rounded, 'Time to Finish',
                              _getETAText()),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Description ──
                  if (_book.description != null &&
                      _book.description!.isNotEmpty) ...[
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.notes_rounded,
                                  color: AppColors.accent, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Description',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _book.description!,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              height: 1.6,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // ── Tags ──
                  if (_book.tags != null && _book.tags!.isNotEmpty) ...[
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.label_rounded,
                                  color: AppColors.primary, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Tags',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _book.tags!
                                .split(',')
                                .map((t) => t.trim())
                                .where((t) => t.isNotEmpty)
                                .map(
                                  (tag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                          color: AppColors.accent
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      '#$tag',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Read Button ──
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.75),
              border: const Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            child: SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _openReader,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.menu_book_rounded),
            label: Text(
              _book.readingProgress > 0 && _book.readingProgress < 1
                  ? 'Continue Reading'
                  : _book.isCompleted
                      ? 'Read Again'
                      : 'Start Reading',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildGradientBg() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.surface3, AppColors.primaryDim],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              Icon(icon, size: 15, color: AppColors.textMuted),
        ),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ],
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
