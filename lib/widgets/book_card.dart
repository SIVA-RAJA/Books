import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../models/book_model.dart';
import '../main.dart' show AppColors;

// ─────────────────────────────────────────────────────────────────────────────
//  BookCard — grid + list variants
//  • Spring press-scale micro-animation on every tap
//  • Haptic feedback on tap, long-press, and favorite toggle
//  • Animated favorite button (color transition)
//  • Completed ✓ badge overlay on cover
//  • Mini cover thumbnail inside the options bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class BookCard extends StatefulWidget {
  final Book book;
  final bool isGridView;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onEdit;
  final VoidCallback? onReread;  // only provided for completed books

  const BookCard({
    super.key,
    required this.book,
    required this.isGridView,
    required this.onTap,
    required this.onDelete,
    required this.onFavoriteToggle,
    required this.onEdit,
    this.onReread,
  });

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard>
    with SingleTickerProviderStateMixin {
  // ── Press animation ───────────────────────────────────────────
  late AnimationController _pressCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 220),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.955).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _pressCtrl.forward();
  void _onTapUp(TapUpDetails _) {
    _pressCtrl.reverse();
    HapticFeedback.selectionClick();
    widget.onTap();
  }
  void _onTapCancel() => _pressCtrl.reverse();

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showOptionsMenu(context);
        },
        child: widget.isGridView
            ? _buildGridCard(context)
            : _buildListCard(context),
      ),
    );
  }

  // ─── Grid Card ────────────────────────────────────────────────────────────

  Widget _buildGridCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover ──
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCover(
                  width: double.infinity,
                  height: double.infinity,
                  context: context,
                ),

                // Top gradient for badges
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Favorite button — no background, just the heart
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onFavoriteToggle();
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        widget.book.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_outline_rounded,
                        key: ValueKey(widget.book.isFavorite),
                        color: widget.book.isFavorite
                            ? const Color(0xFFB71C1C) // Dark red
                            : Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ),

                // Bottom progress bar
                if (widget.book.readingProgress > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Stack(
                      children: [
                        Container(height: 4, color: Colors.black38),
                        FractionallySizedBox(
                          widthFactor:
                              widget.book.readingProgress.clamp(0.0, 1.0),
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: widget.book.isCompleted
                                    ? [AppColors.green, AppColors.green]
                                    : [AppColors.primary, AppColors.accent],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Completed ✓ badge
                if (widget.book.isCompleted)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 10),
                    ),
                  ),
              ],
            ),
          ),

          // ── Info ──
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.book.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.book.author,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(child: _buildGenreChip()),
                      if (widget.book.isCompleted && widget.book.readingProgress >= 1)
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.green, size: 14)
                      else if (widget.book.readingProgress > 0)
                        Row(
                          children: [
                            if (widget.book.isCompleted)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.check_circle_rounded, color: AppColors.green, size: 12),
                              ),
                            Text(
                              '${(widget.book.readingProgress * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── List Card ────────────────────────────────────────────────────────────

  Widget _buildListCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cover
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _buildCover(width: 58, height: 80, context: context),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.book.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Animated favorite icon
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onFavoriteToggle();
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Icon(
                          widget.book.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_outline_rounded,
                          key: ValueKey(widget.book.isFavorite),
                          color: widget.book.isFavorite
                              ? const Color(0xFFB71C1C) // Dark red
                              : AppColors.textMuted,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  widget.book.author,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 7),
                Row(children: [
                  _buildGenreChip(),
                ]),
                const SizedBox(height: 7),

                // Progress bar
                if (widget.book.readingProgress > 0) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(children: [
                            Container(
                                height: 4, color: AppColors.surface3),
                            FractionallySizedBox(
                              widthFactor: widget.book.readingProgress
                                  .clamp(0.0, 1.0),
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: widget.book.isCompleted
                                        ? [AppColors.green, AppColors.green]
                                        : [
                                            AppColors.primary,
                                            AppColors.accent
                                          ],
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.book.isCompleted && widget.book.readingProgress >= 1
                            ? '✓ Done'
                            : (widget.book.isCompleted ? '✓ ${(widget.book.readingProgress * 100).toInt()}%' : '${(widget.book.readingProgress * 100).toInt()}%'),
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.book.isCompleted && widget.book.readingProgress >= 1
                              ? AppColors.green
                              : AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ] else
                  const Text(
                    'Not started',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),

          // More button
          IconButton(
            icon: const Icon(Icons.more_vert_rounded,
                size: 20, color: AppColors.textMuted),
            onPressed: () {
              HapticFeedback.lightImpact();
              _showOptionsMenu(context);
            },
          ),
        ],
      ),
    );
  }

  // ─── Shared widgets ───────────────────────────────────────────────────────

  Widget _buildCover({
    required double width,
    required double height,
    required BuildContext context,
  }) {
    if (widget.book.coverImagePath != null) {
      return Image.file(
        File(widget.book.coverImagePath!),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(width, height),
      );
    }
    return _placeholder(width, height);
  }

  Widget _placeholder(double width, double height) {
    const gradients = [
      [Color(0xFF7C6FFF), Color(0xFF3B1F99)],
      [Color(0xFFFF4D6D), Color(0xFF991F3B)],
      [Color(0xFF00D2FF), Color(0xFF004D7A)],
      [Color(0xFFFF9100), Color(0xFF7A3E00)],
      [Color(0xFF00E676), Color(0xFF005C30)],
    ];
    final idx = widget.book.title.length % gradients.length;
    final cols = gradients[idx];

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cols[0], cols[1]],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_stories_rounded,
              color: Colors.white38, size: 28),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              widget.book.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 3,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenreChip() {
    final first = widget.book.genre.split(',').first.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        first,
        style: const TextStyle(
          fontSize: 9,
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }


  // ─── Options Bottom Sheet ─────────────────────────────────────────────────

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderBright,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Book header — cover + title + progress
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: widget.book.coverImagePath != null
                        ? Image.file(
                            File(widget.book.coverImagePath!),
                            width: 44,
                            height: 58,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 44,
                            height: 58,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primaryDim
                                ],
                              ),
                            ),
                            child: const Icon(Icons.auto_stories_rounded,
                                color: Colors.white38, size: 22),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.book.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.book.author,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                        if (widget.book.readingProgress > 0) ...[
                          const SizedBox(height: 5),
                          Text(
                            '${(widget.book.readingProgress * 100).toInt()}% read · p.${widget.book.currentPage}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.border),

              _sheetTile(
                icon: Icons.menu_book_rounded,
                label: 'Open Book',
                iconColor: AppColors.primary,
                onTap: () {
                  Navigator.pop(context);
                  widget.onTap();
                },
              ),
              _sheetTile(
                icon: Icons.edit_rounded,
                label: 'Edit Book',
                iconColor: AppColors.accent,
                onTap: () {
                  Navigator.pop(context);
                  widget.onEdit();
                },
              ),
              _sheetTile(
                icon: widget.book.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_outline_rounded,
                label: widget.book.isFavorite
                    ? 'Remove from Favorites'
                    : 'Add to Favorites',
                iconColor: widget.book.isFavorite
                    ? AppColors.red
                    : AppColors.textSecondary,
                onTap: () {
                  Navigator.pop(context);
                  widget.onFavoriteToggle();
                },
              ),
              _sheetTile(
                icon: Icons.delete_outline_rounded,
                label: 'Remove from Library',
                iconColor: AppColors.red,
                labelColor: AppColors.red,
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete();
                },
              ),
              // Re-read option — only shown for completed books
              if (widget.onReread != null)
                _sheetTile(
                  icon: Icons.replay_rounded,
                  label: 'Re-read',
                  iconColor: const Color(0xFF00BCD4),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onReread!();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required Color iconColor,
    Color? labelColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: labelColor ?? AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
