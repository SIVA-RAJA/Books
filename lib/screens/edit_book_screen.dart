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
// EditBookScreen
//
// Pre-fills all fields from an existing Book and saves updates back to the DB.
// The filePath / fileName are never changed — only metadata is edited.
// ─────────────────────────────────────────────────────────────────────────────

class EditBookScreen extends StatefulWidget {
  final Book book;
  const EditBookScreen({super.key, required this.book});

  @override
  State<EditBookScreen> createState() => _EditBookScreenState();
}

class _EditBookScreenState extends State<EditBookScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;

  // Cover: may be replaced by the user; starts with existing coverImagePath
  String? _coverImagePath;
  bool _isLoading = false;

  // Genres: pre-filled from existing book
  final Set<String> _selectedGenres = {};

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.book.title);
    _authorController = TextEditingController(text: widget.book.author);
    _descriptionController =
        TextEditingController(text: widget.book.description ?? '');
    _tagsController = TextEditingController(text: widget.book.tags ?? '');
    _coverImagePath = widget.book.coverImagePath;

    // Pre-select genres (comma-separated in DB)
    for (final g in widget.book.genre.split(',').map((e) => e.trim())) {
      if (g.isNotEmpty) _selectedGenres.add(g);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
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
      // Copy the picked image into app storage
      final picked = result.files.first.path!;
      final saved = await _copyCoverToAppStorage(picked);
      setState(() => _coverImagePath = saved);
    } catch (e) {
      if (mounted) _showSnackbar('Error picking image: $e', isError: true);
    }
  }

  // ─── Extract PDF first page as cover ──────────────────────────────────────

  Future<void> _extractCoverFromPdf() async {
    if (widget.book.fileType.toLowerCase() != 'pdf') return;
    setState(() => _isLoading = true);
    try {
      final coverPath =
          await _extractPdfFirstPageAsCover(widget.book.filePath);
      if (!mounted) return;
      setState(() {
        _coverImagePath = coverPath;
        _isLoading = false;
      });
      if (coverPath != null) {
        _showSnackbar('Cover extracted from PDF first page!');
      } else {
        _showSnackbar('Could not extract cover from PDF', isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('Error extracting cover: $e', isError: true);
      }
    }
  }

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
      if (pageImage == null) { await doc.dispose(); return null; }

      final uiImage = await pageImage.createImage();
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      pageImage.dispose();
      await doc.dispose();
      if (byteData == null) return null;

      final appDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory('${appDir.path}/covers');
      if (!await coversDir.exists()) await coversDir.create(recursive: true);
      final coverName = 'cover_${DateTime.now().millisecondsSinceEpoch}.png';
      final coverFile = File('${coversDir.path}/$coverName');
      await coverFile.writeAsBytes(byteData.buffer.asUint8List());
      return coverFile.path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _copyCoverToAppStorage(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory('${appDir.path}/covers');
    if (!await coversDir.exists()) await coversDir.create(recursive: true);
    final fileName =
        'cover_${DateTime.now().millisecondsSinceEpoch}${path.extension(sourcePath)}';
    final destPath = '${coversDir.path}/$fileName';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  // ─── Genre handling ────────────────────────────────────────────────────────

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
    if (genre == 'Other') { _promptCustomGenre(); return; }
    setState(() {
      if (_selectedGenres.contains(genre)) {
        _selectedGenres.remove(genre);
      } else {
        _selectedGenres.add(genre);
      }
    });
  }

  // ─── Save ──────────────────────────────────────────────────────────────────

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGenres.isEmpty) {
      _showSnackbar('Please select at least one genre', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updated = widget.book.copyWith(
        title: _titleController.text.trim(),
        author: _authorController.text.trim(),
        genre: _selectedGenres.join(', '),
        coverImagePath: _coverImagePath,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        tags: _tagsController.text.trim().isEmpty
            ? null
            : _tagsController.text.trim(),
      );

      await DBHelper.instance.updateBook(updated);
      if (!mounted) return;
      _showSnackbar('Book updated!');
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.pop(context, true); // true = refresh needed
    } catch (e) {
      if (mounted) _showSnackbar('Error saving: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text(
          'Edit Book',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 20),
                  Text('Saving changes…',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 14)),
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
                    // ── File info (read-only) ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_rounded,
                              color: AppColors.textMuted, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.book.fileName,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.book.fileType.toUpperCase(),
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Cover Image ──
                    _buildSectionTitle('Cover Image'),
                    const SizedBox(height: 8),
                    _buildCoverPicker(),
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

                    // ── Genre (multi-select) ──
                    _buildSectionTitle('Genre *'),
                    const SizedBox(height: 4),
                    const Text(
                      'Select one or more. Tap "Other" for custom.',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _buildGenreChips(),
                    const SizedBox(height: 16),

                    // ── Description ──
                    _buildSectionTitle('Description (Optional)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: _inputDecoration('Enter book description'),
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
                            colors: [AppColors.primary, AppColors.primaryDim],
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
                          onPressed: _saveChanges,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text(
                            'Save Changes',
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

  Widget _buildCoverPicker() {
    return Column(
      children: [
        // Cover preview / placeholder
        GestureDetector(
          onTap: _pickCoverImage,
          child: Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border, width: 1.5),
              borderRadius: BorderRadius.circular(14),
              color: AppColors.surface2,
            ),
            child: _coverImagePath == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 44, color: AppColors.textMuted),
                      SizedBox(height: 8),
                      Text('Tap to pick cover image',
                          style:
                              TextStyle(color: AppColors.textSecondary)),
                    ],
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(_coverImagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textMuted)),
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
        ),
        // Extract from PDF button (only for PDFs)
        if (widget.book.fileType.toLowerCase() == 'pdf') ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _extractCoverFromPdf,
              icon: const Icon(Icons.auto_fix_high_rounded,
                  size: 16, color: AppColors.accent),
              label: const Text('Auto-extract cover from PDF first page',
                  style: TextStyle(
                      color: AppColors.accent, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.accent),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGenreChips() {
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
              color: isSelected ? AppColors.primary : AppColors.border),
          showCheckmark: !isOther,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        );
      }).toList(),
    );
  }

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
}
