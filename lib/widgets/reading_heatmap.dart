import 'package:flutter/material.dart';
import '../main.dart' show AppColors;

// ─────────────────────────────────────────────────────────────────────────────
// ReadingHeatmap
//
// GitHub-style full-year heatmap:
//  • Shows all 52/53 weeks of the selected year horizontally
//  • Month labels (Jan, Feb …) appear at the correct column
//  • Year selector to switch between years
//  • Horizontally scrollable
//  • Current year by default; past years accessible via arrows
// ─────────────────────────────────────────────────────────────────────────────

class ReadingHeatmap extends StatefulWidget {
  /// Key: 'YYYY-MM-DD', Value: seconds read that day
  final Map<String, int> dailyData;

  const ReadingHeatmap({super.key, required this.dailyData});

  @override
  State<ReadingHeatmap> createState() => _ReadingHeatmapState();
}

class _ReadingHeatmapState extends State<ReadingHeatmap> {
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
  }

  int get _minYear {
    if (widget.dailyData.isEmpty) return DateTime.now().year;
    int min = DateTime.now().year;
    for (final key in widget.dailyData.keys) {
      if (key.length >= 4) {
        final y = int.tryParse(key.substring(0, 4));
        if (y != null && y < min) min = y;
      }
    }
    return min;
  }

  // ── Colour levels (cyan → bright teal, matching app accent) ────────────────
  static const _c0 = Color(0xFF1A1A2E); // empty
  static const _c1 = Color(0xFF003344); // < 5 min
  static const _c2 = Color(0xFF005577); // 5–15 min
  static const _c3 = Color(0xFF0099BB); // 15–30 min
  static const _c4 = Color(0xFF00D2FF); // > 30 min  (= AppColors.accent)

  Color _colorFor(int? seconds) {
    if (seconds == null || seconds == 0) return _c0;
    if (seconds < 5 * 60)  return _c1;
    if (seconds < 15 * 60) return _c2;
    if (seconds < 30 * 60) return _c3;
    return _c4;
  }

  String _fmt(int? seconds) {
    if (seconds == null || seconds == 0) return 'No reading';
    if (seconds < 60) return '${seconds}s read';
    final m = seconds ~/ 60;
    if (m < 60) return '${m}m read';
    return '${m ~/ 60}h ${m % 60}m read';
  }

  // ── Build week columns for the selected year ────────────────────────────────

  List<List<DateTime?>> _buildWeekColumns() {
    final jan1 = DateTime(_selectedYear, 1, 1);

    // Align start to the Sunday on/before Jan 1.
    // DateTime.weekday: Mon=1 … Sun=7.  Sunday ≡ weekday%7 == 0.
    final daysToSunday = jan1.weekday % 7; // 0 if already Sunday
    final startDate = jan1.subtract(Duration(days: daysToSunday));

    // Last day to show: Dec 31 or today (whichever is earlier)
    final now = DateTime.now();
    final lastDay = _selectedYear < now.year
        ? DateTime(_selectedYear, 12, 31)
        : DateTime(now.year, now.month, now.day);

    final columns = <List<DateTime?>>[];
    var cur = startDate;

    while (!cur.isAfter(lastDay)) {
      final week = <DateTime?>[];
      for (int d = 0; d < 7; d++) {
        final day = cur.add(Duration(days: d));
        // Show the cell only if the day belongs to the selected year
        // and is not in the future
        if (day.year == _selectedYear && !day.isAfter(lastDay)) {
          week.add(day);
        } else {
          week.add(null); // invisible cell (padding)
        }
      }
      columns.add(week);
      cur = cur.add(const Duration(days: 7));
    }
    return columns;
  }

  // ── Month label positions ───────────────────────────────────────────────────

  Map<int, String> _monthLabels(List<List<DateTime?>> columns) {
    const abbr = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final labels = <int, String>{};
    int? lastMonth;
    for (int w = 0; w < columns.length; w++) {
      for (final day in columns[w]) {
        if (day != null && day.month != lastMonth) {
          labels[w] = abbr[day.month];
          lastMonth = day.month;
          break;
        }
      }
    }
    return labels;
  }

  // ── Widget ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const cellSize = 12.0;
    const cellGap  =  3.0;
    const cellStep = cellSize + cellGap; // 15 px per cell
    const dayLabelW = 22.0;

    final columns    = _buildWeekColumns();
    final monthLabels = _monthLabels(columns);
    final now = DateTime.now();

    // Day-of-week labels shown on left (Sun → Sat)
    const dayLabels = ['Sun', '', 'Tue', '', 'Thu', '', 'Sat'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Year selector ────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Visibility(
              visible: _selectedYear > _minYear,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary, size: 20),
                onPressed: () => setState(() => _selectedYear--),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
            Text(
              '$_selectedYear',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            Visibility(
              visible: _selectedYear < now.year,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: IconButton(
                icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
                onPressed: () => setState(() => _selectedYear++),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Scrollable grid ──────────────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day labels (Sun / Tue / Thu / Sat)
              Padding(
                padding: const EdgeInsets.only(top: 18), // align below month labels
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (i) {
                    return SizedBox(
                      height: cellStep,
                      width: dayLabelW,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          dayLabels[i],
                          style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 4),

              // Week columns
              ...List.generate(columns.length, (w) {
                final hasLabel = monthLabels.containsKey(w);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Month label (3-letter)
                    SizedBox(
                      height: 16,
                      width: cellStep,
                      child: hasLabel
                          ? OverflowBox(
                              alignment: Alignment.centerLeft,
                              maxWidth: 40,
                              child: Text(
                                monthLabels[w]!,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 2),
                    // 7 day cells (Sun → Sat)
                    ...List.generate(7, (d) {
                      final day = columns[w][d];
                      if (day == null) {
                        return SizedBox(
                          width: cellStep,
                          height: cellStep,
                        );
                      }
                      final key =
                          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                      final secs = widget.dailyData[key];
                      final isToday = day.year == now.year &&
                          day.month == now.month &&
                          day.day == now.day;

                      return Tooltip(
                        message: '$key  ${_fmt(secs)}',
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          margin: const EdgeInsets.only(
                              bottom: cellGap, right: cellGap),
                          decoration: BoxDecoration(
                            color: _colorFor(secs),
                            borderRadius: BorderRadius.circular(2),
                            border: isToday
                                ? Border.all(
                                    color: AppColors.accent,
                                    width: 1.2,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Legend ───────────────────────────────────────────────────────────
        Row(
          children: [
            const Text('Less ',
                style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
            ...[_c0, _c1, _c2, _c3, _c4].map((c) => Container(
                  width: 11,
                  height: 11,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
            const Text('More',
                style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
            const Spacer(),
            Text(
              '< 5m  5–15m  15–30m  30m+',
              style: TextStyle(
                fontSize: 8,
                color: AppColors.textMuted.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
