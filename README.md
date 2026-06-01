# Books 📚 — Personal Ebook Organizer

A beautifully designed, feature-rich, and completely private offline Ebook organizer and reader built with Flutter.

![Books App Cover](assets/images/placeholder_cover.png) _(UI features a premium Vanta Black, Surface 2, and Sepia design system)._

---

## ✨ Features

- **Multi-Format Support**: Read PDF, EPUB, and TXT files natively within the app.
- **Lightning Fast Bulk Import**: Select your local library folder and the app will recursively scan, import, and auto-generate beautiful gradient covers (or extract high-quality PDF covers) for your entire collection in seconds.
- **100% Offline English-to-Tamil Translation**: Highlight text in any PDF or TXT file and instantly translate it to Tamil without needing an internet connection (powered by Google ML Kit).
- **Advanced Reading Stats**:
  - Track total daily reading time and reading streaks.
  - View a GitHub-style reading heatmap and beautiful trend charts.
  - Generates a "Yearly Wrapped" summary of your reading habits.
- **Smart Organization**: Filter by genres, mark books as favorites, and toggle between clean Grid and List views.
- **Automated Background Backups**: Set it and forget it. The app securely backs up your database to your local storage weekly.
- **Privacy First**: Everything stays on your device. No cloud sync, no tracking, no accounts required.

---

## 📱 How to Use the App

1. **Importing Books**:
   - Tap the **`⋮` (3 dots)** in the top right corner and select **"Add Single Book"** to pick a specific file.
   - Or, select **"Add Library Folder"**. The app will scan that folder (and all sub-folders) for books and import them instantly.
2. **Reading & Translating**:
   - Tap any book to open it.
   - To translate: Long-press any English text to highlight it, and select **"Translate to Tamil"** from the popup menu. _(Note: The very first time you do this, the app will download a 30MB AI translation model. This download strictly requires an unmetered Wi-Fi connection and will **not** use cellular data. **Mobile Hotspot Users:** Android blocks this download on Hotspots. To bypass this, go to your phone's Wi-Fi Settings > Tap the Hotspot > Network Usage > Change to "Treat as unmetered")._
3. **Tracking Progress**:
   - As you read, the progress bar updates automatically. Check the **Stats** tab (graph icon) to see your reading streaks and daily goals!
4. **Backups**:
   - Backups happen automatically, but you can manually backup or restore your library anytime from the top-right menu.

---

## 🛠️ For Developers: How to Run the Project

This project is built with Flutter and supports Android natively.

### Prerequisites

Before you begin, ensure you have the following installed on your machine:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version 3.0.0 or higher)
- [Dart SDK](https://dart.dev/get-dart)
- An IDE (VS Code, Android Studio, or IntelliJ IDEA)
- An Android Emulator or physical Android device connected via USB.

### Setup Instructions (All Operating Systems)

These steps are identical for Windows, macOS, and Linux (Ubuntu, Fedora, Arch, etc.).

1. **Clone the repository:**

   ```bash
   git clone <repository-url>
   cd Books
   ```

2. **Fetch dependencies:**

   ```bash
   flutter pub get
   ```

3. **Connect a Device:**
   Ensure your emulator is running, or your physical device is connected with USB Debugging enabled. Verify the connection:

   ```bash
   flutter devices
   ```

4. **Run the app:**
   ```bash
   flutter run
   ```

### Building for Release (Important for Translation Feature)

When testing the **Offline Translation feature**, be aware that running `flutter run` creates a "Fat APK" containing all architectures, making the app size massive (~150MB+).

To build a highly optimized, small release version for your specific device:

```bash
flutter build apk --split-per-abi
```

You will find the optimized APKs in `build/app/outputs/flutter-apk/`. Install the `armeabi-v7a` or `arm64-v8a` version on your phone.

---

## 📝 Architecture & Dependencies

- **State & Storage**: `sqflite` for metadata persistence, `shared_preferences` for settings.
- **Reading Engines**: `syncfusion_flutter_pdfviewer` & `pdfrx` (PDFs), `epub_view` (EPUBs).
- **AI Integration**: `google_mlkit_translation` for on-device NLP.
- **Background Tasks**: `workmanager` for scheduled weekly backups.

---


_Built for readers, by reader._
