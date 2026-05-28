import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/book_model.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  // Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ebook_library.db');
    return _database!;
  }

  // Initialize DB
  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // Create table
  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
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
  }

  // Upgrade DB
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE books ADD COLUMN isCompleted INTEGER DEFAULT 0');
      await db.execute('UPDATE books SET isCompleted = 1 WHERE readingProgress >= 1');
    }
  }

  // ─── CREATE ───────────────────────────────────────────

  Future<int> insertBook(Book book) async {
    final db = await database;
    return await db.insert(
      'books',
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─── READ ─────────────────────────────────────────────

  // Get all books
  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final result = await db.query(
      'books',
      orderBy: 'dateAdded DESC',
    );
    return result.map((map) => Book.fromMap(map)).toList();
  }

  // Get single book by id
  Future<Book?> getBookById(int id) async {
    final db = await database;
    final result = await db.query(
      'books',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isNotEmpty) {
      return Book.fromMap(result.first);
    }
    return null;
  }

  // Search books by title or author
  Future<List<Book>> searchBooks(String query) async {
    final db = await database;
    final result = await db.query(
      'books',
      where: 'title LIKE ? OR author LIKE ? OR tags LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
    );
    return result.map((map) => Book.fromMap(map)).toList();
  }

  // Get books by genre
  Future<List<Book>> getBooksByGenre(String genre) async {
    final db = await database;
    final result = await db.query(
      'books',
      where: 'genre = ?',
      whereArgs: [genre],
    );
    return result.map((map) => Book.fromMap(map)).toList();
  }

  // Get favorite books
  Future<List<Book>> getFavoriteBooks() async {
    final db = await database;
    final result = await db.query(
      'books',
      where: 'isFavorite = ?',
      whereArgs: [1],
    );
    return result.map((map) => Book.fromMap(map)).toList();
  }

  // Get currently reading books (progress > 0 and < 1)
  Future<List<Book>> getCurrentlyReading() async {
    final db = await database;
    final result = await db.query(
      'books',
      where: 'readingProgress > 0 AND readingProgress < 1',
      orderBy: 'lastRead DESC',
    );
    return result.map((map) => Book.fromMap(map)).toList();
  }

  // Sort books
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
    return result.map((map) => Book.fromMap(map)).toList();
  }

  // ─── UPDATE ───────────────────────────────────────────

  // Update book info
  Future<int> updateBook(Book book) async {
    final db = await database;
    return await db.update(
      'books',
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  // Update reading progress
  Future<void> updateReadingProgress({
    required int bookId,
    required int currentPage,
    required int totalPages,
  }) async {
    final db = await database;
    final progress = totalPages > 0 ? currentPage / totalPages : 0.0;

    final bookData = await db.query('books', columns: ['isCompleted'], where: 'id = ?', whereArgs: [bookId]);
    int isCompleted = 0;
    if (bookData.isNotEmpty) {
      isCompleted = (bookData.first['isCompleted'] as int?) ?? 0;
    }
    if (progress >= 1.0) {
      isCompleted = 1;
    }

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

  // Toggle favorite
  Future<void> toggleFavorite(int bookId, bool isFavorite) async {
    final db = await database;
    await db.update(
      'books',
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  // ─── DELETE ───────────────────────────────────────────

  Future<int> deleteBook(int id) async {
    final db = await database;
    return await db.delete(
      'books',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Close DB
  Future close() async {
    final db = await database;
    db.close();
  }
}
