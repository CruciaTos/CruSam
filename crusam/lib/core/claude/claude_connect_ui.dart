// lib/core/claude/claude_connect_ui.dart
//
// The "Connect to Claude" flow, shared by the Profile card and the prompt
// shown once per app version when Claude Desktop is installed but CruSam
// isn't connected to it yet.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router/app_router.dart';
import 'claude_connection_service.dart';

class ClaudeConnectUi {
  ClaudeConnectUi._();

  static const _promptedKey = 'claude_connect_prompted_for';

  /// Called once after start-up. Asks at most once per app version.
  static Future<void> maybePrompt() async {
    try {
      final status = await ClaudeConnectionService.check();
      if (!status.needsAction) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_promptedKey) == status.appVersion) return;
      await prefs.setString(_promptedKey, status.appVersion);

      final ctx = AppRouter.rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final go = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: const Text('Use CruSam with Claude'),
          content: const Text(
              'Claude Desktop can work in CruSam for you: invoices, salaries '
              'and emails, while you watch it happen here.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Connect')),
          ],
        ),
      );
      if (go == true && ctx.mounted) await connect(ctx);
    } catch (e) {
      debugPrint('ClaudeConnectUi.maybePrompt: $e');
    }
  }

  /// Connects, then gets Claude Desktop to load CruSam.
  static Future<void> connect(BuildContext context) async {
    final r = await ClaudeConnectionService.connect();
    if (!context.mounted) return;
    if (!r.ok) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Couldn't connect"),
          content: Text('${r.error ?? 'Something went wrong.'}\n\n'
              'Send Soham a screenshot of this message.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      return;
    }
    final restart = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Connected'),
        content: Text(r.claudeRunning
            ? 'Claude needs to restart once to load CruSam. Any chat you are '
                'typing in Claude will be kept.'
            : 'Open Claude and start a new chat. Try: "Using CruSam, give me '
                'an overview."'),
        actions: [
          if (r.claudeRunning)
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(r.claudeRunning ? 'Restart Claude' : 'Open Claude'),
          ),
        ],
      ),
    );
    if (restart != true) return;
    if (r.claudeRunning) {
      await ClaudeConnectionService.restartClaude();
    } else {
      await ClaudeConnectionService.openClaude();
    }
  }
}
