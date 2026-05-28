import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/book_model.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  // ─── Database getter ─────────────────────────────────

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ebook_library.db');
    return _database!;
  }

  // Returns the on-disk path to the internal SQLite file
  Future<String> getDatabaseFilePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'ebook_library.db');
  }

  // ─── Init & schema ───────────────────────────────────

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 4,          // bumped from 3 → 4 to add daily_stats
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // Create full schema from scratch (fresh install)
  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fileName TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        genre TEXT NOT NULL,
        filePath TEXT NOT NULL,
        fileType TEXT NOT NULL,
        coverImagePath TEXT,
        totalPages INTEGER DEFAULT 0,
        currentPage INTEGER DEFAULT 0,
        readingProgress REAL DEFAULT 0.0,
        dateAdded TEXT NOT NULL,
        lastRead TEXT,
        isFavorite INTEGER DEFAULT 0,
        description TEXT,
        tags TEXT,
        isCompleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_stats (
        date TEXT PRIMARY KEY,
        secondsRead INTEGER DEFAULT 0
      )
    ''');
  }

  // Migrate older DB versions forward
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: add isCompleted
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE books ADD COLUMN isCompleted INTEGER DEFAULT 0');
      await db.execute(
          'UPDATE books SET isCompleted = 1 WHERE readingProgress >= 1');
    }
    // v2 → v3: add fileName (unique key used for backup/restore matching)
    if (oldVersion < 3) {
      // Add column — may be empty for existing rows; we'll populate from filePath
      await db.execute(
          'ALTER TABLE books ADD COLUMN fileName TEXT NOT NULL DEFAULT ""');
      // Backfill fileName from the stored filePath basename
      final rows = await db.query('books', columns: ['id', 'filePath']);
      for (final row in rows) {
        final fp = row['filePath'] as String? ?? '';
        final fn = fp.isNotEmpty ? basename(fp) : '';
        await db.update(
          'books',
          {'fileName': fn},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
    // v3 → v4: add daily_stats table for streaks and time spent reading
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE daily_stats (
          date TEXT PRIMARY KEY,
          secondsRead INTEGER DEFAULT 0
        )
      ''');
    }
  }

  // ─── Stats & Streaks ───────────────────────────────────

  /// Add reading time (in seconds) for today
  Future<void> addReadingTime(int seconds) async {
    final db = await database;
    final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
    
    final result = await db.query(
      'daily_stats',
      where: 'date = ?',
      whereArgs: [today],
    );

    if (result.isEmpty) {
      await db.insert('daily_stats', {'date': today, 'secondsRead': seconds});
    } else {
      final currentSeconds = result.first['secondsRead'] as int? ?? 0;
      await db.update(
        'daily_stats',
        {'secondsRead': currentSeconds + seconds},
        where: 'date = ?',
        whereArgs: [today],
      );
    }
  }

  /// Get all daily reading stats ordered by date
  Future<List<Map<String, dynamic>>> getDailyStats() async {
    final db = await database;
    return await db.query('daily_stats', orderBy: 'date ASC');
  }

  // ─── Force close (needed before restore) ─────────────

  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null; // force re-open on next access
    }
  }

  // ─── CREATE ──────────────────────────────────────────

  Future<int> insertBook(Book book) async {
    final db = await database;
    return await db.insert(
      'books',
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─── READ ────────────────────────────────────────────

  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final result = await db.query('books', orderBy: 'dateAdded DESC');
    return result.map((m) => Book.fromMap(m)).toList();
  }

  Future<Book?> getBookById(int id) async {
    final db = await database;
    final result =
        await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (result.isNotEmpty) return Book.fromMap(result.first);
    return null;
  }

  /// Look up a book by its filename — used when matching restored metadata
  /// to files found in the library folder.
  Future<Book?> getBookByFileName(String fileName) async {
    final db = await database;
    final result = await db.query(
      'books',
      where: 'fileName = ?',
      whereArgs: [fileName],
    );
    if (result.isNotEmpty) return Book.fromMap(result.first);
    return null;
  }

  Future<List<Book>> searchBooks(String query) async {
    final db = await database;
    final result = await db.query(
      'books',
      where: 'title LIKE ? OR author LIKE ? OR tags LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
    );
    return result.map((m) => Book.fromMap(m)).toList();
  }

  Future<List<Book>> getBooksByGenre(String genre) async {
    final db = await database;
    final result = await db.query(
      'books',
      where: 'genre = ?',
      whereArgs: [genre],
    );
    return result.map((m) => Book.fromMap(m)).toList();
  }

  Future<List<Book>> getFavoriteBooks() async {
    final db = await database;
    final result =
        await db.query('books', where: 'isFavorite = ?', whereArgs: [1]);
    return result.map((m) => Book.fromMap(m)).toList();
  }

  Future<List<Book>> getCurrentlyReading() async {
    final db = await database;
    final result = await db.query(
      'books',
      where: 'readingProgress > 0 AND readingProgress < 1',
      orderBy: 'lastRead DESC',
    );
    return result.map((m) => Book.fromMap(m)).toList();
  }

  Future<List<Book>> getSortedBooks(String sortOption) async {
    final db = await database;
    String orderBy;
    switch (sortOption) {
      case 'Title A-Z':
        orderBy = 'title ASC';
        break;
      case 'Title Z-A':
        orderBy = 'title DESC';
        break;
      case 'Author A-Z':
        orderBy = 'author ASC';
        break;
      case 'Last Read':
        orderBy = 'lastRead DESC';
        break;
      case 'Recently Added':
      default:
        orderBy = 'dateAdded DESC';
        break;
    }
    final result = await db.query('books', orderBy: orderBy);
    return result.map((m) => Book.fromMap(m)).toList();
  }

  // ─── UPDATE ──────────────────────────────────────────

  Future<int> updateBook(Book book) async {
    final db = await database;
    return await db.update(
      'books',
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  /// Update only the filePath for a given fileName.
  /// Called after a restore when files may have moved.
  Future<void> updateFilePath(String fileName, String newFilePath) async {
    final db = await database;
    await db.update(
      'books',
      {'filePath': newFilePath},
      where: 'fileName = ?',
      whereArgs: [fileName],
    );
  }

  Future<void> updateReadingProgress({
    required int bookId,
    required int currentPage,
    required int totalPages,
  }) async {
    final db = await database;
    final progress = totalPages > 0 ? currentPage / totalPages : 0.0;

    final bookData = await db.query(
      'books',
      columns: ['isCompleted'],
      where: 'id = ?',
      whereArgs: [bookId],
    );
    int isCompleted = 0;
    if (bookData.isNotEmpty) {
      isCompleted = (bookData.first['isCompleted'] as int?) ?? 0;
    }
    if (progress >= 1.0) isCompleted = 1;

    await db.update(
      'books',
      {
        'currentPage': currentPage,
        'totalPages': totalPages,
        'readingProgress': progress,
        'lastRead': DateTime.now().toIso8601String(),
        'isCompleted': isCompleted,
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> toggleFavorite(int bookId, bool isFavorite) async {
    final db = await database;
    await db.update(
      'books',
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  // ─── DELETE ──────────────────────────────────────────

  Future<int> deleteBook(int id) async {
    final db = await database;
    return await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  // ─── BACKUP ──────────────────────────────────────────

  /// Copies the live internal DB file to [destinationPath].
  /// The DB is closed first so sqflite flushes its WAL.
  Future<void> backupTo(String destinationPath) async {
    // Close so all pending writes are committed and WAL is merged
    await closeDatabase();
    final internalPath = await getDatabaseFilePath();
    final srcFile = File(internalPath);
    if (!await srcFile.exists()) {
      throw Exception('Internal database file not found at $internalPath');
    }
    // Ensure destination directory exists
    final destDir = Directory(destinationPath).parent;
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    await srcFile.copy(destinationPath);
  }

  // ─── RESTORE ─────────────────────────────────────────

  /// Replaces the internal DB with [sourcePath] (the backup file).
  /// Closes current DB first, then overwrites, then lets [database] getter
  /// re-open it fresh on next call.
  Future<void> restoreFrom(String sourcePath) async {
    final srcFile = File(sourcePath);
    if (!await srcFile.exists()) {
      throw Exception('Backup file not found at $sourcePath');
    }
    // Close the live DB so we can safely overwrite it
    await closeDatabase();
    final internalPath = await getDatabaseFilePath();
    await srcFile.copy(internalPath);
    // _database is null now — next call to [database] getter will re-open
  }

  // ─── CLOSE ───────────────────────────────────────────

  Future close() async {
    final db = await database;
    db.close();
  }
}
