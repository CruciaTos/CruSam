import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crusam/core/ai/models/ai_provider.dart';
import 'package:crusam/core/ai/notifier/ai_chat_notifier.dart';
import 'package:crusam/core/ai/services/ollama_service.dart';
import 'package:crusam/core/ai/services/gemini_service.dart';

// =============================================================================
// MINIMALIST DESIGN TOKENS
// =============================================================================

class _K {
  // Backgrounds
  static const bg = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceElevated = Color(0xFF252525);

  // Borders – very subtle
  static const border = Color(0x1AFFFFFF);
  static const borderFocus = Color(0x33FFFFFF);

  // Accent – understated blue-grey
  static const accent = Color(0xFF8AB4F8);
  static const accentMuted = Color(0xFF5F8BCF);

  // Status
  static const online = Color(0xFF66BB6A);
  static const error = Color(0xFFEF5350);

  // Text
  static const textPrimary = Color(0xFFE8EAED);
  static const textSecondary = Color(0xFF9AA0A6);
  static const textMuted = Color(0xFF6B7280);

  // Message bubbles – almost invisible difference
  static const userBubble = Color(0xFF2D2D30);
  static const aiBubble = surface;

  // Radii – consistent 8
  static const r8 = Radius.circular(8);
  static const r12 = Radius.circular(12);
  static const rFull = Radius.circular(999);
}

// =============================================================================
// MAIN SCREEN
// =============================================================================

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  static void showAsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    color: _K.surface,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _K.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const Expanded(child: AiChatScreen()),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  int _editingIndex = -1;
  bool _showSlashCommands = false;
  String _slashQuery = '';
  bool _contextExpanded = false;
  String? _smartSuggestion;

  // ---- NEW: Prevent duplicate dialogs for pending actions ----
  bool _showingPendingDialog = false;

  static const _slashCommands = [
    _SlashCommand('/salary', 'Show salary analysis', Icons.attach_money),
    _SlashCommand('/employees', 'List all employees', Icons.people_outline),
    _SlashCommand('/audit', 'Run audit check', Icons.fact_check_outlined),
    _SlashCommand('/vouchers', 'Show pending vouchers', Icons.receipt_long),
    _SlashCommand('/help', 'What can you help with?', Icons.help_outline),
  ];

  static const _suggestions = {
    'highest paid': 'Who is the highest paid employee?',
    'salary': 'Show salary breakdown for this month',
    'pending': 'Show all pending vouchers',
    'total': 'What is the total salary disbursed?',
    'pf': 'Calculate PF contributions for all employees',
    'esic': 'List ESIC-eligible employees',
  };

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _inputFocus.requestFocus());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _inputController.text;
    if (text.startsWith('/')) {
      setState(() {
        _showSlashCommands = true;
        _slashQuery = text.substring(1).toLowerCase();
        _smartSuggestion = null;
      });
      return;
    }
    String? suggestion;
    final lower = text.toLowerCase();
    if (lower.length >= 3) {
      for (final entry in _suggestions.entries) {
        if (lower.contains(entry.key)) {
          suggestion = entry.value;
          break;
        }
      }
    }
    setState(() {
      _showSlashCommands = false;
      _slashQuery = '';
      _smartSuggestion = suggestion;
    });
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(max,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(max);
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final notifier = AiChatNotifier.instance;
    if (notifier.isLoading) return;
    _inputController.clear();
    setState(() {
      _showSlashCommands = false;
      _smartSuggestion = null;
      _editingIndex = -1;
    });
    _scrollToBottom();

    if (_editingIndex >= 0) {
      await notifier.editAndResend(_editingIndex, text);
    } else {
      await notifier.sendMessage(text);
    }
    _scrollToBottom();
  }

  void _applySlashCommand(_SlashCommand cmd) {
    _inputController.text = cmd.description;
    _inputController.selection =
        TextSelection.fromPosition(TextPosition(offset: cmd.description.length));
    setState(() {
      _showSlashCommands = false;
      _slashQuery = '';
    });
    _inputFocus.requestFocus();
  }

  void _startEdit(int index, String text) {
    setState(() => _editingIndex = index);
    _inputController.text = text;
    _inputController.selection =
        TextSelection.fromPosition(TextPosition(offset: text.length));
    _inputFocus.requestFocus();
  }

  void _cancelEdit() {
    setState(() => _editingIndex = -1);
    _inputController.clear();
    _inputFocus.requestFocus();
  }

  // ---- NEW: Show interactive confirmation dialog when a tool action is pending ----
  void _showPendingActionDialog(BuildContext context, AiChatNotifier notifier) {
    showDialog(
      context: context,
      barrierDismissible: false,  // user must tap a button
      builder: (ctx) => AlertDialog(
        backgroundColor: _K.surface,
        title: const Text('Confirm Action', style: TextStyle(color: _K.textPrimary)),
        content: Text(
          notifier.pendingActionDescription ?? 'Perform this action?',
          style: const TextStyle(color: _K.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.resolvePendingAction(false);
              _showingPendingDialog = false;
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.resolvePendingAction(true);
              _showingPendingDialog = false;
            },
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          _inputFocus.requestFocus();
        },
      },
      child: ListenableBuilder(
        listenable: AiChatNotifier.instance,
        builder: (context, _) {
          final notifier = AiChatNotifier.instance;
          if (notifier.isLoading) _scrollToBottom();

          // ---- Show confirmation dialog when a pending action appears ----
          if (notifier.hasPendingAction && !_showingPendingDialog) {
            _showingPendingDialog = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showPendingActionDialog(context, notifier);
              }
            });
          }
          // -----------------------------------------------------------------

          return Scaffold(
            backgroundColor: _K.bg,
            body: Column(
              children: [
                _ChatHeader(notifier: notifier),
                if (_contextExpanded)
                  _ContextPanel(
                    onToggle: () => setState(() => _contextExpanded = false),
                  ),
                Expanded(
                  child: _MessageList(
                    notifier: notifier,
                    scrollController: _scrollController,
                    onEdit: _startEdit,
                    onDelete: (i) => notifier.deleteMessage(i),
                    onRegenerate: notifier.regenerateLastResponse,
                  ),
                ),
                if (notifier.status == ChatStatus.error)
                  _ErrorBanner(
                    message: notifier.errorMessage ?? 'An error occurred.',
                    onRetry: () {
                      final msgs = notifier.messages;
                      if (msgs.isNotEmpty && msgs.last.isError && msgs.length >= 2) {
                        final userMsg = msgs[msgs.length - 2];
                        if (userMsg.role == ChatRole.user) {
                          notifier.deleteMessage(msgs.length - 1);
                          notifier.sendMessage(userMsg.text);
                        }
                      }
                    },
                    onSwitchModel: () => _showModelPicker(context, notifier),
                  ),
                _InputArea(
                  controller: _inputController,
                  focusNode: _inputFocus,
                  notifier: notifier,
                  isEditing: _editingIndex >= 0,
                  showSlashCommands: _showSlashCommands,
                  slashQuery: _slashQuery,
                  slashCommands: _slashCommands,
                  smartSuggestion: _smartSuggestion,
                  onSend: _sendMessage,
                  onCancel: notifier.isLoading
                      ? notifier.cancelGeneration
                      : _editingIndex >= 0
                          ? _cancelEdit
                          : null,
                  onApplySlash: _applySlashCommand,
                  onApplySuggestion: (s) {
                    _inputController.text = s;
                    _inputController.selection =
                        TextSelection.fromPosition(TextPosition(offset: s.length));
                    setState(() => _smartSuggestion = null);
                    _inputFocus.requestFocus();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showModelPicker(BuildContext context, AiChatNotifier notifier) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ModelPickerSheet(notifier: notifier),
    );
  }
}

// =============================================================================
// HEADER
// =============================================================================

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.notifier});
  final AiChatNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final String phaseLabel;
    final Color phaseColor;

    switch (notifier.chatPhase) {
      case ChatPhase.connecting:
        phaseLabel = 'Connecting…';
        phaseColor = Colors.amber;
        break;
      case ChatPhase.thinking:
        phaseLabel = 'Thinking…';
        phaseColor = _K.accent;
        break;
      case ChatPhase.streaming:
        phaseLabel = 'Generating…';
        phaseColor = _K.online;
        break;
      case ChatPhase.verifying:
        phaseLabel = 'Verifying…';
        phaseColor = _K.accent;
        break;
      case ChatPhase.idle:
        final isLocal = notifier.selectedProvider == AiProvider.ollama;
        phaseLabel = isLocal ? 'Local' : 'Online';
        phaseColor = isLocal ? _K.online : _K.accent;
        break;
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _K.surface,
        border: Border(bottom: BorderSide(color: _K.border)),
      ),
      child: Row(
        children: [
          const Text(
            'CruSam AI',
            style: TextStyle(
              color: _K.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: phaseColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              phaseLabel,
              style: TextStyle(
                color: phaseColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          if (!notifier.isLoading && notifier.hasMessages)
            _HeaderIcon(
              icon: Icons.add_comment_outlined,
              tooltip: 'New conversation',
              onTap: () => _confirmClear(context),
            ),
          _HeaderIcon(
            icon: Icons.tune_outlined,
            tooltip: 'Model settings',
            onTap: () => _showModelPicker(context),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _K.surface,
        title: const Text('Start new conversation?'),
        content: const Text('All current messages will be cleared.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              notifier.clearHistory();
            },
            child: const Text('Clear', style: TextStyle(color: _K.error)),
          ),
        ],
      ),
    );
  }

  void _showModelPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ModelPickerSheet(notifier: notifier),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: _K.textSecondary),
        ),
      ),
    );
  }
}

// =============================================================================
// CONTEXT PANEL
// =============================================================================

class _ContextPanel extends StatelessWidget {
  const _ContextPanel({required this.onToggle});
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: _K.surface,
      child: Row(
        children: [
          const Icon(Icons.circle, size: 6, color: _K.accent),
          const SizedBox(width: 6),
          const Text(
            'Live data loaded',
            style: TextStyle(color: _K.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          InkWell(
            onTap: onToggle,
            child: const Icon(Icons.close, size: 14, color: _K.textMuted),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MESSAGE LIST
// =============================================================================

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.notifier,
    required this.scrollController,
    required this.onEdit,
    required this.onDelete,
    required this.onRegenerate,
  });

  final AiChatNotifier notifier;
  final ScrollController scrollController;
  final void Function(int index, String text) onEdit;
  final void Function(int index) onDelete;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final messages = notifier.messages;
    final pending = notifier.pendingStreamText;
    final isLoading = notifier.isLoading;
    final pendingCount = (pending != null || isLoading) ? 1 : 0;
    final itemCount = messages.length + pendingCount;

    if (itemCount == 0) {
      return _EmptyState(notifier: notifier);
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == messages.length && pendingCount == 1) {
          final txt = pending ?? '';
          if (txt.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 8),
              child: _TypingIndicator(),
            );
          }
          return _MessageBubble(
            message: ChatMessage(
              role: ChatRole.assistant,
              text: txt,
              timestamp: DateTime.now(),
            ),
            index: -1,
            isLast: true,
            onEdit: null,
            onDelete: null,
            onRegenerate: null,
          );
        }

        final msg = messages[index];
        final isLastAssistant = index == messages.length - 1 &&
            msg.role == ChatRole.assistant &&
            !msg.isError;

        return _MessageBubble(
          message: msg,
          index: index,
          isLast: isLastAssistant,
          onEdit: msg.role == ChatRole.user ? () => onEdit(index, msg.text) : null,
          onDelete: () => onDelete(index),
          onRegenerate: isLastAssistant && !isLoading ? onRegenerate : null,
        );
      },
    );
  }
}

// =============================================================================
// MESSAGE BUBBLE – stripped down
// =============================================================================

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.index,
    required this.isLast,
    required this.onEdit,
    required this.onDelete,
    required this.onRegenerate,
  });

  final ChatMessage message;
  final int index;
  final bool isLast;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRegenerate;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _hovered = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == ChatRole.user;
    final bgColor = widget.message.isError
        ? _K.error.withOpacity(0.08)
        : isUser
            ? _K.userBubble
            : _K.aiBubble;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isUser ? 'You' : 'AI',
                  style: const TextStyle(color: _K.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(widget.message.timestamp),
                  style: const TextStyle(color: _K.textMuted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.all(_K.r8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  isUser
                      ? SelectableText(
                          widget.message.text,
                          style: const TextStyle(color: _K.textPrimary, fontSize: 14, height: 1.45),
                        )
                      : _MarkdownView(text: widget.message.text),
                  if (_hovered || widget.isLast)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          _MsgAction(
                            icon: _copied ? Icons.check : Icons.copy_outlined,
                            tooltip: _copied ? 'Copied' : 'Copy',
                            color: _copied ? _K.online : _K.textMuted,
                            onTap: _copyText,
                          ),
                          if (widget.onEdit != null)
                            _MsgAction(
                              icon: Icons.edit_outlined,
                              tooltip: 'Edit',
                              color: _K.textMuted,
                              onTap: widget.onEdit!,
                            ),
                          if (widget.onRegenerate != null)
                            _MsgAction(
                              icon: Icons.refresh,
                              tooltip: 'Regenerate',
                              color: _K.textMuted,
                              onTap: widget.onRegenerate!,
                            ),
                          if (widget.onDelete != null)
                            _MsgAction(
                              icon: Icons.delete_outline,
                              tooltip: 'Delete',
                              color: _K.error.withOpacity(0.7),
                              onTap: widget.onDelete!,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyText() {
    Clipboard.setData(ClipboardData(text: widget.message.text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String _formatTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _MsgAction extends StatelessWidget {
  const _MsgAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

// =============================================================================
// TYPING INDICATOR
// =============================================================================

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _animation = Tween(begin: 0.0, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = ((_animation.value - i * 0.2) % 1.0).clamp(0.0, 1.0);
            final opacity = (0.2 + 0.8 * (0.5 - (t - 0.5).abs() * 2).clamp(0.0, 1.0)).clamp(0.2, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _K.accent.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// =============================================================================
// MARKDOWN
// =============================================================================

class _MarkdownView extends StatelessWidget {
  const _MarkdownView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _parseBlocks(text),
    );
  }

  List<Widget> _parseBlocks(String raw) {
    final result = <Widget>[];
    final codeBlockRx = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
    int cursor = 0;

    for (final match in codeBlockRx.allMatches(raw)) {
      if (match.start > cursor) {
        result.addAll(_parseInlineBlocks(raw.substring(cursor, match.start)));
      }
      result.add(_CodeBlock(code: (match.group(2) ?? '').trimRight(), language: match.group(1) ?? ''));
      cursor = match.end;
    }
    if (cursor < raw.length) {
      result.addAll(_parseInlineBlocks(raw.substring(cursor)));
    }
    return result.isEmpty ? [const SizedBox.shrink()] : result;
  }

  List<Widget> _parseInlineBlocks(String text) {
    final widgets = <Widget>[];
    final lines = text.split('\n');
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 4));
      } else if (line.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(line.substring(4), style: const TextStyle(color: _K.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        ));
      } else if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(line.substring(3), style: const TextStyle(color: _K.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        ));
      } else if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(line.substring(2), style: const TextStyle(color: _K.accent, fontSize: 18, fontWeight: FontWeight.w700)),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(_buildBullet(line.substring(2)));
      } else if (RegExp(r'^\d+\. ').hasMatch(line)) {
        final prefix = RegExp(r'^\d+\. ').stringMatch(line)!;
        widgets.add(_buildNumbered(prefix, line.substring(prefix.length)));
      } else {
        widgets.add(_buildRichLine(line));
      }
      i++;
    }
    return widgets;
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 6),
            child: Icon(Icons.circle, size: 4, color: _K.accent),
          ),
          Expanded(child: _buildRichLine(text)),
        ],
      ),
    );
  }

  Widget _buildNumbered(String prefix, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$prefix ', style: const TextStyle(color: _K.accent, fontSize: 13, fontWeight: FontWeight.w500)),
          Expanded(child: _buildRichLine(text)),
        ],
      ),
    );
  }

  Widget _buildRichLine(String text) {
    return SelectableText.rich(
      TextSpan(children: _parseInlineSpans(text)),
      style: const TextStyle(color: _K.textPrimary, fontSize: 14, height: 1.45),
    );
  }

  List<InlineSpan> _parseInlineSpans(String text) {
    final spans = <InlineSpan>[];
    int i = 0;
    final buf = StringBuffer();

    void flush() {
      if (buf.isNotEmpty) {
        spans.add(TextSpan(text: buf.toString()));
        buf.clear();
      }
    }

    while (i < text.length) {
      if (i + 1 < text.length && text[i] == '*' && text[i + 1] == '*') {
        flush();
        final end = text.indexOf('**', i + 2);
        if (end != -1) {
          spans.add(TextSpan(
            text: text.substring(i + 2, end),
            style: const TextStyle(fontWeight: FontWeight.bold, color: _K.textPrimary),
          ));
          i = end + 2;
          continue;
        }
      }
      if (text[i] == '*' && (i == 0 || text[i - 1] != '*')) {
        final end = text.indexOf('*', i + 1);
        if (end != -1 && end != i + 1) {
          flush();
          spans.add(TextSpan(
            text: text.substring(i + 1, end),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ));
          i = end + 1;
          continue;
        }
      }
      if (text[i] == '`') {
        final end = text.indexOf('`', i + 1);
        if (end != -1) {
          flush();
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: _K.surfaceElevated,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                text.substring(i + 1, end),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: _K.accent),
              ),
            ),
          ));
          i = end + 1;
          continue;
        }
      }
      buf.write(text[i]);
      i++;
    }
    flush();
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }
}

// =============================================================================
// CODE BLOCK
// =============================================================================

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.code, this.language = ''});
  final String code;
  final String language;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: _K.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _K.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: const BoxDecoration(
              color: _K.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Text(
                  widget.language.isEmpty ? 'code' : widget.language,
                  style: const TextStyle(color: _K.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                ),
                const Spacer(),
                InkWell(
                  onTap: _copyCode,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_copied ? Icons.check : Icons.copy_outlined, size: 12, color: _K.textMuted),
                      const SizedBox(width: 4),
                      Text(_copied ? 'Copied' : 'Copy', style: const TextStyle(color: _K.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFDADCE0),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }
}

// =============================================================================
// EMPTY STATE
// =============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.notifier});
  final AiChatNotifier notifier;

  static const _quickActions = [
    ('Who is the highest paid employee?', Icons.bar_chart),
    ('Show salary breakdown for this month', Icons.pie_chart_outline),
    ('List all pending vouchers', Icons.receipt_long_outlined),
    ("Summarise this month's audit status", Icons.fact_check_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'CruSam AI',
              style: TextStyle(
                color: _K.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask me anything about your employees,\npayroll, vouchers, or audit data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _K.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _quickActions.map((qa) {
                return InkWell(
                  onTap: () => notifier.sendMessage(qa.$1),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _K.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _K.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(qa.$2, size: 14, color: _K.accent),
                        const SizedBox(width: 6),
                        Text(qa.$1, style: const TextStyle(color: _K.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'Type / for commands',
              style: TextStyle(color: _K.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ERROR BANNER
// =============================================================================

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onSwitchModel,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSwitchModel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _K.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _K.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _K.error, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(color: _K.error, fontSize: 12)),
          ),
          TextButton(
            onPressed: onSwitchModel,
            child: const Text('Switch', style: TextStyle(color: _K.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INPUT AREA
// =============================================================================

class _InputArea extends StatelessWidget {
  const _InputArea({
    required this.controller,
    required this.focusNode,
    required this.notifier,
    required this.isEditing,
    required this.showSlashCommands,
    required this.slashQuery,
    required this.slashCommands,
    required this.smartSuggestion,
    required this.onSend,
    required this.onCancel,
    required this.onApplySlash,
    required this.onApplySuggestion,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AiChatNotifier notifier;
  final bool isEditing;
  final bool showSlashCommands;
  final String slashQuery;
  final List<_SlashCommand> slashCommands;
  final String? smartSuggestion;
  final VoidCallback onSend;
  final VoidCallback? onCancel;
  final void Function(_SlashCommand) onApplySlash;
  final void Function(String) onApplySuggestion;

  @override
  Widget build(BuildContext context) {
    final filtered = showSlashCommands
        ? slashCommands
            .where((c) =>
                c.command.toLowerCase().contains(slashQuery) ||
                c.description.toLowerCase().contains(slashQuery))
            .toList()
        : <_SlashCommand>[];

    return Container(
      decoration: const BoxDecoration(
        color: _K.surface,
        border: Border(top: BorderSide(color: _K.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSlashCommands && filtered.isNotEmpty)
            _SlashCommandsOverlay(commands: filtered, onTap: onApplySlash),

          if (!showSlashCommands && smartSuggestion != null && !notifier.isLoading)
            GestureDetector(
              onTap: () => onApplySuggestion(smartSuggestion!),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _K.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tips_and_updates_outlined, size: 14, color: _K.accent),
                    const SizedBox(width: 6),
                    Text(smartSuggestion!, style: const TextStyle(color: _K.accent, fontSize: 13)),
                  ],
                ),
              ),
            ),

          if (isEditing)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _K.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 14, color: _K.accent),
                  const SizedBox(width: 6),
                  const Text('Editing', style: TextStyle(color: _K.accent, fontSize: 12)),
                  const Spacer(),
                  if (onCancel != null)
                    InkWell(
                      onTap: onCancel,
                      child: const Text('Cancel', style: TextStyle(color: _K.error, fontSize: 12)),
                    ),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: _K.bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _K.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    enabled: !notifier.isLoading || notifier.isStreaming,
                    style: const TextStyle(color: _K.textPrimary, fontSize: 14, height: 1.4),
                    decoration: const InputDecoration(
                      hintText: 'Message…',
                      hintStyle: TextStyle(color: _K.textMuted, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, right: 2),
                  child: notifier.isLoading
                      ? IconButton(
                          onPressed: onCancel,
                          icon: const Icon(Icons.stop, color: _K.error, size: 22),
                          splashRadius: 18,
                        )
                      : IconButton(
                          onPressed: onSend,
                          icon: const Icon(Icons.arrow_upward, color: _K.accent, size: 22),
                          splashRadius: 18,
                        ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'AI may produce inaccurate information.',
              style: TextStyle(color: _K.textMuted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SLASH COMMANDS OVERLAY
// =============================================================================

class _SlashCommandsOverlay extends StatelessWidget {
  const _SlashCommandsOverlay({
    required this.commands,
    required this.onTap,
  });

  final List<_SlashCommand> commands;
  final void Function(_SlashCommand) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _K.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: commands.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: _K.border),
        itemBuilder: (context, i) {
          final cmd = commands[i];
          return InkWell(
            onTap: () => onTap(cmd),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(cmd.icon, size: 16, color: _K.accent),
                  const SizedBox(width: 10),
                  Text(cmd.command, style: const TextStyle(color: _K.accent, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cmd.description, style: const TextStyle(color: _K.textSecondary, fontSize: 13)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// MODEL PICKER BOTTOM SHEET (simplified)
// =============================================================================

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({required this.notifier});
  final AiChatNotifier notifier;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  String _serverMode = 'local';
  final _remoteUrlCtrl = TextEditingController();
  bool _testing = false;
  _ConnStatus _connStatus = _ConnStatus.idle;

  final _geminiKeyCtrl = TextEditingController();
  bool _geminiKeySaved = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final mode = await OllamaService.instance.getServerMode();
    final remoteUrl = await OllamaService.instance.getRemoteUrl();
    final geminiKey = await GeminiService.instance.getApiKey() ?? '';

    if (mounted) {
      setState(() {
        _serverMode = mode;
        _remoteUrlCtrl.text = remoteUrl;
        _geminiKeyCtrl.text = geminiKey;
      });
    }
  }

  @override
  void dispose() {
    _remoteUrlCtrl.dispose();
    _geminiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _onServerModeChanged(String mode) async {
    setState(() {
      _serverMode = mode;
      _connStatus = _ConnStatus.idle;
    });
    await OllamaService.instance.saveServerMode(mode);
    await widget.notifier.refreshModels();
  }

  Future<void> _testAndSave() async {
    final url = _remoteUrlCtrl.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _testing = true;
      _connStatus = _ConnStatus.idle;
    });

    final ok = await OllamaService.instance.testConnection(url);

    if (ok) {
      await OllamaService.instance.saveRemoteUrl(url);
      await widget.notifier.refreshModels();
    }

    if (mounted) {
      setState(() {
        _testing = false;
        _connStatus = ok ? _ConnStatus.success : _ConnStatus.failure;
      });
    }
  }

  Future<void> _saveGeminiKey() async {
    final key = _geminiKeyCtrl.text.trim();
    if (key.isEmpty) return;
    await GeminiService.instance.saveApiKey(key);
    if (mounted) {
      setState(() => _geminiKeySaved = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _geminiKeySaved = false);
      });
    }
    if (widget.notifier.selectedProvider == AiProvider.gemini) {
      await widget.notifier.refreshModels();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('AI Settings',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),

              // Provider
              _SectionLabel(label: 'Provider', icon: Icons.smart_toy_outlined),
              const SizedBox(height: 8),
              SegmentedButton<AiProvider>(
                segments: AiProvider.values
                    .map((p) => ButtonSegment(
                          value: p,
                          label: Text(p.label),
                          icon: Icon(p == AiProvider.ollama ? Icons.computer_outlined : Icons.cloud_outlined, size: 16),
                        ))
                    .toList(),
                selected: {widget.notifier.selectedProvider},
                onSelectionChanged: (s) => widget.notifier.selectProvider(s.first),
              ),
              const SizedBox(height: 16),

              // Ollama server config
              if (widget.notifier.selectedProvider == AiProvider.ollama) ...[
                _SectionLabel(label: 'Ollama Server', icon: Icons.dns_outlined),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'local', label: Text('Local'), icon: Icon(Icons.laptop_outlined, size: 16)),
                    ButtonSegment(value: 'remote', label: Text('Remote'), icon: Icon(Icons.lan_outlined, size: 16)),
                  ],
                  selected: {_serverMode},
                  onSelectionChanged: (s) => _onServerModeChanged(s.first),
                ),
                const SizedBox(height: 10),
                if (_serverMode == 'remote') ...[
                  TextField(
                    controller: _remoteUrlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'LAN URL',
                      hintText: 'http://192.168.1.5:11434',
                      prefixIcon: const Icon(Icons.link, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (_) => setState(() => _connStatus = _ConnStatus.idle),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _testing ? null : _testAndSave,
                          icon: _testing
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.wifi_find_outlined, size: 16),
                          label: Text(_testing ? 'Testing…' : 'Connect & Save'),
                        ),
                      ),
                    ],
                  ),
                  if (_connStatus == _ConnStatus.success)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Connected!', style: TextStyle(color: Colors.green, fontSize: 12)),
                    ),
                  if (_connStatus == _ConnStatus.failure)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Connection failed. Check URL.', style: TextStyle(color: _K.error, fontSize: 12)),
                    ),
                ],
                const SizedBox(height: 16),
              ],

              // Gemini API key
              if (widget.notifier.selectedProvider == AiProvider.gemini) ...[
                _SectionLabel(label: 'Gemini API Key', icon: Icons.key_outlined),
                const SizedBox(height: 8),
                TextField(
                  controller: _geminiKeyCtrl,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'AIza…',
                    prefixIcon: const Icon(Icons.vpn_key_outlined, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveGeminiKey,
                        icon: Icon(_geminiKeySaved ? Icons.check : Icons.save_outlined, size: 16),
                        label: Text(_geminiKeySaved ? 'Saved!' : 'Save Key'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Model selection
              _SectionLabel(label: 'Model', icon: Icons.model_training_outlined),
              const SizedBox(height: 8),
              if (widget.notifier.isLoadingModels)
                const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
              else if (widget.notifier.availableModels.isEmpty)
                Text(
                  widget.notifier.selectedProvider == AiProvider.ollama
                      ? 'No models found. Run: ollama pull llama3.2:3b'
                      : 'Enter a valid Gemini API key.',
                  style: const TextStyle(color: _K.error, fontSize: 12),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.notifier.availableModels.map((m) {
                    final selected = m.id == widget.notifier.selectedModel;
                    return FilterChip(
                      label: Text(m.label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                      selected: selected,
                      onSelected: (_) {
                        widget.notifier.selectModel(m.id);
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
              TextButton.icon(
                onPressed: widget.notifier.refreshModels,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh models'),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _ConnStatus { idle, success, failure }

// =============================================================================
// UTILS
// =============================================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                )),
      ],
    );
  }
}

// =============================================================================
// DATA CLASS
// =============================================================================

class _SlashCommand {
  const _SlashCommand(this.command, this.description, this.icon);
  final String command;
  final String description;
  final IconData icon;
}