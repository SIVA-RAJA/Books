import 'package:workmanager/workmanager.dart';
import 'backup_restore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundScanService
//
// Schedules a weekly background scan of the library folder.
// Runs every Sunday at 12:00 AM (midnight).
// If new books are found, auto-backs up the database.
// ─────────────────────────────────────────────────────────────────────────────

const kWeeklyScanTask  = 'weekly_library_scan';
const kFolderPathPref  = 'library_folder_path';

/// Top-level entry point — WorkManager calls this in a separate isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == kWeeklyScanTask) {
      try {
        // Retrieve folder path from SharedPreferences (available in isolate)
        final prefs = await SharedPreferences.getInstance();
        final folderPath = prefs.getString(kFolderPathPref);
        if (folderPath == null || folderPath.isEmpty) return true;

        final service = BackupRestoreService();
        final result  = await service.scanLibraryFolder(folderPath);

        // Auto-backup if any new books were discovered
        if (result.added > 0) {
          await service.backup();
        }
      } catch (_) {
        // Don't fail the task — WorkManager will retry on failure
      }
    }
    return true;
  });
}

class BackgroundScanService {
  BackgroundScanService._();

  // ── Initialise WorkManager (call once at app start) ─────────────────────────

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  // ── Schedule / reschedule weekly scan ───────────────────────────────────────

  /// Saves [folderPath] to SharedPreferences so the background isolate can
  /// read it, then registers a periodic task that fires every 7 days.
  static Future<void> scheduleWeeklyScan(String folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kFolderPathPref, folderPath);

    final delay = _delayUntilNextSundayMidnight();

    await Workmanager().registerPeriodicTask(
      kWeeklyScanTask,
      kWeeklyScanTask,
      frequency: const Duration(days: 7),
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.notRequired),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(kWeeklyScanTask);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Returns the duration from now until the next Sunday at 00:00:00.
  static Duration _delayUntilNextSundayMidnight() {
    final now = DateTime.now();
    // DateTime.sunday == 7
    final daysUntil = (DateTime.sunday - now.weekday + 7) % 7;
    // If today IS Sunday but it's already past midnight, schedule next week
    final targetDay = daysUntil == 0 ? 7 : daysUntil;
    final nextSunday = DateTime(now.year, now.month, now.day + targetDay);
    return nextSunday.difference(now);
  }

  /// Quick helper to store the folder path whenever the user picks a folder.
  static Future<void> saveFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kFolderPathPref, path);
  }

  static Future<String?> getSavedFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kFolderPathPref);
  }
}
