import 'package:flutter/material.dart';
import '../styles.dart';

/// A reusable dropdown filter styled to match the app's arcade theme.
class FilterDropdown<T> extends StatelessWidget {
  final T? value;
  final List<(T?, String)> options;
  final ValueChanged<T?> onChanged;

  const FilterDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentLight,
        border: Border.all(
          color: AppColors.of(context).parchmentBorder,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          icon: Icon(
            Icons.expand_more,
            color: AppColors.of(context).textMid,
            size: 22,
          ),
          dropdownColor: AppColors.of(context).parchment,
          borderRadius: BorderRadius.circular(8),
          alignment: AlignmentDirectional.bottomStart,
          style: PixelText.title(
            size: 16,
            color: AppColors.of(context).textDark,
          ),
          selectedItemBuilder: (context) {
            return options.map((o) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  o.$2,
                  style: PixelText.title(
                    size: 16,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              );
            }).toList();
          },
          items: options.map((option) {
            final (val, label) = option;
            final selected = val == value;
            return DropdownMenuItem<T?>(
              value: val,
              child: Text(
                label,
                style: PixelText.body(
                  size: 16,
                  color: selected
                      ? AppColors.of(context).accent
                      : AppColors.of(context).textDark,
                ),
              ),
            );
          }).toList(),
          onChanged: (val) => onChanged(val),
        ),
      ),
    );
  }
}
