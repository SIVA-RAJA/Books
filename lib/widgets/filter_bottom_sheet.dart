import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../main.dart' show AppColors;

class FilterBottomSheet extends StatefulWidget {
  final String selectedSort;
  final ValueChanged<String> onSortChanged;

  const FilterBottomSheet({
    super.key,
    required this.selectedSort,
    required this.onSortChanged,
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late String _tempSort;

  @override
  void initState() {
    super.initState();
    _tempSort = widget.selectedSort;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Text(
                'Sort By',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sort Options
          ...AppConstants.sortOptions.map((option) {
            final isSelected = _tempSort == option;
            return GestureDetector(
              onTap: () {
                setState(() => _tempSort = option);
                widget.onSortChanged(option);
                Navigator.pop(context);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surface3,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getSortIcon(option),
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textMuted,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      option,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  IconData _getSortIcon(String option) {
    switch (option) {
      case 'Recently Added':
        return Icons.access_time_rounded;
      case 'Title A-Z':
        return Icons.sort_by_alpha_rounded;
      case 'Title Z-A':
        return Icons.sort_by_alpha_rounded;
      case 'Author A-Z':
        return Icons.person_rounded;
      case 'Last Read':
        return Icons.history_rounded;
      default:
        return Icons.sort_rounded;
    }
  }
}
