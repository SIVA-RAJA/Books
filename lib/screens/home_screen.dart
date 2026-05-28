import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../database/db_helper.dart';
import '../models/book_model.dart';
import '../services/backup_restore_service.dart';
import '../utils/constants.dart';
import '../utils/page_transitions.dart';
import 'edit_book_screen.dart';
import 'book_detail_screen.dart';
import '../widgets/book_card.dart';
import '../widgets/filter_bottom_sheet.dart';
import '../main.dart' show AppColors;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // State
  List<Book> _allBooks = [];
  List<Book> _filteredBooks = [];
  bool _isLoading = true;
  bool _isGridView = true;
  String _selectedGenre = 'All';
  String _selectedSort = 'Last Read';
  String _searchQuery = '';
  int _currentNavIndex = 0;

  // Stats
  int _currentStreak = 0;
  int _longestStreak = 0;
  int _totalReadingSeconds = 0;

  /// Path to the folder the user has selected as their library folder.
  /// Persisted in-memory only — for a real app, store in shared_preferences.
  String? _libraryFolderPath;

  final _backupService = BackupRestoreService();

  // Controllers
  final _searchController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: AppConstants.genres.length,
      vsync: this,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedGenre = AppConstants.genres[_tabController.index];
        });
        _applyFilters();
      }
    });
    _loadBooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ─── Load Books ───────────────────────────────────────

  Future<void> _loadBooks() async {
    setState(() => _isLoading = true);
    try {
      final books = await DBHelper.instance.getSortedBooks(_selectedSort);
      final stats = await DBHelper.instance.getDailyStats();
      
      int currentStreak = 0;
      int longestStreak = 0;
      int totalSeconds = 0;
      DateTime? lastDate;

      for (final s in stats) {
        final dateStr = s['date'] as String;
        final secs = s['secondsRead'] as int;
        totalSeconds += secs;

        final parts = dateStr.split('-');
        final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));

        if (lastDate == null) {
          currentStreak = 1;
        } else {
          final diff = dt.difference(lastDate).inDays;
          if (diff == 1) {
            currentStreak++;
          } else if (diff > 1) {
            if (currentStreak > longestStreak) longestStreak = currentStreak;
            currentStreak = 1;
          }
        }
        lastDate = dt;
      }
      if (currentStreak > longestStreak) longestStreak = currentStreak;

      // Reset streak if we missed yesterday and today
      if (lastDate != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final diff = today.difference(lastDate).inDays;
        if (diff > 1) {
          currentStreak = 0;
        }
      }

      setState(() {
        _allBooks = books;
        _currentStreak = currentStreak;
        _longestStreak = longestStreak;
        _totalReadingSeconds = totalSeconds;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ─── Apply Filters & Search ───────────────────────────

  void _applyFilters() {
    List<Book> result = List.from(_allBooks);

    // Genre filter — book.genre may be comma-separated (e.g. "Fiction, Fantasy")
    if (_selectedGenre != 'All') {
      result = result
          .where((b) => b.genre
              .split(',')
              .map((g) => g.trim())
              .contains(_selectedGenre))
          .toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((b) {
        return b.title.toLowerCase().contains(q) ||
            b.author.toLowerCase().contains(q) ||
            (b.tags?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    setState(() => _filteredBooks = result);
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
    _applyFilters();
  }

  // ─── Navigate to Book Detail ──────────────────────────

  void _goToBookDetail(Book book) async {
    HapticFeedback.lightImpact();
    await Navigator.push(
      context,
      AppRoutes.scaleUp(BookDetailScreen(book: book)),
    );
    _loadBooks(); // Refresh after reading
  }

  // ─── Navigate to Edit Book ────────────────────────────

  Future<void> _goToEditBook(Book book) async {
    HapticFeedback.lightImpact();
    final result = await Navigator.push(
      context,
      AppRoutes.slideUp(EditBookScreen(book: book)),
    );
    if (result == true) _loadBooks();
  }

  // ─── Show Sort/Filter Bottom Sheet ───────────────────

  void _showFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FilterBottomSheet(
        selectedSort: _selectedSort,
        onSortChanged: (sort) {
          setState(() => _selectedSort = sort);
          _loadBooks();
        },
      ),
    );
  }

  // ─── Delete Book ──────────────────────────────────────

  Future<void> _deleteBook(Book book) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Book'),
        content: Text('Are you sure you want to delete "${book.title}" from the library? (The file on your phone is NOT deleted.)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Only delete the DB row — the file lives on external storage, keep it.
      await DBHelper.instance.deleteBook(book.id!);
      // Only remove the generated cover thumbnail (not the original file).
      try {
        if (book.coverImagePath != null) {
          final cover = File(book.coverImagePath!);
          if (await cover.exists()) await cover.delete();
        }
      } catch (_) {}
      _loadBooks();
    }
  }

  // ─── Library Folder ───────────────────────────────────

  /// Let the user pick a folder on external storage, then scan it.
  Future<void> _selectAndScanFolder() async {
    try {
      // file_picker can pick a directory on Android
      final result = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select your PDF library folder',
      );
      if (!mounted || result == null) return;

      setState(() => _isLoading = true);

      _libraryFolderPath = result;
      final scanResult = await _backupService.scanLibraryFolder(result);

      if (!mounted) return;
      setState(() => _isLoading = false);
      _loadBooks();

      _showSnackbar(
        'Scan complete: ${scanResult.added} new book${scanResult.added == 1 ? '' : 's'} added, '
        '${scanResult.updated} file path${scanResult.updated == 1 ? '' : 's'} updated.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('Error scanning folder: $e', isError: true);
      }
    }
  }

  // ─── Backup ───────────────────────────────────────────

  Future<void> _backupDatabase() async {
    try {
      setState(() => _isLoading = true);
      final dest = await _backupService.backup();
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackbar('Backup saved to $dest');
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('Backup failed: $e', isError: true);
      }
    }
  }

  // ─── Restore ──────────────────────────────────────────

  Future<void> _restoreDatabase() async {
    // Check that a backup exists first
    final exists = await _backupService.backupExists;
    if (!exists) {
      _showSnackbar('No backup found at /storage/emulated/0/MyLibrary/backup.db', isError: true);
      return;
    }

    final lastMod = await _backupService.backupLastModified;
    final modStr = lastMod != null
        ? '${lastMod.day}/${lastMod.month}/${lastMod.year} ${lastMod.hour}:${lastMod.minute.toString().padLeft(2, '0')}'
        : 'unknown date';

    if (!mounted) return; // guard after async gap

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface2,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Restore Backup?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'This will replace your current library metadata with the backup from $modStr.\n\nYour PDF files are untouched.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      setState(() => _isLoading = true);
      final processed =
          await _backupService.restore(libraryFolderPath: _libraryFolderPath);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _loadBooks();
      _showSnackbar(
          'Restore complete! $processed book${processed == 1 ? '' : 's'} synced.');
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('Restore failed: $e', isError: true);
      }
    }
  }

  // ─── Snackbar helper ──────────────────────────────────

  void _showSnackbar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ─── Currently Reading Section ────────────────────────

  Widget _buildCurrentlyReading() {
    final reading = _allBooks
        .where((b) => b.readingProgress > 0 && b.readingProgress < 1)
        .toList();
    reading.sort((a, b) => (b.lastRead ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(a.lastRead ?? DateTime.fromMillisecondsSinceEpoch(0)));

    if (reading.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_stories_rounded,
                    size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              const Text(
                'Continue Reading',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${reading.length} in progress',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: reading.length,
            itemBuilder: (context, index) {
              final book = reading[index];
              return GestureDetector(
                onTap: () => _goToBookDetail(book),
                child: Container(
                  width: 260,
                  margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.surface2,
                    border: Border.all(color: AppColors.borderBright),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Cover — safe: errorBuilder shows placeholder, no raw error text
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: book.coverImagePath != null
                            ? Image.file(
                                File(book.coverImagePath!),
                                width: 52,
                                height: 76,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _continueReadingPlaceholder(book),
                              )
                            : _continueReadingPlaceholder(book),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              book.title,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              book.author,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 7),
                            Stack(
                              children: [
                                Container(
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface3,
                                      borderRadius: BorderRadius.circular(2),
                                    )),
                                FractionallySizedBox(
                                  widthFactor: book.readingProgress,
                                  child: Container(
                                    height: 4,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(2),
                                      gradient: const LinearGradient(
                                        colors: [AppColors.primary, AppColors.accent],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${(book.readingProgress * 100).toInt()}% · p.${book.currentPage}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Gradient placeholder for the Continue Reading cards.
  /// Shows an icon, never any error text — so it can never overflow.
  Widget _continueReadingPlaceholder(Book book) {
    const gradients = [
      [Color(0xFF7C6FFF), Color(0xFF3B1F99)],
      [Color(0xFFFF4D6D), Color(0xFF991F3B)],
      [Color(0xFF00D2FF), Color(0xFF004D7A)],
      [Color(0xFFFF9100), Color(0xFF7A3E00)],
      [Color(0xFF00E676), Color(0xFF005C30)],
    ];
    final idx = book.title.length % gradients.length;
    final cols = gradients[idx];
    return Container(
      width: 52,
      height: 76,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cols[0], cols[1]],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.auto_stories_rounded,
          color: Colors.white54, size: 20),
    );
  }

  // ─── Empty State ──────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.library_books_outlined,
                size: 44, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          Text(
            _searchQuery.isNotEmpty ? 'No books found' : 'Your library is empty',
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search term'
                : 'Tap + to add your first book',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ─── Books Grid / List ────────────────────────────────

  Widget _buildBooksSliver() {
    if (_filteredBooks.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    if (_isGridView) {
      return SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.52,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final book = _filteredBooks[index];
              return BookCard(
                book: book,
                isGridView: true,
                onTap: () => _goToBookDetail(book),
                onDelete: () => _deleteBook(book),
                onEdit: () => _goToEditBook(book),
                onFavoriteToggle: () async {
                  await DBHelper.instance
                      .toggleFavorite(book.id!, !book.isFavorite);
                  _loadBooks();
                },
              );
            },
            childCount: _filteredBooks.length,
          ),
        ),
      );
    } else {
      return SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final book = _filteredBooks[index];
              return BookCard(
                book: book,
                isGridView: false,
                onTap: () => _goToBookDetail(book),
                onDelete: () => _deleteBook(book),
                onEdit: () => _goToEditBook(book),
                onFavoriteToggle: () async {
                  await DBHelper.instance
                      .toggleFavorite(book.id!, !book.isFavorite);
                  _loadBooks();
                },
              );
            },
            childCount: _filteredBooks.length,
          ),
        ),
      );
    }
  }

  // ─── Nav Pages ────────────────────────────────────────

  Widget _buildLibraryPage() {
    return CustomScrollView(
      slivers: [
        // Search and Tabs pinned to the top
        SliverAppBar(
          pinned: true,
          floating: false,
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          toolbarHeight: 72,
          title: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search books, authors, tags...',
              leading: const Icon(Icons.search_rounded, color: AppColors.textMuted),
              trailing: [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  ),
              ],
              onChanged: _onSearchChanged,
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: AppConstants.genres.map((g) => Tab(text: g)).toList(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            dividerColor: Colors.transparent,
          ),
        ),

        // Scrollable content below the pinned app bar
        SliverToBoxAdapter(
          child: Column(
            children: [

              // Currently Reading
              if (_searchQuery.isEmpty && _selectedGenre == 'All')
                _buildCurrentlyReading(),

              // Sort & View Toggle Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        '${_filteredBooks.length} books',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showFilterSheet,
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: Text(_selectedSort, style: const TextStyle(fontSize: 12)),
                    ),
                    IconButton(
                      icon: Icon(
                        _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _isGridView = !_isGridView),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Books
        if (_isLoading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else
          _buildBooksSliver(),
      ],
    );
  }

  Widget _buildFavoritesPage() {
    final favorites = _allBooks.where((b) => b.isFavorite).toList();
    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.favorite_outline_rounded,
                  size: 44, color: AppColors.red),
            ),
            const SizedBox(height: 20),
            const Text(
              'No favorites yet',
              style: TextStyle(
                fontSize: 18,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Long-press a book card to add it',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final book = favorites[index];
        return BookCard(
          book: book,
          isGridView: true,
          onTap: () => _goToBookDetail(book),
          onDelete: () => _deleteBook(book),
          onEdit: () => _goToEditBook(book),
          onFavoriteToggle: () async {
            await DBHelper.instance
                .toggleFavorite(book.id!, !book.isFavorite);
            _loadBooks();
          },
        );
      },
    );
  }

  Widget _buildStatsPage() {
    final total = _allBooks.length;
    final completed =
        _allBooks.where((b) => b.isCompleted).length;
    final reading =
        _allBooks.where((b) => b.readingProgress > 0 && !b.isCompleted).length;
    final notStarted =
        _allBooks.where((b) => b.readingProgress == 0).length;

    // Avg progress
    final avgProgress = total > 0
        ? _allBooks.fold(0.0, (sum, b) => sum + b.readingProgress) / total
        : 0.0;

    // Total pages read
    final totalPagesRead =
        _allBooks.fold<int>(0, (sum, b) => sum + b.currentPage);

    // Genre counts (handle comma-separated genres)
    final genreCounts = <String, int>{};
    for (final book in _allBooks) {
      for (final g in book.genre.split(',').map((e) => e.trim())) {
        if (g.isNotEmpty) {
          genreCounts[g] = (genreCounts[g] ?? 0) + 1;
        }
      }
    }
    final sortedGenres = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topGenres = sortedGenres.take(5).toList();

    // Recently read books (has lastRead)
    final recentlyRead = _allBooks
        .where((b) => b.lastRead != null)
        .toList()
      ..sort((a, b) => b.lastRead!.compareTo(a.lastRead!));
    final last5 = recentlyRead.take(5).toList();

    // File type breakdown
    final typeCounts = <String, int>{};
    for (final book in _allBooks) {
      typeCounts[book.fileType.toUpperCase()] =
          (typeCounts[book.fileType.toUpperCase()] ?? 0) + 1;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.03);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reading Stats',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '$total books in your library',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Overall progress badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(avgProgress * 100).toInt()}% avg',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Ring Chart + Status ──
          _buildSection(
            cardColor: cardColor,
            borderColor: borderColor,
            child: Row(
              children: [
                // Donut ring
                SizedBox(
                  width: 120,
                  height: 120,
                  child: total == 0
                      ? const Center(
                          child: Icon(
                            Icons.library_books_outlined,
                            size: 48,
                            color: AppColors.textMuted,
                          ),
                        )
                      : CustomPaint(
                          painter: _DonutChartPainter(
                            completed: completed,
                            reading: reading,
                            notStarted: notStarted,
                            total: total,
                            completedColor: AppColors.green,
                            readingColor: AppColors.primary,
                            notStartedColor: AppColors.surface3,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$total',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  'books',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 20),
                // Legend
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _legendItem(
                        color: AppColors.green,
                        label: 'Completed',
                        value: completed,
                        total: total,
                      ),
                      const SizedBox(height: 10),
                      _legendItem(
                        color: AppColors.primary,
                        label: 'Reading',
                        value: reading,
                        total: total,
                      ),
                      const SizedBox(height: 10),
                      _legendItem(
                        color: AppColors.surface3,
                        label: 'Not Started',
                        value: notStarted,
                        total: total,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Quick Stats Row ──
          Row(
            children: [
              _quickStatCard(
                icon: Icons.menu_book_rounded,
                label: 'Pages Read',
                value: totalPagesRead > 999
                    ? '${(totalPagesRead / 1000).toStringAsFixed(1)}k'
                    : totalPagesRead.toString(),
                color: AppColors.primary,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
              const SizedBox(width: 10),
              _quickStatCard(
                icon: Icons.check_circle_rounded,
                label: 'Completed',
                value: '$completed',
                color: AppColors.green,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
              const SizedBox(width: 10),
              _quickStatCard(
                icon: Icons.auto_stories_rounded,
                label: 'In Progress',
                value: '$reading',
                color: AppColors.orange,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Streaks & Time Row ──
          Row(
            children: [
              _quickStatCard(
                icon: Icons.local_fire_department_rounded,
                label: 'Current Streak',
                value: '$_currentStreak d',
                color: Colors.deepOrange,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
              const SizedBox(width: 10),
              _quickStatCard(
                icon: Icons.emoji_events_rounded,
                label: 'Best Streak',
                value: '$_longestStreak d',
                color: Colors.amber,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
              const SizedBox(width: 10),
              _quickStatCard(
                icon: Icons.timer_rounded,
                label: 'Time Spent',
                value: _totalReadingSeconds >= 3600
                    ? '${(_totalReadingSeconds ~/ 3600)}h ${(_totalReadingSeconds % 3600) ~/ 60}m'
                    : _totalReadingSeconds > 60
                        ? '${_totalReadingSeconds ~/ 60}m'
                        : _totalReadingSeconds > 0
                            ? '< 1m'
                            : '0m',
                color: Colors.blueAccent,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Top Genres ──
          if (topGenres.isNotEmpty) ...[
            _buildSection(
              cardColor: cardColor,
              borderColor: borderColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    icon: Icons.local_offer_rounded,
                    title: 'Top Genres',
                    color: const Color(0xFF9C27B0),
                  ),
                  const SizedBox(height: 16),
                  ...topGenres.asMap().entries.map((entry) {
                    final i = entry.key;
                    final e = entry.value;
                    final pct = total > 0 ? e.value / total : 0.0;
                    final colors = [
                      const Color(0xFF6C63FF),
                      const Color(0xFF4CAF50),
                      const Color(0xFFFF9800),
                      const Color(0xFFE91E63),
                      const Color(0xFF00BCD4),
                    ];
                    final barColor = colors[i % colors.length];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: barColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    e.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${e.value} · ${(pct * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: pct),
                              duration: Duration(
                                  milliseconds: 600 + i * 100),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, _) =>
                                  LinearProgressIndicator(
                                value: value,
                                minHeight: 8,
                                backgroundColor: barColor
                                    .withValues(alpha: 0.15),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(
                                        barColor),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],


        // ── Recently Read ──
        if (last5.isNotEmpty) ...[
          _buildSection(
            cardColor: cardColor,
            borderColor: borderColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(
                  icon: Icons.history_rounded,
                  title: 'Recently Read',
                  color: AppColors.orange,
                ),
                const SizedBox(height: 12),
                ...last5.map((book) {
                  final ago = _timeAgo(book.lastRead!);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        // Mini cover
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primary
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.menu_book_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                ago,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Progress pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _progressColor(book.readingProgress)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${(book.readingProgress * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _progressColor(
                                  book.readingProgress),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],

        // ── Empty state ──
        if (total == 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 72,
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No stats yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add some books to see your reading stats',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      ),
    );
  }

  // ─── Stats helpers ────────────────────────────────────

  Widget _buildSection({
    required Widget child,
    required Color cardColor,
    required Color borderColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _legendItem({
    required Color color,
    required String label,
    required int value,
    required int total,
  }) {
    final pct = total > 0 ? (value / total * 100).toInt() : 0;
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Text(
          '$value ($pct%)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _quickStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color cardColor,
    required Color borderColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Color _progressColor(double progress) {
    if (progress >= 1.0) return const Color(0xFF4CAF50);
    if (progress > 0) return const Color(0xFF6C63FF);
    return Colors.grey;
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
  // ─── Build ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildLibraryPage(),
      _buildFavoritesPage(),
      _buildStatsPage(),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Row(
          children: [
            // Logo image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/logo.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ).createShader(bounds),
              child: const Text(
                'Books',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        // ── Library management actions ──────────────────────
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textSecondary),
            tooltip: 'Library options',
            onSelected: (value) {
              switch (value) {
                case 'scan_folder':
                  _selectAndScanFolder();
                  break;
                case 'backup':
                  _backupDatabase();
                  break;
                case 'restore':
                  _restoreDatabase();
                  break;
              }
            },
            itemBuilder: (_) => [
              // ── Scan / Add Folder ──
              PopupMenuItem<String>(
                value: 'scan_folder',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.folder_open_rounded,
                          color: AppColors.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Add Library Folder',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        Text(
                          _libraryFolderPath != null
                              ? _libraryFolderPath!.split('/').last
                              : 'Pick a folder to scan',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              // ── Backup ──
              const PopupMenuItem<String>(
                value: 'backup',
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x1A00E676), // AppColors.green dim
                          borderRadius:
                              BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Icon(Icons.cloud_upload_rounded,
                            color: AppColors.green, size: 18),
                      ),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Backup',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        Text('Save metadata to backup.db',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              // ── Restore ──
              const PopupMenuItem<String>(
                value: 'restore',
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x1AFF9100), // AppColors.orange dim
                          borderRadius:
                              BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Icon(Icons.cloud_download_rounded,
                            color: AppColors.orange, size: 18),
                      ),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Restore',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        Text('Reload from backup.db',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: pages[_currentNavIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentNavIndex,
        onDestinationSelected: (index) {
          setState(() => _currentNavIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Favorites',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}


// ── Donut chart painter ──────────────────────────────────────────────────────

class _DonutChartPainter extends CustomPainter {
  final int completed;
  final int reading;
  final int notStarted;
  final int total;
  final Color completedColor;
  final Color readingColor;
  final Color notStartedColor;

  _DonutChartPainter({
    required this.completed,
    required this.reading,
    required this.notStarted,
    required this.total,
    required this.completedColor,
    required this.readingColor,
    required this.notStartedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 16.0;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    final segments = [
      (completed / total, completedColor),
      (reading / total, readingColor),
      (notStarted / total, notStartedColor),
    ];

    const startAngle = -3.14159 / 2; // start at top
    const gap = 0.05; // radians gap between segments
    double currentAngle = startAngle;

    for (final seg in segments) {
      final fraction = seg.$1;
      final color = seg.$2;
      if (fraction <= 0) continue;

      final sweepAngle = fraction * 2 * 3.14159 - gap;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, currentAngle, sweepAngle, false, paint);
      currentAngle += sweepAngle + gap;
    }
  }

  @override
  bool shouldRepaint(_DonutChartPainter old) =>
      old.completed != completed ||
      old.reading != reading ||
      old.notStarted != notStarted;
}

