class Book {
  final int? id;
  final String title;
  final String author;
  final String genre;
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
  final String? tags; // comma separated tags
  final bool isCompleted;

  Book({
    this.id,
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
  });

  // Convert Book to Map (for saving to DB)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
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

  // Convert Map to Book (for reading from DB)
  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'],
      title: map['title'],
      author: map['author'],
      genre: map['genre'],
      filePath: map['filePath'],
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
      isCompleted: map['isCompleted'] == 1 || (map['readingProgress'] ?? 0.0) >= 1.0,
    );
  }

  // CopyWith - to update specific fields
  Book copyWith({
    int? id,
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
