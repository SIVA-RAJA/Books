import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import '../main.dart' show AppColors;

class QuoteScreen extends StatefulWidget {
  const QuoteScreen({super.key});

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  bool _isLoading = true;
  String _quoteText = '';
  String _quoteAuthor = '';

  @override
  void initState() {
    super.initState();
    // Keep immersive mode on the quote screen too
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    try {
      final jsonString = await rootBundle.loadString('assets/quotes.json');
      final List<dynamic> jsonList = jsonDecode(jsonString);

      final prefs = await SharedPreferences.getInstance();
      int lastQuoteIndex = prefs.getInt('lastQuoteIndex') ?? -1;
      
      // Increment and wrap around
      int nextIndex = lastQuoteIndex + 1;
      if (nextIndex >= jsonList.length) {
        nextIndex = 0;
      }
      
      await prefs.setInt('lastQuoteIndex', nextIndex);

      final quoteData = jsonList[nextIndex];
      
      if (mounted) {
        setState(() {
          _quoteText = quoteData['quoteText'] ?? 'A room without books is like a body without a soul.';
          _quoteAuthor = quoteData['quoteAuthor'] ?? 'Marcus Tullius Cicero';
          if (_quoteAuthor.trim().isEmpty) {
            _quoteAuthor = 'Unknown';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _quoteText = 'Error loading quotes: $e';
          _quoteAuthor = 'System';
          _isLoading = false;
        });
      }
    }
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.textSecondary)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black, // Vanta black stealth mode
      body: GestureDetector(
        onTap: _goToHome,
        behavior: HitTestBehavior.opaque, // Tap anywhere
        child: SizedBox.expand(
          child: Stack(
            children: [
              // Quote Content
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.format_quote_rounded, size: 48, color: AppColors.textMuted),
                      const SizedBox(height: 24),
                      Text(
                        _quoteText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          height: 1.6,
                          fontFamily: 'Georgia', // Elegant serif font
                          fontStyle: FontStyle.italic,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        '— $_quoteAuthor',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom subtle hint
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Tap anywhere to continue',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
