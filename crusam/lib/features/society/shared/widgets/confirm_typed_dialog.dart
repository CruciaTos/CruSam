import 'package:flutter/material.dart';

class ConfirmTypedDialog extends StatefulWidget {
  final String title;
  final String message;
  final String requiredWord;
  final String actionLabel;
  final Color actionColor;

  const ConfirmTypedDialog({
    super.key,
    required this.title,
    required this.message,
    required this.requiredWord,
    this.actionLabel = 'Confirm',
    this.actionColor = const Color(0xFFEF4444),
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String requiredWord,
    String actionLabel = 'Confirm',
    Color actionColor = const Color(0xFFEF4444),
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmTypedDialog(
        title: title,
        message: message,
        requiredWord: requiredWord,
        actionLabel: actionLabel,
        actionColor: actionColor,
      ),
    );
    return result ?? false;
  }

  @override
  State<ConfirmTypedDialog> createState() => _ConfirmTypedDialogState();
}

class _ConfirmTypedDialogState extends State<ConfirmTypedDialog> {
  final TextEditingController _ctrl = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    setState(() {
      _matches = val.trim().toUpperCase() == widget.requiredWord.toUpperCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.message,
              style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 16),
            Text(
              'Type "${widget.requiredWord}" to confirm:',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: widget.requiredWord,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onChanged,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.actionColor,
            foregroundColor: Colors.white,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
