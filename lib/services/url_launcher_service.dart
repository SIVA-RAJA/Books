import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class UrlLauncherService {
  /// Launches a URL explicitly targeting Google Chrome on Android.
  static Future<void> openInChrome(String urlString) async {
    if (urlString.trim().isEmpty) return;
    final Uri url = Uri.parse(urlString);

    try {
      bool launched = false;
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          launched = await launchUrl(
            url,
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {}
      }

      if (!launched) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching URL in Chrome: $e');
    }
  }

  /// Opens Google Translate in Chrome as a web fallback for the given text.
  static Future<void> openGoogleTranslateInChrome(String text) async {
    final encodedText = Uri.encodeComponent(text);
    final translateUrl = 'https://translate.google.com/?sl=en&tl=ta&text=$encodedText';
    await openInChrome(translateUrl);
  }
}
