import 'package:flutter/material.dart';

class SendEmailDialog extends StatefulWidget {
  final String title;
  final String defaultTo;
  final String defaultCc;
  final String defaultSubject;
  final String defaultBody;
  final String attachmentName;
  final Future<void> Function({
    required String to,
    required String cc,
    required String subject,
    required String body,
  }) onSend;

  const SendEmailDialog({
    super.key,
    required this.title,
    this.defaultTo = '',
    this.defaultCc = '',
    required this.defaultSubject,
    this.defaultBody = '',
    required this.attachmentName,
    required this.onSend,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    String defaultTo = '',
    String defaultCc = '',
    required String defaultSubject,
    String defaultBody = '',
    required String attachmentName,
    required Future<void> Function({
      required String to,
      required String cc,
      required String subject,
      required String body,
    }) onSend,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SendEmailDialog(
        title: title,
        defaultTo: defaultTo,
        defaultCc: defaultCc,
        defaultSubject: defaultSubject,
        defaultBody: defaultBody,
        attachmentName: attachmentName,
        onSend: onSend,
      ),
    );
  }

  @override
  State<SendEmailDialog> createState() => _SendEmailDialogState();
}

class _SendEmailDialogState extends State<SendEmailDialog> {
  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;
  bool _sending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(text: widget.defaultTo);
    _ccController = TextEditingController(text: widget.defaultCc);
    _subjectController = TextEditingController(text: widget.defaultSubject);
    _bodyController = TextEditingController(text: widget.defaultBody);
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final to = _toController.text.trim();
    if (to.isEmpty) {
      setState(() => _errorMessage = 'Recipient email address is required');
      return;
    }

    setState(() {
      _sending = true;
      _errorMessage = null;
    });

    try {
      await widget.onSend(
        to: to,
        cc: _ccController.text.trim(),
        subject: _subjectController.text.trim(),
        body: _bodyController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
                  ),
                ),
              ],
              TextField(
                controller: _toController,
                decoration: const InputDecoration(
                  labelText: 'To',
                  hintText: 'member@example.com',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ccController,
                decoration: const InputDecoration(
                  labelText: 'Cc',
                  hintText: 'committee@example.com',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message Body',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.attachmentName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _sending ? null : _handleSend,
          icon: _sending
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_outlined, size: 16),
          label: Text(_sending ? 'Sending...' : 'Send Email'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
