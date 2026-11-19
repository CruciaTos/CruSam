import 'package:flutter/material.dart';
import 'package:crusam/features/society/core/society_date.dart';
import 'package:crusam/features/society/shared/widgets/society_date_field.dart';

class ReverseDialogResult {
  final String date;
  final String reason;
  final String? reversalKind;

  const ReverseDialogResult({
    required this.date,
    required this.reason,
    this.reversalKind,
  });
}

class ReverseDialog extends StatefulWidget {
  final String documentTitle;
  final bool isReceipt;

  const ReverseDialog({
    super.key,
    required this.documentTitle,
    this.isReceipt = false,
  });

  static Future<ReverseDialogResult?> show(
    BuildContext context, {
    required String documentTitle,
    bool isReceipt = false,
  }) {
    return showDialog<ReverseDialogResult>(
      context: context,
      builder: (_) => ReverseDialog(
        documentTitle: documentTitle,
        isReceipt: isReceipt,
      ),
    );
  }

  @override
  State<ReverseDialog> createState() => _ReverseDialogState();
}

class _ReverseDialogState extends State<ReverseDialog> {
  late String _date;
  final TextEditingController _reasonCtrl = TextEditingController();
  String _reversalKind = 'mistake';
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = todayIso();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Reversal reason is required');
      return;
    }
    if (reason.length > 500) {
      setState(() => _error = 'Reason cannot exceed 500 characters');
      return;
    }

    Navigator.of(context).pop(ReverseDialogResult(
      date: _date,
      reason: reason,
      reversalKind: widget.isReceipt ? _reversalKind : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reverse ${widget.documentTitle}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Reversing will create a mirror journal entry that nets to zero. Posted documents cannot be edited or deleted.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            SocietyDateField(
              label: 'Reversal Date',
              value: _date,
              onChanged: (val) {
                if (val != null) setState(() => _date = val);
              },
            ),
            if (widget.isReceipt) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _reversalKind,
                decoration: const InputDecoration(
                  labelText: 'Reversal Reason Type',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'mistake', child: Text('Entered in Mistake')),
                  DropdownMenuItem(value: 'bounced', child: Text('Cheque / Payment Bounced')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _reversalKind = val);
                },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Reason for Reversal *',
                hintText: 'Enter detailed justification...',
                errorText: _error,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
          ),
          onPressed: _onConfirm,
          child: const Text('Confirm Reversal'),
        ),
      ],
    );
  }
}
