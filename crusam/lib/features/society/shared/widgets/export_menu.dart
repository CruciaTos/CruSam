import 'package:flutter/material.dart';

class ExportMenu extends StatelessWidget {
  final Future<void> Function()? onExportPdf;
  final Future<void> Function()? onExportExcel;

  const ExportMenu({
    super.key,
    this.onExportPdf,
    this.onExportExcel,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Export document',
      icon: const Icon(Icons.download_outlined, size: 20, color: Color(0xFF334155)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      onSelected: (val) {
        if (val == 'pdf' && onExportPdf != null) {
          onExportPdf!();
        } else if (val == 'excel' && onExportExcel != null) {
          onExportExcel!();
        }
      },
      itemBuilder: (ctx) => [
        if (onExportPdf != null)
          const PopupMenuItem(
            value: 'pdf',
            child: Row(
              children: [
                Icon(Icons.picture_as_pdf_outlined, size: 18, color: Color(0xFFEF4444)),
                SizedBox(width: 8),
                Text('Export PDF', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        if (onExportExcel != null)
          const PopupMenuItem(
            value: 'excel',
            child: Row(
              children: [
                Icon(Icons.table_view_outlined, size: 18, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text('Export Excel', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }
}
