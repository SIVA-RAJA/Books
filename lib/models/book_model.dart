import 'package:path/path.dart' as p;

class Book {
  final int? id;

  /// The PDF/EPUB filename (e.g. "MyBook.pdf").
  /// This is the UNIQUE KEY used to reconnect metadata after a restore.
  /// Never rename your files — this is the permanent identity of a book.
  final String fileName;

  final String title;
  final String author;
  final String genre;

  /// Full absolute path to the file on device storage.
  /// This may change (e.g. after restore + folder re-scan), but fileName won't.
  final String filePath;
  final String fileType; // pdf, epub, txt, doc
  final String? coverImagePath;
  final int totalPages;
  final int currentPage;
  final double readingProgress; // 0.0 to 1.0
  final DateTime dateAdded;
  final DateTime? lastRead;
  final bool isFavorite;
  final String? description;
  final String? tags; // comma-separated tags
  final bool isCompleted;

  Book({
    this.id,
    String? fileName,    // optional — derived from filePath if not supplied
    required this.title,
    required this.author,
    required this.genre,
    required this.filePath,
    required this.fileType,
    this.coverImagePath,
    this.totalPages = 0,
    this.currentPage = 0,
    this.readingProgress = 0.0,
    required this.dateAdded,
    this.lastRead,
    this.isFavorite = false,
    this.description,
    this.tags,
    this.isCompleted = false,
  }) : fileName = fileName ?? p.basename(filePath);

  // ─── DB serialization ──────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fileName': fileName,
      'title': title,
      'author': author,
      'genre': genre,
      'filePath': filePath,
      'fileType': fileType,
      'coverImagePath': coverImagePath,
      'totalPages': totalPages,
      'currentPage': currentPage,
      'readingProgress': readingProgress,
      'dateAdded': dateAdded.toIso8601String(),
      'lastRead': lastRead?.toIso8601String(),
      'isFavorite': isFavorite ? 1 : 0,
      'description': description,
      'tags': tags,
      'isCompleted': isCompleted ? 1 : 0,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    final filePath = map['filePath'] as String? ?? '';
    // If fileName column is missing/empty (old DB row), derive from filePath
    final storedFileName = map['fileName'] as String?;
    final fileName = (storedFileName != null && storedFileName.isNotEmpty)
        ? storedFileName
        : p.basename(filePath);
    return Book(
      id: map['id'],
      fileName: fileName,
      title: map['title'],
      author: map['author'],
      genre: map['genre'],
      filePath: filePath,
      fileType: map['fileType'],
      coverImagePath: map['coverImagePath'],
      totalPages: map['totalPages'] ?? 0,
      currentPage: map['currentPage'] ?? 0,
      readingProgress: map['readingProgress'] ?? 0.0,
      dateAdded: DateTime.parse(map['dateAdded']),
      lastRead: map['lastRead'] != null
          ? DateTime.parse(map['lastRead'])
          : null,
      isFavorite: map['isFavorite'] == 1,
      description: map['description'],
      tags: map['tags'],
      isCompleted: map['isCompleted'] == 1 ||
          (map['readingProgress'] ?? 0.0) >= 1.0,
    );
  }

  // ─── CopyWith ──────────────────────────────────────

  Book copyWith({
    int? id,
    String? fileName,
    String? title,
    String? author,
    String? genre,
    String? filePath,
    String? fileType,
    String? coverImagePath,
    int? totalPages,
    int? currentPage,
    double? readingProgress,
    DateTime? dateAdded,
    DateTime? lastRead,
    bool? isFavorite,
    String? description,
    String? tags,
    bool? isCompleted,
  }) {
    return Book(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      title: title ?? this.title,
      author: author ?? this.author,
      genre: genre ?? this.genre,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      totalPages: totalPages ?? this.totalPages,
      currentPage: currentPage ?? this.currentPage,
      readingProgress: readingProgress ?? this.readingProgress,
      dateAdded: dateAdded ?? this.dateAdded,
      lastRead: lastRead ?? this.lastRead,
      isFavorite: isFavorite ?? this.isFavorite,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
