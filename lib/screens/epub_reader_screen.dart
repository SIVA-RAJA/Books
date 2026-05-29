import 'package:flutter/material.dart';
import 'package:epub_view/epub_view.dart';
import 'dart:io';
import '../models/book_model.dart';
import '../database/db_helper.dart';

class EpubReaderScreen extends StatefulWidget {
  final Book book;

  const EpubReaderScreen({super.key, required this.book});

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  EpubController? _epubController;
  bool _showControls = true;
  bool _isLoading = true;
  int _currentChapter = 0;
  int _totalChapters = 0;

  @override
  void initState() {
    super.initState();
    _initEpub();
  }

  Future<void> _initEpub() async {
    // Add small delay to let navigation transition finish smoothly
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      final file = File(widget.book.filePath);
      final bytes = await file.readAsBytes();

      // ── FIX: store controller in local var first,
      //    then mounted check before calling setState ──
      final controller = EpubController(
        document: EpubDocument.openData(bytes),
      );

      if (!mounted) return;
      setState(() {
        _epubController = controller;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load EPUB: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _saveProgress();
    _epubController?.dispose();
    super.dispose();
  }

  Future<void> _saveProgress() async {
    if (_totalChapters > 0) {
      await DBHelper.instance.updateReadingProgress(
        bookId: widget.book.id!,
        currentPage: _currentChapter,
        totalPages: _totalChapters,
      );
    }
  }

  Future<void> _saveAndNotify() async {
    await _saveProgress();
    // ── FIX: mounted check after async gap ──
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Progress saved!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  void _showTableOfContents() {
    final controller = _epubController;
    if (controller == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Table of Contents',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Expanded(
              child: EpubViewTableOfContents(controller: controller),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Pure vanta black
      appBar: _showControls
          ? AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.book.title,
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_totalChapters > 0)
                    Text(
                      'Chapter $_currentChapter of $_totalChapters',
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.list),
                  onPressed: _showTableOfContents,
                  tooltip: 'Table of Contents',
                ),
                IconButton(
                  icon: const Icon(Icons.bookmark_add_outlined),
                  // ── FIX: extracted to method with mounted check ──
                  onPressed: _saveAndNotify,
                ),
              ],
            )
          : null,

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _epubController == null
              ? const Center(child: Text('Failed to load book'))
              : GestureDetector(
                  onTap: _toggleControls,
                  child: EpubView(
                    controller: _epubController!,
                    onChapterChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _currentChapter = value.chapterNumber + 1;
                        });
                        _saveProgress();
                      }
                    },
                    onDocumentLoaded: (document) {
                      setState(() {
                        _totalChapters =
                            document.Chapters?.length ?? 0;
                      });
                    },
                    onDocumentError: (error) {
                      // ── FIX: synchronous context use,
                      //    no async gap here ──
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $error'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
