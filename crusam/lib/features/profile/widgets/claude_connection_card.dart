// lib/features/profile/widgets/claude_connection_card.dart
//
// Shows whether CruSam is connected to Claude Desktop, and connects or
// updates it in one click (see ClaudeConnectionService).

import 'package:flutter/material.dart';

import '../../../core/claude/claude_connect_ui.dart';
import '../../../core/claude/claude_connection_service.dart';
import '../../../core/theme/ink_tokens.dart';

typedef _Tok = InkTokens;

class ClaudeConnectionCard extends StatefulWidget {
  const ClaudeConnectionCard({super.key});

  @override
  State<ClaudeConnectionCard> createState() => _ClaudeConnectionCardState();
}

class _ClaudeConnectionCardState extends State<ClaudeConnectionCard> {
  ClaudeConnection? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await ClaudeConnectionService.check();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      debugPrint('ClaudeConnectionCard: $e');
    }
  }

  Future<void> _connect() async {
    await ClaudeConnectUi.connect(context);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final (title, detail, ok) = switch (s) {
      null => ('Checking…', '', false),
      ClaudeConnection(claudeInstalled: false) =>
        ('Claude Desktop not found', 'Install Claude Desktop, sign in, then connect.', false),
      ClaudeConnection(manualSetup: true) =>
        ('Connected', 'Set up by hand in Claude Desktop.', true),
      ClaudeConnection(upToDate: true) =>
        ('Connected', 'Claude can work in CruSam.', true),
      ClaudeConnection(connected: true) =>
        ('Connected', 'Updated for ${s.appVersion}; Claude uses it after its next restart.', true),
      _ => ('Not connected', 'Claude can create invoices, salaries and emails for you.', false),
    };

    Widget? action;
    if (s != null && !s.claudeInstalled) {
      action = _button('Get Claude', ClaudeConnectionService.openDownloadPage);
    } else if (s != null && !s.connected && s.canConnect) {
      action = _button('Connect', _connect);
    }

    return Container(
      decoration: BoxDecoration(
        color: _Tok.surface,
        border: Border.all(color: _Tok.border),
        borderRadius: BorderRadius.circular(_Tok.cRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: _Tok.padH),
            decoration: const BoxDecoration(
              color: _Tok.surfaceAlt,
              border: Border(bottom: BorderSide(color: _Tok.divider)),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(_Tok.cRadius),
                topRight: Radius.circular(_Tok.cRadius),
              ),
            ),
            child: Row(children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _Tok.ink,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text('CLAUDE DESKTOP', style: _Tok.tsCardTitle.copyWith(fontSize: 12)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(_Tok.padV),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ok ? const Color(0xFFD1FAE5) : _Tok.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  ok ? Icons.check_circle_outline : Icons.link,
                  size: 18,
                  color: ok ? const Color(0xFF065F46) : _Tok.inkLight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _Tok.tsBody.copyWith(fontWeight: FontWeight.w600)),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(detail, style: _Tok.tsSmall, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onPressed) => SizedBox(
        height: 34,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: _Tok.ink,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.radius)),
            elevation: 0,
            textStyle: _Tok.tsLabel.copyWith(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          child: Text(label),
        ),
      );
}
