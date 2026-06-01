import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  TranslationService._privateConstructor();
  static final TranslationService instance = TranslationService._privateConstructor();

  final _modelManager = OnDeviceTranslatorModelManager();
  
  // Create an English to Tamil translator
  final _translator = OnDeviceTranslator(
    sourceLanguage: TranslateLanguage.english,
    targetLanguage: TranslateLanguage.tamil,
  );

  /// Checks if the Tamil translation model is already downloaded on the device.
  Future<bool> isModelDownloaded() async {
    return await _modelManager.isModelDownloaded(TranslateLanguage.tamil.bcpCode);
  }

  /// Downloads the Tamil translation model.
  /// Throws an exception if it fails (e.g., no internet).
  Future<void> downloadModel() async {
    final success = await _modelManager.downloadModel(TranslateLanguage.tamil.bcpCode);
    if (!success) {
      throw Exception('Failed to download Tamil translation model.');
    }
  }

  /// Translates the given [text] from English to Tamil.
  Future<String> translate(String text) async {
    if (text.trim().isEmpty) return '';
    try {
      final translatedText = await _translator.translateText(text);
      return translatedText;
    } catch (e) {
      throw Exception('Translation failed: $e');
    }
  }

  /// Dispose the translator when no longer needed to free resources.
  /// Note: As a singleton service used globally, we might not dispose this often,
  /// but it's good practice to provide the method.
  Future<void> dispose() async {
    await _translator.close();
  }
}
