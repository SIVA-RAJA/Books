import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/quote_screen.dart';
import 'services/background_scan_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

class AppColors {
  // Brand (Buttons, highlights are just grey!)
  static const primary    = Color(0xFF404040); // Dark grey buttons
  static const primaryDim = Color(0xFF262626); // Even darker grey
  static const accent     = Color(0xFF606060); // Mid-grey accents
  static const accentDim  = Color(0xFF333333);

  // Surfaces (Layers of black)
  static const bg         = Color(0xFF000000); // Pitch black
  static const surface    = Color(0xFF080808); // Barely lighter black
  static const surface2   = Color(0xFF121212); // Very dark grey
  static const surface3   = Color(0xFF1A1A1A); // Dark grey

  // Text
  static const textPrimary   = Color(0xFFCCCCCC); // Soft light grey
  static const textSecondary = Color(0xFF888888); // Dim grey
  static const textMuted     = Color(0xFF555555); // Very dim grey

  // Status (Heavily desaturated so they don't pop out too much)
  static const green    = Color(0xFF4A6B4A);
  static const orange   = Color(0xFF8B6343);
  static const red      = Color(0xFF824545);
  static const yellow   = Color(0xFF8C824A);

  // Borders
  static const border   = Color(0xFF1A1A1A);
  static const borderBright = Color(0xFF2B2B2B);
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Request storage permissions ─────────────────────────────────────────────
  // MANAGE_EXTERNAL_STORAGE: on Android 11+ (API 30+) this cannot be granted
  // with a normal dialog — Android silently ignores .request(). We must send
  // the user to the special "All Files Access" settings screen instead.
  final manageStatus = await Permission.manageExternalStorage.status;
  if (!manageStatus.isGranted) {
    // First try the normal request (works on some vendors/older builds)
    final result = await Permission.manageExternalStorage.request();
    if (!result.isGranted) {
      // If still not granted, open the system settings page for this app
      await openAppSettings();
    }
  }
  // Legacy READ_EXTERNAL_STORAGE — needed on Android ≤ 12
  if (await Permission.storage.isDenied) {
    await Permission.storage.request();
  }

  // Force dark status bar icons & transparent bars
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Hide OS navigation buttons for full immersive experience
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // ── Init WorkManager for weekly background scan ─────────────────────────────
  await BackgroundScanService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const poppins = 'Poppins';

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: poppins,

      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        onSecondary: Colors.black,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        surfaceContainerHighest: AppColors.surface3,
        outline: AppColors.border,
        error: AppColors.red,
        primaryContainer: AppColors.surface3,
        onPrimaryContainer: AppColors.primary,
        secondaryContainer: Color(0xFF1A2A3A),
        onSecondaryContainer: AppColors.accent,
      ),

      textTheme: const TextTheme(
        bodyLarge:   TextStyle(color: AppColors.textPrimary,   fontFamily: poppins),
        bodyMedium:  TextStyle(color: AppColors.textSecondary, fontFamily: poppins),
        bodySmall:   TextStyle(color: AppColors.textMuted,     fontFamily: poppins),
        titleLarge:  TextStyle(color: AppColors.textPrimary,   fontFamily: poppins, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: AppColors.textPrimary,   fontFamily: poppins, fontWeight: FontWeight.w600),
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.textSecondary),
      ),

      // NavigationBar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary);
          }
          return const IconThemeData(color: AppColors.textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(color: AppColors.textMuted, fontSize: 11);
        }),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      // TabBar
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 13),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      // Dividers
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        modalBarrierColor: Color(0x99000000),
      ),

      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surface3,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.15),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        trackHeight: 3,
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface3,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // FilledButton
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
        ),
      ),

      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: StadiumBorder(),
      ),

      // PopupMenu
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 8,
      ),

      // SearchBar
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStateProperty.all(AppColors.surface2),
        elevation: WidgetStateProperty.all(0),
        side: WidgetStateProperty.all(
          const BorderSide(color: AppColors.border),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        hintStyle: WidgetStateProperty.all(
          const TextStyle(color: AppColors.textMuted),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(color: AppColors.textPrimary),
        ),
      ),
    );

    return MaterialApp(
      title: 'Books',
      debugShowCheckedModeBanner: false,
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark, // always dark
      home: const QuoteScreen(),
    );
  }
}
