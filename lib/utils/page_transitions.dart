import 'package:flutter/material.dart';

/// Shared page-route transitions used throughout the app.
class AppRoutes {
  /// Slide-up + fade — feels like opening a book
  static Route<T> slideUp<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);

        // Secondary page fades slightly when pushed over
        final secondaryFade = Tween<double>(begin: 1.0, end: 0.85)
            .animate(CurvedAnimation(
                parent: secondaryAnimation, curve: Curves.easeIn));

        return FadeTransition(
          opacity: secondaryFade,
          child: FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          ),
        );
      },
    );
  }

  /// Slide-right (horizontal) — standard nav feel
  static Route<T> slideRight<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(
          begin: const Offset(1.0, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
  }

  /// Scale + fade — for dialogs/detail screens
  static Route<T> scaleUp<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final scale = Tween<double>(begin: 0.92, end: 1.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack));
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);

        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
    );
  }
}
