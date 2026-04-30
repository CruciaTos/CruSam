import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../data/models/employee_model.dart';

/// A searchable employee picker that supports keyboard navigation.
///
/// Use this widget inside an overlay/modal.
/// [onSelected] fires once with the chosen [EmployeeModel].
/// [selectedId] highlights the already selected row.
class EmployeeSearchDropdown extends StatefulWidget {
  final List<EmployeeModel> employees;
  final String? selectedId;
  final void Function(EmployeeModel) onSelected;
  final TextEditingController? searchController;
  final bool showSearchBar;

  const EmployeeSearchDropdown({
    super.key,
    required this.employees,
    required this.onSelected,
    this.selectedId,
    this.searchController,
    this.showSearchBar = true,
  });

  @override
  State<EmployeeSearchDropdown> createState() => EmployeeSearchDropdownState();
}

/// Exposed state for keyboard navigation from the parent.
class EmployeeSearchDropdownState extends State<EmployeeSearchDropdown> {
  String _query = '';
  late final TextEditingController _ctrl;
  late final bool _ownsController;

  int _highlightedIndex = -1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ownsController = widget.searchController == null;
    _ctrl = widget.searchController ?? TextEditingController();
    _query = _ctrl.text;
    _ctrl.addListener(_syncQueryWithController);
  }

  void _syncQueryWithController() {
    final nextQuery = _ctrl.text;
    if (nextQuery == _query) return;
    setState(() {
      _query = nextQuery;
      _highlightedIndex = -1; // reset highlight when query changes
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_syncQueryWithController);
    if (_ownsController) {
      _ctrl.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  List<EmployeeModel> get _filtered {
    if (_query.isEmpty) return widget.employees;
    final q = _query.toLowerCase();
    return widget.employees
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            e.pfNo.toLowerCase().contains(q))
        .toList(growable: false);
  }

  void navigateDown() {
    setState(() {
      if (_highlightedIndex < _filtered.length - 1) {
        _highlightedIndex++;
        _scrollToHighlighted();
      }
    });
  }

  void navigateUp() {
    setState(() {
      if (_highlightedIndex > 0) {
        _highlightedIndex--;
        _scrollToHighlighted();
      } else if (_highlightedIndex == 0) {
        _highlightedIndex = -1; // allow going back to no highlight
      }
    });
  }

  void selectHighlighted() {
    if (_highlightedIndex >= 0 && _highlightedIndex < _filtered.length) {
      widget.onSelected(_filtered[_highlightedIndex]);
    } else if (_filtered.isNotEmpty) {
      // select first match if nothing highlighted (mimics old onSubmitted)
      widget.onSelected(_filtered.first);
    }
  }

  void _scrollToHighlighted() {
    if (_highlightedIndex < 0 || _highlightedIndex >= _filtered.length) return;
    final itemHeight = 48.0; // dense ListTile height
    final targetOffset = _highlightedIndex * itemHeight;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final clamped = targetOffset.clamp(0.0, maxScroll);
    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  void _onClear() {
    _ctrl.clear();
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
          if (widget.showSearchBar) ...[
            _SearchBar(
              controller: _ctrl,
              onClear: _onClear,
              hasText: _query.isNotEmpty,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          _CountLabel(
            shown: filtered.length,
            total: widget.employees.length,
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: _EmployeeList(
              employees: filtered,
              selectedId: widget.selectedId,
              highlightedIndex: _highlightedIndex,
              scrollController: _scrollController,
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
  final VoidCallback onClear;
  final bool hasText;

  const _SearchBar({
    required this.controller,
    required this.onClear,
    required this.hasText,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
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
  final int highlightedIndex;
  final ScrollController scrollController;
  final String query;
  final void Function(EmployeeModel) onTap;

  const _EmployeeList({
    required this.employees,
    required this.selectedId,
    required this.highlightedIndex,
    required this.scrollController,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) {
      return const _EmptyState();
    }

    return ListView.separated(
      controller: scrollController,
      itemCount: employees.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5),
      itemBuilder: (_, i) {
        final emp = employees[i];
        final isSelected = emp.id?.toString() == selectedId;
        final isHighlighted = i == highlightedIndex;

        return _EmployeeTile(
          employee: emp,
          isSelected: isSelected,
          isHighlighted: isHighlighted,
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
  final bool isHighlighted;
  final String query;
  final VoidCallback onTap;

  const _EmployeeTile({
    required this.employee,
    required this.isSelected,
    required this.isHighlighted,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Visual feedback for keyboard highlight
    final Color? tileColor;
    if (isHighlighted) {
      tileColor = AppColors.indigo50.withOpacity(0.6);
    } else if (isSelected) {
      tileColor = AppColors.slate50;
    } else {
      tileColor = null;
    }

    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: AppColors.slate50,
      tileColor: tileColor,
      onTap: onTap,
      leading: _Avatar(name: employee.name),
      title: _HighlightText(
        text: employee.name,
        query: query,
        baseStyle: AppTextStyles.body,
      ),
      subtitle: Text(
        employee.zone.isEmpty
            ? employee.pfNo
            : '${employee.zone} · ${employee.pfNo}',
        style: AppTextStyles.small.copyWith(color: AppColors.slate500),
      ),
      trailing: _CodeBadge(code: employee.code),
    );
  }
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
    return '${parts[0].substring(0, 1)}${parts[1].substring(0, 1)}'
        .toUpperCase();
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