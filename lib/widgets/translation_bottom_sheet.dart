import 'package:flutter/material.dart';
import '../services/translation_service.dart';
import '../services/url_launcher_service.dart';
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
  int _downloadSeconds = 0;
  dynamic _pollingTimer;

  @override
  void initState() {
    super.initState();
    _checkModelAndTranslate();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
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
      _downloadSeconds = 0;
      _errorMsg = null;
    });

    // Poll every 2 seconds to see if model download completes asynchronously
    _pollingTimer?.cancel();
    _pollingTimer = Stream.periodic(const Duration(seconds: 2)).listen((_) async {
      if (!_isDownloading || !mounted) return;
      setState(() => _downloadSeconds += 2);
      try {
        final isDownloaded = await TranslationService.instance.isModelDownloaded();
        if (isDownloaded && mounted && _isDownloading) {
          _pollingTimer?.cancel();
          setState(() {
            _isModelDownloaded = true;
            _isDownloading = false;
          });
          await _performTranslation();
        }
      } catch (_) {}
    });

    try {
      await TranslationService.instance.downloadModel().timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          throw Exception('Download timed out');
        },
      );
      if (!mounted) return;
      _pollingTimer?.cancel();
      setState(() {
        _isModelDownloaded = true;
        _isDownloading = false;
      });
      await _performTranslation();
    } catch (e) {
      if (mounted && _isDownloading) {
        // Double check if model actually succeeded despite timeout
        final isDownloaded = await TranslationService.instance.isModelDownloaded();
        if (isDownloaded) {
          _pollingTimer?.cancel();
          setState(() {
            _isModelDownloaded = true;
            _isDownloading = false;
          });
          await _performTranslation();
          return;
        }

        _pollingTimer?.cancel();
        setState(() {
          _errorMsg = 'Download is taking longer over cellular network. Tap below to translate instantly in Google Chrome!';
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
            Column(
              children: [
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
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    UrlLauncherService.openGoogleTranslateInChrome(widget.originalText);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                  label: const Text('Open in Google Chrome'),
                ),
              ],
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
          Icon(
            _isDownloading ? Icons.cloud_download_rounded : Icons.download_rounded,
            size: 36,
            color: _isDownloading ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            _isDownloading
                ? 'Downloading Offline Model... (${_downloadSeconds}s)'
                : 'Offline Tamil Translation Required',
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            _isDownloading
                ? 'Google Play Services is fetching the ~30MB Tamil pack. It will auto-translate as soon as finished!'
                : 'Download the Tamil translation model (~30MB) once for offline translation, or translate instantly in Google Chrome.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(
                _isDownloading
                    ? 'Downloading (${_downloadSeconds}s)...'
                    : 'Download Offline Model (30MB)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                UrlLauncherService.openGoogleTranslateInChrome(widget.originalText);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.borderBright),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.open_in_browser_rounded, size: 18, color: AppColors.primary),
              label: const Text(
                '🚀 Instant Translate in Google Chrome',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
