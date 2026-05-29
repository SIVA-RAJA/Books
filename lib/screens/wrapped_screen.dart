import 'package:flutter/material.dart';
import '../main.dart' show AppColors;
import '../database/db_helper.dart';

class WrappedScreen extends StatefulWidget {
  final int year;
  const WrappedScreen({super.key, required this.year});

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await DBHelper.instance.getWrappedStats(widget.year);
    setState(() {
      _stats = stats;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final totalSeconds = _stats['totalSeconds'] as int;
    final mostReadAuthor = _stats['mostReadAuthor'] as String;
    final totalPages = _stats['totalPages'] as int;
    final totalBooksCompleted = _stats['totalBooksCompleted'] as int;
    final busiestMonth = _stats['busiestMonth'] as String;

    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('${widget.year} Wrapped', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Text(
              "Your Year in Books",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            _buildStatCard("Time Spent Reading", "$hours h $minutes m", Icons.timer_rounded, Colors.blueAccent),
            const SizedBox(height: 20),
            _buildStatCard("Books Finished", "$totalBooksCompleted", Icons.library_books_rounded, Colors.green),
            const SizedBox(height: 20),
            _buildStatCard("Pages Devoured", "$totalPages", Icons.menu_book_rounded, AppColors.primary),
            const SizedBox(height: 20),
            _buildStatCard("Top Author", mostReadAuthor, Icons.person_rounded, AppColors.accent),
            const SizedBox(height: 20),
            _buildStatCard("Busiest Month", busiestMonth, Icons.calendar_today_rounded, Colors.orange),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ]
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
