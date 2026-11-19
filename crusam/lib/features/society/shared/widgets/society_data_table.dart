import 'package:flutter/material.dart';

class SocietyColumn<T> {
  final String label;
  final Widget Function(T item) cell;
  final double? width;
  final bool numeric;
  final bool sortable;
  final String? tooltip;

  const SocietyColumn({
    required this.label,
    required this.cell,
    this.width,
    this.numeric = false,
    this.sortable = false,
    this.tooltip,
  });
}

class SocietyDataTable<T> extends StatelessWidget {
  final List<SocietyColumn<T>> columns;
  final List<T> rows;
  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int>? onPage;
  final ValueChanged<T>? onRowTap;
  final Set<T>? selection;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool loading;
  final Widget? emptyView;

  const SocietyDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.total,
    this.page = 0,
    this.pageSize = 50,
    this.onPage,
    this.onRowTap,
    this.selection,
    this.onSelectionChanged,
    this.loading = false,
    this.emptyView,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && rows.isEmpty) {
      return Container(
        color: Colors.white,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    if (rows.isEmpty && !loading) {
      return emptyView ??
          Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: const Text('No records found', style: TextStyle(color: Color(0xFF64748B))),
          );
    }

    final totalPages = (total / pageSize).ceil();

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                        headingTextStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                        dataTextStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1E293B),
                        ),
                        headingRowHeight: 40,
                        dataRowMinHeight: 42,
                        dataRowMaxHeight: 48,
                        horizontalMargin: 16,
                        columnSpacing: 24,
                        columns: columns.map((col) {
                          return DataColumn(
                            numeric: col.numeric,
                            tooltip: col.tooltip,
                            label: Text(col.label),
                          );
                        }).toList(),
                        rows: rows.map((item) {
                          final isSelected = selection?.contains(item) ?? false;
                          return DataRow(
                            selected: isSelected,
                            onSelectChanged: onSelectionChanged != null
                                ? (val) {
                                    final set = Set<T>.from(selection ?? {});
                                    if (val == true) {
                                      set.add(item);
                                    } else {
                                      set.remove(item);
                                    }
                                    onSelectionChanged!(set);
                                  }
                                : (onRowTap != null ? (_) => onRowTap!(item) : null),
                            cells: columns.map((col) {
                              return DataCell(
                                SizedBox(
                                  width: col.width,
                                  child: Align(
                                    alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft,
                                    child: col.cell(item),
                                  ),
                                ),
                                onTap: onRowTap != null ? () => onRowTap!(item) : null,
                              );
                            }).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (totalPages > 1 || total > 0)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                color: Color(0xFFF8FAFC),
              ),
              child: Row(
                children: [
                  Text(
                    'Showing ${rows.isEmpty ? 0 : page * pageSize + 1} - ${(page + 1) * pageSize > total ? total : (page + 1) * pageSize} of $total',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: page > 0 && onPage != null ? () => onPage!(page - 1) : null,
                  ),
                  Text(
                    'Page ${page + 1} of ${totalPages < 1 ? 1 : totalPages}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF334155)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: (page + 1) < totalPages && onPage != null ? () => onPage!(page + 1) : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
