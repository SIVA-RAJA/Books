import 'package:flutter/material.dart';
import '../services/translation_service.dart';
import '../main.dart' show AppColors;

class TranslationBottomSheet extends StatefulWidget {
  final String originalText;

  const TranslationBottomSheet({
    super.key,
    required this.originalText,
  });

  static void show(BuildContext context, String text) {
    if (text.trim().isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TranslationBottomSheet(originalText: text),
    );
  }

  @override
  State<TranslationBottomSheet> createState() => _TranslationBottomSheetState();
}

class _TranslationBottomSheetState extends State<TranslationBottomSheet> {
  bool _isModelDownloaded = false;
  bool _isDownloading = false;
  bool _isTranslating = false;
  String? _translatedText;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _checkModelAndTranslate();
  }

  Future<void> _checkModelAndTranslate() async {
    setState(() => _isTranslating = true);
    try {
      final downloaded = await TranslationService.instance.isModelDownloaded();
      if (!mounted) return;

      setState(() {
        _isModelDownloaded = downloaded;
      });

      if (downloaded) {
        await _performTranslation();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Error checking model: $e');
      }
    } finally {
      if (mounted && _isModelDownloaded) {
        setState(() => _isTranslating = false);
      }
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _errorMsg = null;
    });

    try {
      await TranslationService.instance.downloadModel().timeout(
        const Duration(seconds: 300),
        onTimeout: () {
          throw Exception('Download timed out');
        },
      );
      if (!mounted) return;
      setState(() {
        _isModelDownloaded = true;
        _isDownloading = false;
      });
      await _performTranslation();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e.toString().contains('timed out')) {
            _errorMsg = 'Download is taking too long. Please cancel, check your connection, and try again.';
          } else {
            _errorMsg = 'Download failed. Please check your internet connection.';
          }
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _performTranslation() async {
    setState(() {
      _isTranslating = true;
      _errorMsg = null;
    });
    try {
      final result = await TranslationService.instance.translate(widget.originalText);
      if (mounted) {
        setState(() {
          _translatedText = result;
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Failed to translate text.';
          _isTranslating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.borderBright,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Original text header
          const Row(
            children: [
              Icon(Icons.language_rounded, color: AppColors.textMuted, size: 18),
              SizedBox(width: 8),
              Text('English', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              widget.originalText,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.5),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 16),
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),

          // Translation section
          const Row(
            children: [
              Icon(Icons.g_translate_rounded, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text('Tamil', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),

          if (_errorMsg != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(color: AppColors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          else if (!_isModelDownloaded)
            _buildDownloadState()
          else if (_isTranslating || _translatedText == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.bg],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                _translatedText!,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDownloadState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.download_rounded, size: 32, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          const Text(
            'Offline Translation Required',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'To translate text, you need to download the Tamil translation model (approx. 30MB) once. After this, all translations will be completely offline.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isDownloading ? null : _downloadModel,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isDownloading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.download_rounded, size: 18),
              label: Text(_isDownloading ? 'Downloading Model...' : 'Download Model (30MB)', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}
