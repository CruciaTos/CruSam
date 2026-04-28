import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crusam/core/ai/notifier/ai_chat_notifier.dart';
import 'package:crusam/core/ai/models/ai_provider.dart';

// =============================================================================
// MAIN SCREEN
// =============================================================================

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  // Controllers & focus
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  // Editing an existing message
  int _editingIndex = -1;

  // Slash-command overlay
  bool _showSlashCommands = false;
  String _slashQuery = '';

  // Context panel
  bool _contextExpanded = false;

  // Blinking cursor for streaming
  bool _showCursor = true;
  Timer? _cursorTimer;

  // Smart suggestion
  String? _smartSuggestion;

  static const _slashCommands = [
    _SlashCommand('/salary', 'Show salary analysis', Icons.attach_money),
    _SlashCommand('/employees', 'List all employees', Icons.people),
    _SlashCommand('/audit', 'Run audit check', Icons.fact_check),
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

    // Blink cursor for streaming indicator.
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (mounted) setState(() => _showCursor = !_showCursor);
    });

    _inputController.addListener(_onInputChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _inputController.text;

    // Slash commands overlay.
    if (text.startsWith('/')) {
      setState(() {
        _showSlashCommands = true;
        _slashQuery = text.substring(1).toLowerCase();
        _smartSuggestion = null;
      });
      return;
    }

    // Smart suggestions.
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
      if (animated) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
    setState(() {
      _showSlashCommands = false;
      _slashQuery = '';
    });
    _inputFocus.requestFocus();
  }

  void _startEdit(int index, String text) {
    setState(() => _editingIndex = index);
    _inputController.text = text;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    _inputFocus.requestFocus();
  }

  void _cancelEdit() {
    setState(() => _editingIndex = -1);
    _inputController.clear();
    _inputFocus.requestFocus();
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // Ctrl+K → focus input.
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          _inputFocus.requestFocus();
        },
      },
      child: ListenableBuilder(
        listenable: AiChatNotifier.instance,
        builder: (context, _) {
          final notifier = AiChatNotifier.instance;

          // Auto-scroll whenever a stream token arrives.
          if (notifier.isLoading) _scrollToBottom();

          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Column(
              children: [
                _ChatHeader(notifier: notifier),
                _ContextPanel(
                  expanded: _contextExpanded,
                  onToggle: () =>
                      setState(() => _contextExpanded = !_contextExpanded),
                ),
                Expanded(
                  child: _MessageList(
                    notifier: notifier,
                    scrollController: _scrollController,
                    showCursor: _showCursor,
                    onEdit: _startEdit,
                    onDelete: (i) => notifier.deleteMessage(i),
                    onRegenerate: () => notifier.regenerateLastResponse(),
                  ),
                ),
                if (notifier.status == ChatStatus.error)
                  _ErrorBanner(
                    message: notifier.errorMessage ?? 'An error occurred.',
                    onRetry: () {
                      final messages = notifier.messages;
                      if (messages.isNotEmpty &&
                          messages.last.isError &&
                          messages.length >= 2) {
                        final userMsg = messages[messages.length - 2];
                        if (userMsg.role == ChatRole.user) {
                          notifier.deleteMessage(messages.length - 1);
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
                    _inputController.selection = TextSelection.fromPosition(
                      TextPosition(offset: s.length),
                    );
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
    final cs = Theme.of(context).colorScheme;
    final isLocal = notifier.selectedProvider == AiProvider.ollama;

    String statusText;
    Color statusColor;
    switch (notifier.chatPhase) {
      case ChatPhase.connecting:
        statusText = 'Connecting…';
        statusColor = Colors.amber;
        break;
      case ChatPhase.thinking:
        statusText = 'Thinking…';
        statusColor = Colors.orangeAccent;
        break;
      case ChatPhase.streaming:
        statusText = 'Generating…';
        statusColor = Colors.greenAccent;
        break;
      case ChatPhase.idle:
        statusText = isLocal ? 'Local' : 'Online';
        statusColor = isLocal ? Colors.greenAccent : Colors.blueAccent;
        break;
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          // Status dot.
          _PulseDot(
            color: statusColor,
            pulse: notifier.isLoading,
          ),
          const SizedBox(width: 10),
          // Title.
          Text(
            'CruSam AI',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          // Provider chip.
          _ProviderChip(provider: notifier.selectedProvider),
          const SizedBox(width: 8),
          // Model chip.
          if (notifier.selectedModel.isNotEmpty)
            _ModelChip(model: notifier.selectedModel),
          const Spacer(),
          // Phase label (only while loading).
          if (notifier.isLoading)
            Text(
              statusText,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          const SizedBox(width: 8),
          // Clear chat.
          if (!notifier.isLoading && notifier.hasMessages)
            Tooltip(
              message: 'Clear conversation',
              child: IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                onPressed: () => _confirmClear(context),
                color: cs.onSurfaceVariant,
              ),
            ),
          // Settings / model picker.
          Tooltip(
            message: 'Switch model',
            child: IconButton(
              icon: const Icon(Icons.tune_outlined, size: 20),
              onPressed: () =>
                  _showModelPicker(context),
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear conversation?'),
        content:
            const Text('All messages will be removed. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              notifier.clearHistory();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showModelPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _ModelPickerSheet(notifier: notifier),
    );
  }
}

// =============================================================================
// CONTEXT PANEL (collapsible placeholder)
// =============================================================================

class _ContextPanel extends StatelessWidget {
  const _ContextPanel({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      constraints: BoxConstraints(maxHeight: expanded ? 120 : 34),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(0.35),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Toggle row.
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.data_usage_outlined,
                      size: 14, color: cs.onSecondaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    'Using current data',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: cs.onSecondaryContainer,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: const [
                  _ContextChip(icon: Icons.people, label: '120 employees'),
                  _ContextChip(icon: Icons.attach_money, label: '₹45,00,000 salary'),
                  _ContextChip(icon: Icons.receipt_long, label: '12 pending vouchers'),
                  _ContextChip(icon: Icons.calendar_today, label: 'April 2026'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSecondaryContainer,
                ),
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
    required this.showCursor,
    required this.onEdit,
    required this.onDelete,
    required this.onRegenerate,
  });

  final AiChatNotifier notifier;
  final ScrollController scrollController;
  final bool showCursor;
  final void Function(int index, String text) onEdit;
  final void Function(int index) onDelete;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final messages = notifier.messages;
    final pending = notifier.pendingStreamText;
    final isLoading = notifier.isLoading;

    // Total item count: messages + optional pending bubble + optional thinking dot.
    final int pendingCount =
        (pending != null || (isLoading && pending == null)) ? 1 : 0;
    final itemCount = messages.length + pendingCount;

    if (itemCount == 0) {
      return _EmptyState(notifier: notifier);
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Pending streaming bubble.
        if (index == messages.length && pendingCount == 1) {
          final txt = pending ?? '';
          if (txt.isEmpty) {
            // Still waiting for first token → show thinking dots.
            return const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 12),
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
            showCursor: true,
            cursorVisible: true, // always visible while streaming
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
          showCursor: false,
          cursorVisible: false,
          onEdit: msg.role == ChatRole.user
              ? () => onEdit(index, msg.text)
              : null,
          onDelete: () => onDelete(index),
          onRegenerate: isLastAssistant && !isLoading ? onRegenerate : null,
        );
      },
    );
  }
}

// =============================================================================
// MESSAGE BUBBLE
// =============================================================================

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.index,
    required this.isLast,
    required this.showCursor,
    required this.cursorVisible,
    required this.onEdit,
    required this.onDelete,
    required this.onRegenerate,
  });

  final ChatMessage message;
  final int index;
  final bool isLast;
  final bool showCursor;
  final bool cursorVisible;
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
    final cs = Theme.of(context).colorScheme;

    final Color bgColor;
    final Color textColor;
    if (widget.message.isError) {
      bgColor = cs.errorContainer;
      textColor = cs.onErrorContainer;
    } else if (isUser) {
      bgColor = cs.primaryContainer;
      textColor = cs.onPrimaryContainer;
    } else {
      bgColor = cs.surfaceContainerHigh;
      textColor = cs.onSurface;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: EdgeInsets.only(
          left: isUser ? 64 : 16,
          right: isUser ? 16 : 64,
          bottom: 10,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Role label.
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                isUser ? 'You' : 'CruSam AI',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            // Bubble.
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Message content.
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: isUser
                        ? SelectableText(
                            widget.message.text,
                            style: TextStyle(color: textColor, height: 1.5),
                          )
                        : _MarkdownView(
                            text: widget.message.text,
                            textColor: textColor,
                            showCursor: widget.showCursor,
                            cursorVisible: widget.cursorVisible,
                          ),
                  ),
                  // Action row (visible on hover or for last message).
                  AnimatedOpacity(
                    opacity: _hovered || widget.isLast ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                      child: Row(
                        mainAxisAlignment: isUser
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          // Timestamp.
                          Text(
                            _formatTime(widget.message.timestamp),
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color:
                                          textColor.withOpacity(0.5),
                                    ),
                          ),
                          const SizedBox(width: 8),
                          // Copy.
                          _MsgAction(
                            icon: _copied
                                ? Icons.check
                                : Icons.copy_all_outlined,
                            tooltip: _copied ? 'Copied!' : 'Copy',
                            color: textColor.withOpacity(0.7),
                            onTap: _copyText,
                          ),
                          // Edit (user only).
                          if (widget.onEdit != null)
                            _MsgAction(
                              icon: Icons.edit_outlined,
                              tooltip: 'Edit & resend',
                              color: textColor.withOpacity(0.7),
                              onTap: widget.onEdit!,
                            ),
                          // Regenerate (last AI only).
                          if (widget.onRegenerate != null)
                            _MsgAction(
                              icon: Icons.refresh_outlined,
                              tooltip: 'Regenerate',
                              color: textColor.withOpacity(0.7),
                              onTap: widget.onRegenerate!,
                            ),
                          // Delete.
                          if (widget.onDelete != null)
                            _MsgAction(
                              icon: Icons.delete_outline,
                              tooltip: 'Delete',
                              color: cs.error.withOpacity(0.7),
                              onTap: widget.onDelete!,
                            ),
                        ],
                      ),
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

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
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
// TYPING INDICATOR (3 animated dots)
// =============================================================================

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final t = (_ctrl.value - i * 0.18).clamp(0.0, 1.0);
              final opacity = (0.3 + 0.7 * (0.5 - (t - 0.5).abs() * 2).clamp(0.0, 1.0));
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color:
                      cs.onSurfaceVariant.withOpacity(opacity.clamp(0.3, 1.0)),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

// =============================================================================
// MARKDOWN RENDERER
// =============================================================================

class _MarkdownView extends StatelessWidget {
  const _MarkdownView({
    required this.text,
    required this.textColor,
    this.showCursor = false,
    this.cursorVisible = false,
  });

  final String text;
  final Color textColor;
  final bool showCursor;
  final bool cursorVisible;

  @override
  Widget build(BuildContext context) {
    final displayText = showCursor
        ? text + (cursorVisible ? '▋' : ' ')
        : text;

    final widgets = _parseBlocks(displayText, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<Widget> _parseBlocks(String raw, BuildContext context) {
    final result = <Widget>[];
    // Split on triple-backtick code blocks.
    final codeBlockRx = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
    int cursor = 0;

    for (final match in codeBlockRx.allMatches(raw)) {
      if (match.start > cursor) {
        result.addAll(_parseInlineBlocks(raw.substring(cursor, match.start), context));
      }
      final lang = match.group(1) ?? '';
      final code = match.group(2) ?? '';
      result.add(_CodeBlock(code: code.trimRight(), language: lang));
      cursor = match.end;
    }

    if (cursor < raw.length) {
      result.addAll(_parseInlineBlocks(raw.substring(cursor), context));
    }

    return result.isEmpty ? [_buildRichLine('', context)] : result;
  }

  List<Widget> _parseInlineBlocks(String text, BuildContext context) {
    final widgets = <Widget>[];
    final lines = text.split('\n');
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];

      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        i++;
        continue;
      }

      // Heading.
      if (line.startsWith('### ')) {
        widgets.add(_buildHeading(line.substring(4), context, 3));
      } else if (line.startsWith('## ')) {
        widgets.add(_buildHeading(line.substring(3), context, 2));
      } else if (line.startsWith('# ')) {
        widgets.add(_buildHeading(line.substring(2), context, 1));
      }
      // Bullet list.
      else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(_buildBullet(line.substring(2), context));
      }
      // Numbered list.
      else if (RegExp(r'^\d+\. ').hasMatch(line)) {
        final prefix = RegExp(r'^\d+\. ').stringMatch(line)!;
        widgets.add(_buildNumbered(prefix, line.substring(prefix.length), context));
      }
      // Normal text.
      else {
        widgets.add(_buildRichLine(line, context));
      }

      i++;
    }

    return widgets;
  }

  Widget _buildHeading(String text, BuildContext context, int level) {
    final sizes = [22.0, 18.0, 15.0];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: sizes[level - 1],
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildBullet(String text, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('  •  ', style: TextStyle(color: textColor, height: 1.5)),
          Expanded(child: _buildRichLine(text, context)),
        ],
      ),
    );
  }

  Widget _buildNumbered(String prefix, String text, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('  $prefix', style: TextStyle(color: textColor, height: 1.5)),
          Expanded(child: _buildRichLine(text, context)),
        ],
      ),
    );
  }

  Widget _buildRichLine(String text, BuildContext context) {
    return SelectableText.rich(
      TextSpan(children: _parseInlineSpans(text)),
      style: TextStyle(color: textColor, height: 1.55),
    );
  }

  List<InlineSpan> _parseInlineSpans(String text) {
    final spans = <InlineSpan>[];
    int i = 0;
    final buf = StringBuffer();

    void flushBuf(TextStyle? extra) {
      if (buf.isNotEmpty) {
        spans.add(TextSpan(text: buf.toString(), style: extra));
        buf.clear();
      }
    }

    while (i < text.length) {
      // Bold: **...**
      if (i + 1 < text.length && text[i] == '*' && text[i + 1] == '*') {
        flushBuf(null);
        final end = text.indexOf('**', i + 2);
        if (end != -1) {
          spans.add(TextSpan(
            text: text.substring(i + 2, end),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ));
          i = end + 2;
          continue;
        }
      }
      // Italic: *...*
      if (text[i] == '*' && (i == 0 || text[i - 1] != '*')) {
        final end = text.indexOf('*', i + 1);
        if (end != -1 && end != i + 1) {
          flushBuf(null);
          spans.add(TextSpan(
            text: text.substring(i + 1, end),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ));
          i = end + 1;
          continue;
        }
      }
      // Inline code: `...`
      if (text[i] == '`') {
        final end = text.indexOf('`', i + 1);
        if (end != -1) {
          flushBuf(null);
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                text.substring(i + 1, end),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                ),
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

    flushBuf(null);
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }
}

// =============================================================================
// CODE BLOCK WIDGET
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top bar with language + copy button.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Text(
                  widget.language.isEmpty ? 'code' : widget.language,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy_outlined,
                          size: 13,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copied' : 'Copy',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code content.
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: Color(0xFFCDD6F4),
                height: 1.6,
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
    ('Who is the highest paid employee?', Icons.bar_chart_outlined),
    ('Show salary breakdown for this month', Icons.pie_chart_outline),
    ('List all pending vouchers', Icons.receipt_long_outlined),
    ('Summarise this month\'s audit status', Icons.fact_check_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, color: cs.onPrimary, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'CruSam AI',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask anything about your employees, payroll,\nvouchers or audit data.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: _quickActions.map((qa) {
                return ActionChip(
                  avatar: Icon(qa.$2, size: 16),
                  label: Text(qa.$1,
                      style: const TextStyle(fontSize: 12.5)),
                  onPressed: () => notifier.sendMessage(qa.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              'Tip: Type / for slash commands · Ctrl+K to focus input',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withOpacity(0.6),
                  ),
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
    final cs = Theme.of(context).colorScheme;

    // Classify error for structured display.
    final String title;
    final IconData icon;
    if (message.toLowerCase().contains('connect') ||
        message.toLowerCase().contains('network') ||
        message.toLowerCase().contains('socket')) {
      title = 'Connection failed';
      icon = Icons.wifi_off_outlined;
    } else if (message.toLowerCase().contains('api key') ||
        message.toLowerCase().contains('no_api_key')) {
      title = 'API key not configured';
      icon = Icons.key_off_outlined;
    } else if (message.toLowerCase().contains('timeout')) {
      title = 'Request timed out';
      icon = Icons.timer_off_outlined;
    } else if (message.toLowerCase().contains('model')) {
      title = 'Model unavailable';
      icon = Icons.model_training_outlined;
    } else {
      title = 'Something went wrong';
      icon = Icons.error_outline;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                Text(message,
                    style: TextStyle(
                        color: cs.onErrorContainer.withOpacity(0.8),
                        fontSize: 11.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text('Retry',
                style: TextStyle(color: cs.onErrorContainer)),
          ),
          TextButton(
            onPressed: onSwitchModel,
            child: Text('Switch model',
                style: TextStyle(color: cs.onErrorContainer)),
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
    final cs = Theme.of(context).colorScheme;

    final filtered = showSlashCommands
        ? slashCommands
            .where((c) =>
                c.command.toLowerCase().contains(slashQuery) ||
                c.description.toLowerCase().contains(slashQuery))
            .toList()
        : <_SlashCommand>[];

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slash command overlay.
          if (showSlashCommands && filtered.isNotEmpty)
            _SlashCommandsOverlay(
              commands: filtered,
              onTap: onApplySlash,
            ),
          // Smart suggestion.
          if (!showSlashCommands &&
              smartSuggestion != null &&
              !notifier.isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: GestureDetector(
                onTap: () => onApplySuggestion(smartSuggestion!),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tips_and_updates_outlined,
                          size: 14, color: cs.onSecondaryContainer),
                      const SizedBox(width: 6),
                      Text(
                        smartSuggestion!,
                        style: TextStyle(
                          color: cs.onSecondaryContainer,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Edit indicator.
          if (isEditing)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('Editing message',
                      style: TextStyle(
                          color: cs.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (onCancel != null)
                    InkWell(
                      onTap: onCancel,
                      child: Text('Cancel',
                          style: TextStyle(color: cs.error, fontSize: 12)),
                    ),
                ],
              ),
            ),
          // Text field row.
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (event) {
                      if (event is KeyDownEvent) {
                        // Enter = send, Shift+Enter = newline.
                        if (event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          onSend();
                        }
                      }
                    },
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: 6,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      enabled: !notifier.isLoading || notifier.isStreaming,
                      decoration: InputDecoration(
                        hintText: notifier.isLoading
                            ? _hintForPhase(notifier.chatPhase)
                            : 'Message CruSam AI…  (Enter to send, Shift+Enter new line)',
                        hintStyle: TextStyle(
                            color: cs.onSurfaceVariant.withOpacity(0.6),
                            fontSize: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                      ),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send / Cancel button.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: notifier.isLoading
                      ? _CircleBtn(
                          key: const ValueKey('stop'),
                          icon: Icons.stop_rounded,
                          color: cs.error,
                          onTap: onCancel ?? () {},
                          tooltip: 'Stop generation',
                        )
                      : _CircleBtn(
                          key: const ValueKey('send'),
                          icon: Icons.send_rounded,
                          color: cs.primary,
                          onTap: onSend,
                          tooltip: isEditing ? 'Send edit' : 'Send (Enter)',
                        ),
                ),
              ],
            ),
          ),
          // Disclaimer.
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'AI may be incorrect · Based on current data · Not a substitute for professional audit advice',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withOpacity(0.45),
                    fontSize: 10,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _hintForPhase(ChatPhase phase) {
    switch (phase) {
      case ChatPhase.connecting:
        return 'Connecting to model…';
      case ChatPhase.thinking:
        return 'Model is thinking…';
      case ChatPhase.streaming:
        return 'Generating response…';
      case ChatPhase.idle:
        return 'Message CruSam AI…';
    }
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
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
    final cs = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: commands.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: cs.outlineVariant),
        itemBuilder: (context, i) {
          final cmd = commands[i];
          return InkWell(
            onTap: () => onTap(cmd),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(cmd.icon, size: 16, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    cmd.command,
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cmd.description,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
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
// MODEL PICKER BOTTOM SHEET
// =============================================================================

class _ModelPickerSheet extends StatelessWidget {
  const _ModelPickerSheet({required this.notifier});
  final AiChatNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI Settings',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              // Provider toggle.
              Text('Provider',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
              const SizedBox(height: 8),
              SegmentedButton<AiProvider>(
                segments: AiProvider.values
                    .map((p) => ButtonSegment(
                          value: p,
                          label: Text(p.label),
                          icon: Icon(
                            p == AiProvider.ollama
                                ? Icons.computer_outlined
                                : Icons.cloud_outlined,
                            size: 16,
                          ),
                        ))
                    .toList(),
                selected: {notifier.selectedProvider},
                onSelectionChanged: (s) => notifier.selectProvider(s.first),
              ),
              const SizedBox(height: 16),
              // Model picker.
              Text('Model',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
              const SizedBox(height: 8),
              if (notifier.isLoadingModels)
                const Center(child: CircularProgressIndicator())
              else if (notifier.availableModels.isEmpty)
                Text(
                  notifier.selectedProvider == AiProvider.ollama
                      ? 'No models found. Run: ollama pull llama3.2:3b'
                      : 'No models available.',
                  style: TextStyle(color: cs.error),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: notifier.availableModels.map((m) {
                    final selected = m.id == notifier.selectedModel;
                    return FilterChip(
                      label: Text(m.label,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.normal)),
                      selected: selected,
                      onSelected: (_) {
                        notifier.selectModel(m.id);
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              // Refresh.
              TextButton.icon(
                onPressed: notifier.refreshModels,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh models'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// SMALL REUSABLE WIDGETS
// =============================================================================

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulse) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.5 + 0.5 * _ctrl.value),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.4 * _ctrl.value),
              blurRadius: 6,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({required this.provider});
  final AiProvider provider;

  @override
  Widget build(BuildContext context) {
    final isLocal = provider == AiProvider.ollama;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isLocal
            ? Colors.greenAccent.withOpacity(0.12)
            : Colors.blueAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLocal
              ? Colors.greenAccent.withOpacity(0.4)
              : Colors.blueAccent.withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLocal ? Icons.computer_outlined : Icons.cloud_outlined,
            size: 11,
            color: isLocal ? Colors.greenAccent : Colors.blueAccent,
          ),
          const SizedBox(width: 4),
          Text(
            provider.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isLocal ? Colors.greenAccent : Colors.blueAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.model});
  final String model;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Trim long model names.
    final display = model.length > 20 ? '${model.substring(0, 20)}…' : model;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        display,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onTertiaryContainer,
          fontFamily: 'monospace',
        ),
      ),
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