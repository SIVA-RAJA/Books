# Books 📚

**Books** is a beautiful, modern, and feature-rich Personal Ebook Organizer built with Flutter. It allows you to seamlessly manage, read, and track your local ebook collection (PDF & EPUB) all in one place.

## ✨ Features

- **Modern UI/UX**: Designed with a sleek, responsive dark theme using Material 3 and custom design tokens.
- **Multi-Format Support**: Native viewing support for both **PDF** and **EPUB** formats.
- **Smart Metadata**: Automatically extracts cover images from PDF files upon import.
- **Reading Tracking**: Automatically tracks your reading progress, pages read, and remembers your last read position.
- **Library Management**: Organize your collection using genres, tags, and favorites.
- **Advanced Search & Filtering**: Easily find books by title, author, or tag. Sort by recently added, title, or progress.
- **Reading Stats**: Visualize your reading habits with detailed statistics and charts (Completed, Reading, Not Started).
- **Local Storage**: Completely offline. All metadata is stored locally using SQLite.

## 🛠️ Technology Stack

- **Framework**: Flutter (Dart)
- **Local Database**: `sqflite` for fast and reliable local data persistence.
- **File Management**: `file_picker` & `path_provider` for importing local documents.
- **Document Rendering**: 
  - `syncfusion_flutter_pdfviewer` for high-performance PDF reading.
  - `epub_view` for rendering EPUB files.
  - `pdfrx` for automatic PDF cover extraction.
- **UI Elements**: `google_fonts`, `flutter_staggered_grid_view`, `cached_network_image`, `lottie`.

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (`>=3.0.0 <4.0.0`)
- Dart SDK
- Supported platforms: Android, iOS, Web, Desktop (Windows, macOS, Linux)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/SIVA-RAJA/books.git
   cd books
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```

## 📂 Project Structure

```text
lib/
├── database/        # SQLite database helper and queries
├── models/          # Data models (Book model)
├── screens/         # UI Screens (Home, Detail, PDF/EPUB readers, Add book)
├── utils/           # Constants, page transitions, and helpers
├── widgets/         # Reusable UI components (BookCard, BottomSheets)
└── main.dart        # Entry point and theme configuration
```

## 🤝 Contributing
Contributions, issues, and feature requests are welcome!

## 📝 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
