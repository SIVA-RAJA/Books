import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../main.dart' show AppColors;

class ReadingTrendChart extends StatefulWidget {
  final Map<String, int> dailyData;

  const ReadingTrendChart({super.key, required this.dailyData});

  @override
  State<ReadingTrendChart> createState() => _ReadingTrendChartState();
}

class _ReadingTrendChartState extends State<ReadingTrendChart> {
  String _selectedRange = '7D';

  final List<String> _ranges = [
    '1D', '3D', '5D', '7D', '14D', '30D', 
    '3M', '5M', '7M', '1Y', '2Y', '3Y', '5Y', '10Y', 'ALL'
  ];

  int _getMaxAvailableDays() {
    if (widget.dailyData.isEmpty) return 7;
    DateTime minDate = DateTime.now();
    for (final key in widget.dailyData.keys) {
      final parts = key.split('-');
      if (parts.length == 3) {
        final dt = DateTime(int.tryParse(parts[0]) ?? 2000, int.tryParse(parts[1]) ?? 1, int.tryParse(parts[2]) ?? 1);
        if (dt.isBefore(minDate)) minDate = dt;
      }
    }
    final days = DateTime.now().difference(minDate).inDays + 1;
    return days > 7 ? days : 7;
  }

  @override
  Widget build(BuildContext context) {
    final maxAvailableDays = _getMaxAvailableDays();
    int requestedDays = 7;
    
    if (_selectedRange.endsWith('D')) {
      requestedDays = int.tryParse(_selectedRange.replaceAll('D', '')) ?? 7;
    } else if (_selectedRange == '3M') {
      requestedDays = 90;
    } else if (_selectedRange == '5M') {
      requestedDays = 150;
    } else if (_selectedRange == '7M') {
      requestedDays = 210;
    } else if (_selectedRange == '1Y') {
      requestedDays = 365;
    } else if (_selectedRange == '2Y') {
      requestedDays = 730;
    } else if (_selectedRange == '3Y') {
      requestedDays = 1095;
    } else if (_selectedRange == '5Y') {
      requestedDays = 1825;
    } else if (_selectedRange == '10Y') {
      requestedDays = 3650;
    } else if (_selectedRange == 'ALL') {
      requestedDays = maxAvailableDays;
    }

    final isClamped = requestedDays > maxAvailableDays && _selectedRange != 'ALL';
    final days = isClamped ? maxAvailableDays : requestedDays;
    final now = DateTime.now();
    final List<FlSpot> spots = [];
    double maxY = 10.0; // default min Y

    for (int i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final seconds = widget.dailyData[key] ?? 0;
      final minutes = seconds / 60.0;
      if (minutes > maxY) maxY = minutes;
      
      spots.add(FlSpot((days - 1 - i).toDouble(), minutes));
    }

    maxY = maxY * 1.2;
    double xInterval = (days / 6).ceilToDouble();
    if (xInterval == 0) xInterval = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _ranges.length,
            itemBuilder: (context, index) {
              final range = _ranges[index];
              final isSelected = range == _selectedRange;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(range, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : AppColors.textSecondary)),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface3,
                  side: BorderSide.none,
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onSelected: (val) {
                    if (val) setState(() => _selectedRange = range);
                  },
                ),
              );
            },
          ),
        ),
        if (isClamped)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Showing all available data since you started.',
              style: TextStyle(color: Colors.orange.withValues(alpha: 0.8), fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (days - 1).toDouble() < 0 ? 0 : (days - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(color: AppColors.border, strokeWidth: 1, dashArray: [5, 5]),
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      if (value < 0 || value >= days) return const SizedBox.shrink();
                      final date = now.subtract(Duration(days: days - 1 - value.toInt()));
                      
                      String text;
                      if (days <= 7) {
                        text = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][date.weekday - 1];
                      } else if (days <= 30) {
                        text = '${date.day}/${date.month}';
                      } else if (days <= 365) {
                        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                        text = months[date.month - 1];
                      } else {
                        text = '${date.year}';
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                      );
                    },
                    reservedSize: 24,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value == maxY || value == 0) return const SizedBox.shrink();
                      return Text('${value.toInt()}m', style: const TextStyle(color: AppColors.textMuted, fontSize: 10));
                    },
                    reservedSize: 32,
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: days > 30 ? false : true,
                  color: AppColors.primary,
                  barWidth: days > 60 ? 1.5 : 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.3),
                        AppColors.primary.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => AppColors.surface,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final date = now.subtract(Duration(days: days - 1 - spot.x.toInt()));
                      return LineTooltipItem(
                        '${date.day}/${date.month}/${date.year}\n${spot.y.toInt()} min',
                        const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

