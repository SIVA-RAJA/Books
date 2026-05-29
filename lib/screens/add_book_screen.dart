import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:pdfrx/pdfrx.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:ui' as ui;
import '../database/db_helper.dart';
import '../models/book_model.dart';
import '../utils/constants.dart';
import '../main.dart' show AppColors;

// ─────────────────────────────────────────────────────────────────────────────
// AddBookScreen
//
// Allows adding a single book by picking a file.
// The file is NOT copied into app storage — the original external path is used.
// Covers are still extracted/copied into app storage because they are tiny
// generated thumbnails, not originals.
// ─────────────────────────────────────────────────────────────────────────────

class AddBookScreen extends StatefulWidget {
  const AddBookScreen({super.key});

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();

  // State
  String? _selectedFilePath;  // original path — stored as-is in DB
  String? _selectedFileName;
  String? _selectedFileType;
  String? _coverImagePath;    // user-picked cover (original path, not copied)

  // Multi-genre selection
  final Set<String> _selectedGenres = {};

  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  // ─── Pick book file ────────────────────────────────────────────────────────

  Future<void> _pickBookFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: AppConstants.supportedExtensions,
        allowMultiple: false,
      );

      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() {
        _selectedFilePath = file.path;
        _selectedFileName = file.name;
        _selectedFileType =
            path.extension(file.name).replaceAll('.', '').toLowerCase();

        // Auto-fill title from filename
        if (_titleController.text.isEmpty) {
          _titleController.text = path
              .basenameWithoutExtension(file.name)
              .replaceAll('_', ' ')
              .replaceAll('-', ' ');
        }
      });
    } catch (e) {
      if (mounted) _showSnackbar('Error picking file: $e', isError: true);
    }
  }

  // ─── Pick cover image ──────────────────────────────────────────────────────

  Future<void> _pickCoverImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;
      setState(() => _coverImagePath = result.files.first.path);
    } catch (e) {
      if (mounted) _showSnackbar('Error picking image: $e', isError: true);
    }
  }

  // ─── Extract PDF first page as cover ──────────────────────────────────────
  // Cover thumbnails are small generated images — we store them inside the
  // app's documents directory since they are not original files.

  Future<String?> _extractPdfFirstPageAsCover(String pdfPath) async {
    try {
      final doc = await PdfDocument.openFile(pdfPath);
      final page = doc.pages[0];

      const targetWidth = 300.0;
      final scale = targetWidth / page.width;
      final targetHeight = page.height * scale;

      final pageImage = await page.render(
        fullWidth: targetWidth,
        fullHeight: targetHeight,
        backgroundColor: Colors.white,
      );

      if (pageImage == null) {
        await doc.dispose();
        return null;
      }

      final uiImage = await pageImage.createImage();
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      pageImage.dispose();
      await doc.dispose();

      if (byteData == null) return null;

      // Save cover thumbnail to app documents (small generated file — safe here)
      final appDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory('${appDir.path}/covers');
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }
      final coverName =
          'auto_cover_${DateTime.now().millisecondsSinceEpoch}.png';
      final coverFile = File('${coversDir.path}/$coverName');
      await coverFile.writeAsBytes(byteData.buffer.asUint8List());

      return coverFile.path;
    } catch (_) {
      return null; // silently fail — cover will just be null
    }
  }

  // ─── Copy cover image to app storage ──────────────────────────────────────
  // A user-picked cover image is copied so we own a persistent reference.

  Future<String> _copyCoverToAppStorage(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory('${appDir.path}/covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    final fileName = path.basename(sourcePath);
    final destPath = '${coversDir.path}/$fileName';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  // ─── Custom genre prompt ───────────────────────────────────────────────────

  Future<void> _promptCustomGenre() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Custom Genre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Enter genre name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) Navigator.pop(context, val);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _selectedGenres.add(result));
    }
  }

  void _toggleGenre(String genre) {
    if (genre == 'Other') {
      _promptCustomGenre();
      return;
    }
    setState(() {
      if (_selectedGenres.contains(genre)) {
        _selectedGenres.remove(genre);
      } else {
        _selectedGenres.add(genre);
      }
    });
  }

  // ─── Save book ─────────────────────────────────────────────────────────────

  Future<void> _saveBook() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFilePath == null) {
      _showSnackbar('Please select a book file', isError: true);
      return;
    }
    if (_selectedGenres.isEmpty) {
      _showSnackbar('Please select at least one genre', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // File stays at original path — no copy needed
      final filePath = _selectedFilePath!;

      // Determine cover
      String? savedCoverPath;
      if (_coverImagePath != null) {
        // User provided a cover — copy it so we own a persistent reference
        savedCoverPath = await _copyCoverToAppStorage(_coverImagePath!);
      } else if (_selectedFileType == 'pdf') {
        // Auto-extract first page of the PDF as cover thumbnail
        savedCoverPath =
            await _extractPdfFirstPageAsCover(_selectedFilePath!);
      }

      final genreString = _selectedGenres.join(', ');

      final book = Book(
        title: _titleController.text.trim(),
        author: _authorController.text.trim(),
        genre: genreString,
        filePath: filePath,     // original external path
        fileType: _selectedFileType ?? 'pdf',
        coverImagePath: savedCoverPath,
        dateAdded: DateTime.now(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        tags: _tagsController.text.trim().isEmpty
            ? null
            : _tagsController.text.trim(),
      );

      await DBHelper.instance.insertBook(book);

      if (!mounted) return;
      _showSnackbar('Book added successfully!');
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _showSnackbar('Error saving book: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Snackbar helper ───────────────────────────────────────────────────────

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.red : AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Add New Book',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              color: AppColors.bg.withValues(alpha: 0.75),
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 20),
                  Text(
                    'Saving book…',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── File Picker ──
                    _buildSectionTitle('Book File *'),
                    const SizedBox(height: 8),
                    _buildFilePicker(theme),
                    const SizedBox(height: 24),

                    // ── Cover Image ──
                    _buildSectionTitle('Cover Image'),
                    const SizedBox(height: 4),
                    Text(
                      _selectedFileType == 'pdf'
                          ? 'Optional — leave empty to auto-extract from PDF'
                          : 'Optional',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _buildCoverImagePicker(theme),
                    const SizedBox(height: 24),

                    // ── Title ──
                    _buildSectionTitle('Title *'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: _inputDecoration('Enter book title'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Title is required'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // ── Author ──
                    _buildSectionTitle('Author *'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _authorController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: _inputDecoration('Enter author name'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Author is required'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // ── Genre ──
                    _buildSectionTitle('Genre *'),
                    const SizedBox(height: 4),
                    const Text(
                      'Select one or more. Tap "Other" for custom.',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _buildGenreChips(theme),
                    const SizedBox(height: 16),

                    // ── Description ──
                    _buildSectionTitle('Description (Optional)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration:
                          _inputDecoration('Enter book description'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),

                    // ── Tags ──
                    _buildSectionTitle('Tags (Optional)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _tagsController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: _inputDecoration(
                          'e.g. classic, must-read, favorite'),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Separate tags with commas',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 32),

                    // ── Save Button ──
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primaryDim
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _saveBook,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text(
                            'Save Book',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  // ─── Sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildFilePicker(ThemeData theme) {
    return GestureDetector(
      onTap: _pickBookFile,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: _selectedFilePath != null
                ? AppColors.primary
                : AppColors.border,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
          color: _selectedFilePath != null
              ? AppColors.primary.withValues(alpha: 0.07)
              : AppColors.surface2,
        ),
        child: _selectedFilePath == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.upload_file_rounded,
                      size: 44, color: AppColors.textMuted),
                  SizedBox(height: 8),
                  Text('Tap to select book file',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(
                    'PDF, EPUB, DOC, TXT supported',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              )
            : Row(
                children: [
                  Icon(
                    _getFileIcon(_selectedFileType ?? ''),
                    color: AppColors.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFileName ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _selectedFileType?.toUpperCase() ?? '',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _pickBookFile,
                    icon: const Icon(Icons.change_circle_outlined,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCoverImagePicker(ThemeData theme) {
    return GestureDetector(
      onTap: _pickCoverImage,
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          color: AppColors.surface2,
        ),
        child: _coverImagePath == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_outlined,
                      size: 44, color: AppColors.textMuted),
                  const SizedBox(height: 8),
                  const Text('Tap to add cover image',
                      style:
                          TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                    _selectedFileType == 'pdf'
                        ? 'Leave empty → auto-extract first PDF page'
                        : 'Leave empty for default cover',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(_coverImagePath!), fit: BoxFit.cover),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _coverImagePath = null),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildGenreChips(ThemeData theme) {
    final genres =
        AppConstants.genres.where((g) => g != 'All').toList();
    final customGenres = _selectedGenres
        .where((g) => !AppConstants.genres.contains(g))
        .toList();
    final allChips = [...genres, ...customGenres];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allChips.map((genre) {
        final isSelected = _selectedGenres.contains(genre);
        final isOther = genre == 'Other';
        return FilterChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOther && !isSelected) ...[
                const Icon(Icons.add,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
              ],
              Text(genre),
            ],
          ),
          selected: isSelected,
          onSelected: (_) => _toggleGenre(genre),
          backgroundColor: AppColors.surface2,
          selectedColor: AppColors.primary.withValues(alpha: 0.2),
          checkmarkColor: AppColors.primary,
          labelStyle: TextStyle(
            color:
                isSelected ? AppColors.primary : AppColors.textSecondary,
            fontWeight:
                isSelected ? FontWeight.w700 : FontWeight.normal,
            fontSize: 13,
          ),
          side: BorderSide(
            color:
                isSelected ? AppColors.primary : AppColors.border,
          ),
          showCheckmark: !isOther,
          padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        );
      }).toList(),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: AppColors.primary, width: 2),
      ),
      filled: true,
      fillColor: AppColors.surface2,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  IconData _getFileIcon(String type) {
    switch (type) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'epub':
        return Icons.menu_book;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }
}
