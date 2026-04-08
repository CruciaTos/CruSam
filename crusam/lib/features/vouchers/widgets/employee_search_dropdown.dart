import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../data/models/employee_model.dart';

/// A searchable employee picker.
///
/// Renders a search bar + filtered employee list.
/// [onSelected] fires once with the chosen [EmployeeModel].
/// [selectedId] highlights the active row if already chosen.
class EmployeeSearchDropdown extends StatefulWidget {
  final List<EmployeeModel> employees;
  final String? selectedId;
  final void Function(EmployeeModel) onSelected;

  const EmployeeSearchDropdown({
    super.key,
    required this.employees,
    required this.onSelected,
    this.selectedId,
  });

  @override
  State<EmployeeSearchDropdown> createState() => _EmployeeSearchDropdownState();
}

class _EmployeeSearchDropdownState extends State<EmployeeSearchDropdown> {
  String _query = '';
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<EmployeeModel> get _filtered {
    if (_query.isEmpty) return widget.employees;
    final q = _query.toLowerCase();
    return widget.employees
        .where((e) =>
            e.name.toLowerCase().contains(q) || e.pfNo.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void _onChanged(String value) => setState(() => _query = value);

  void _onClear() {
    _ctrl.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        _SearchBar(
          controller: _ctrl,
          onChanged: _onChanged,
          onClear: _onClear,
          hasText: _query.isNotEmpty,
        ),
        const SizedBox(height: AppSpacing.sm),
        _CountLabel(
          shown: filtered.length,
          total: widget.employees.length,
        ),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: _EmployeeList(
            employees: filtered,
            selectedId: widget.selectedId,
            query: _query,
            onTap: widget.onSelected,
          ),
        ),
      ],
    ),
  );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasText;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hasText,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: true, 
        style: AppTextStyles.input,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search by name or PF number…',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: onClear,
                  tooltip: 'Clear',
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
      );
}

class _CountLabel extends StatelessWidget {
  final int shown;
  final int total;

  const _CountLabel({required this.shown, required this.total});

  @override
  Widget build(BuildContext context) => Text(
        shown == total ? '$total employees' : '$shown of $total matched',
        style: AppTextStyles.small.copyWith(color: AppColors.slate500),
      );
}

class _EmployeeList extends StatelessWidget {
  final List<EmployeeModel> employees;
  final String? selectedId;
  final String query;
  final void Function(EmployeeModel) onTap;

  const _EmployeeList({
    required this.employees,
    required this.selectedId,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) {
      return const _EmptyState();
    }

    return ListView.separated(
      
      itemCount: employees.length,
      separatorBuilder: (_, separatorIndex) =>
          const Divider(height: 1, thickness: 0.5),
      itemBuilder: (_, i) {
        final emp = employees[i];
        final isSelected = emp.id?.toString() == selectedId;

        return _EmployeeTile(
          employee: emp,
          isSelected: isSelected,
          query: query,
          onTap: () => onTap(emp),
        );
      },
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  final EmployeeModel employee;
  final bool isSelected;
  final String query;
  final VoidCallback onTap;

  const _EmployeeTile({
    required this.employee,
    required this.isSelected,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        selected: isSelected,
        selectedTileColor: AppColors.slate50,
        onTap: onTap,
        leading: _Avatar(name: employee.name),
        title: _HighlightText(
          text: employee.name,
          query: query,
          baseStyle: AppTextStyles.body,
        ),
        subtitle: Text(
          employee.zone.isEmpty ? employee.pfNo : '${employee.zone} · ${employee.pfNo}',
          style: AppTextStyles.small.copyWith(color: AppColors.slate500),
        ),
        trailing: _CodeBadge(code: employee.code),
      );
}

class _Avatar extends StatelessWidget {
  final String name;

  const _Avatar({required this.name});

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    return '${parts[0].substring(0, 1)}${parts[1].substring(0, 1)}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.slate100,
        child: Text(
          _initials,
          style: AppTextStyles.small.copyWith(
            color: AppColors.slate700,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _CodeBadge extends StatelessWidget {
  final String code;

  const _CodeBadge({required this.code});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: AppColors.slate100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          code.isEmpty ? '--' : code,
          style: AppTextStyles.small.copyWith(
            color: AppColors.slate700,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}

class _HighlightText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;

  const _HighlightText({
    required this.text,
    required this.query,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: baseStyle);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchStart = lowerText.indexOf(lowerQuery);

    if (matchStart == -1) return Text(text, style: baseStyle);

    final matchEnd = matchStart + query.length;

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          if (matchStart > 0) TextSpan(text: text.substring(0, matchStart)),
          TextSpan(
            text: text.substring(matchStart, matchEnd),
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.slate900,
            ),
          ),
          if (matchEnd < text.length) TextSpan(text: text.substring(matchEnd)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text(
            'No employees found',
            style: AppTextStyles.small.copyWith(color: AppColors.slate400),
          ),
        ),
      );
}