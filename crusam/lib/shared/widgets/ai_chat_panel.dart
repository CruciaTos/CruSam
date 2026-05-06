// ============================================================
// ai_chat_panel.dart – final file with batch sync & file context
// ============================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crusam/core/ai/services/file_extraction_service.dart';
import 'package:crusam/core/ai/services/batch_sync_manager.dart'; // ADDED

import 'package:crusam/core/ai/models/ai_provider.dart';
import 'package:crusam/core/ai/notifier/ai_chat_notifier.dart';
import 'package:crusam/core/ai/services/ollama_service.dart';
import 'package:crusam/core/ai/services/gemini_service.dart';

// =============================================================================
// MINIMALIST DESIGN TOKENS
// =============================================================================

class _K {
  static const bg = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const surfaceElevated = Color(0xFF252525);

  static const border = Color(0x1AFFFFFF);
  static const borderFocus = Color(0x33FFFFFF);

  static const accent = Color(0xFF8AB4F8);
  static const accentMuted = Color(0xFF5F8BCF);

  static const online = Color(0xFF66BB6A);
  static const error = Color(0xFFEF5350);

  static const textPrimary = Color(0xFFE8EAED);
  static const textSecondary = Color(0xFF9AA0A6);
  static const textMuted = Color(0xFF6B7280);

  static const userBubble = Color(0xFF2D2D30);
  static const aiBubble = surface;

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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Column(
                children: [
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
  final _picker = ImagePicker();

  int _editingIndex = -1;
  bool _showSlashCommands = false;
  String _slashQuery = '';
  bool _contextExpanded = false;
  String? _smartSuggestion;

  Uint8List? _pendingImageBytes;
  String? _pendingImagePath;

  // ── Pending file (PDF / Excel) ─────────────────────────────────────────
  Uint8List? _pendingFileBytes;
  String? _pendingFileType; // 'pdf' | 'excel'
  String? _pendingFileName;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocus.requestFocus();
      _applyHardcodedModels();
    });
  }

  // ---------------------------------------------------------------
  // Hardcode the models for Local (Ollama) provider
  // ---------------------------------------------------------------
  void _applyHardcodedModels() {
    final notifier = AiChatNotifier.instance;
    if (notifier.selectedProvider == AiProvider.ollama) {
      notifier.selectModel('qwen2.3'); // main chat model
      notifier.setImageProcessingModel(
          'minicpm-v:8b'); // vision model for extraction
      notifier.setAnalysisModel(null); // use the main model for final answer
    }
    // Gemini keeps whatever was selected (or default) – no change.
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
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(max);
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked =
          await _picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _pendingImageBytes = bytes;
          _pendingImagePath = picked.path.split('/').last;
        });
        _inputFocus.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  void _clearPendingImage() {
    setState(() {
      _pendingImageBytes = null;
      _pendingImagePath = null;
    });
  }

  // ── NEW: file picker for PDF / Excel ──────────────────────────────────
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'xlsx', 'xls'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      final name = file.name;
      final ext = name.split('.').last.toLowerCase();
      final type = ext == 'pdf' ? 'pdf' : 'excel';

      // Clear any pending image when a file is picked
      setState(() {
        _pendingImageBytes = null;
        _pendingImagePath = null;
        _pendingFileBytes = bytes;
        _pendingFileType = type;
        _pendingFileName = name;
      });
      _inputFocus.requestFocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e')),
        );
      }
    }
  }

  void _clearPendingFile() {
    setState(() {
      _pendingFileBytes = null;
      _pendingFileType = null;
      _pendingFileName = null;
    });
  }

  // ── Updated sendMessage to include file attachments ────────────────────
  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    final imageBytes = _pendingImageBytes;
    final fileBytes = _pendingFileBytes;
    final fileType = _pendingFileType;
    final fileName = _pendingFileName;

    if (text.isEmpty && imageBytes == null && fileBytes == null) return;

    final notifier = AiChatNotifier.instance;
    if (notifier.isLoading) return;

    _inputController.clear();
    _clearPendingImage();
    _clearPendingFile();
    setState(() {
      _showSlashCommands = false;
      _smartSuggestion = null;
      _editingIndex = -1;
    });
    _scrollToBottom();

    await notifier.sendMessage(
      text,
      imageBytes: imageBytes,
      fileBytes: fileBytes,
      fileType: fileType,
      fileName: fileName,
    );
    _scrollToBottom();
  }

  void _applySlashCommand(_SlashCommand cmd) {
    _inputController.text = cmd.description;
    _inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: cmd.description.length));
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

  void _showPendingActionDialog(BuildContext context, AiChatNotifier notifier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _K.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Confirm Action',
            style: TextStyle(color: _K.textPrimary)),
        content: Text(
          notifier.pendingActionDescription ?? 'Perform this action?',
          style: const TextStyle(color: _K.textSecondary, height: 1.4),
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _K.textPrimary,
                side: const BorderSide(color: _K.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                notifier.resolvePendingAction(false);
                _showingPendingDialog = false;
              },
              child: const Text('No'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _K.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                notifier.resolvePendingAction(true);
                _showingPendingDialog = false;
              },
              child: const Text('Yes'),
            ),
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

          if (notifier.hasPendingAction && !_showingPendingDialog) {
            _showingPendingDialog = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showPendingActionDialog(context, notifier);
              }
            });
          }

          return Scaffold(
            backgroundColor: _K.bg,
            body: Column(
              children: [
                _ChatHeader(notifier: notifier),
                if (_contextExpanded)
                  _ContextPanel(
                    onToggle: () =>
                        setState(() => _contextExpanded = false),
                  ),

                // ── NEW: file context badge ──────────────────────────────────
                if (notifier.hasActiveFileContext &&
                    !notifier.hasBatchSyncActive)
                  FileContextBadge(
                    fileName: notifier.activeFileName ?? 'file',
                    onClear: () => notifier.clearFileContext(),
                  ),

                // ── NEW: batch sync progress bar ────────────────────────────
                if (notifier.hasBatchSyncActive)
                  BatchSyncBar(notifier: notifier),

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
                      if (msgs.isNotEmpty &&
                          msgs.last.isError &&
                          msgs.length >= 2) {
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
                  pendingImageBytes: _pendingImageBytes,
                  pendingImageName: _pendingImagePath,
                  pendingFileType: _pendingFileType,
                  pendingFileName: _pendingFileName,
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
                        TextPosition(offset: s.length));
                    setState(() => _smartSuggestion = null);
                    _inputFocus.requestFocus();
                  },
                  onPickImage: _pickImage,
                  onClearImage: _clearPendingImage,
                  onPickFile: _pickFile,
                  onClearFile: _clearPendingFile,
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
// NEW WIDGET: BATCH SYNC BAR
// =============================================================================

class BatchSyncBar extends StatelessWidget {
  const BatchSyncBar({super.key, required this.notifier});
  final AiChatNotifier notifier;

  static const _accent = Color(0xFF8AB4F8);
  static const _surface = Color(0xFF1E1E1E);
  static const _border = Color(0x1AFFFFFF);
  static const _error = Color(0xFFEF5350);
  static const _textSecondary = Color(0xFF9AA0A6);
  static const _online = Color(0xFF66BB6A);

  @override
  Widget build(BuildContext context) {
    final mgr = BatchSyncManager.instance;
    final prog = mgr.progress;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.08),
        border: const Border(
          top: BorderSide(color: _border),
          bottom: BorderSide(color: _border),
        ),
      ),
      child: Row(
        children: [
          // Sync icon
          const Icon(Icons.sync, size: 14, color: _accent),
          const SizedBox(width: 8),
          // Progress text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Employee Sync — ${prog.processed} done  ·  '
                  '${prog.skipped} skipped  ·  '
                  '${prog.remaining} remaining',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Mini progress bar
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: prog.total == 0
                        ? 0
                        : (prog.processed + prog.skipped) / prog.total,
                    backgroundColor: _border,
                    color: _online,
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Stop button
          GestureDetector(
            onTap: () {
              BatchSyncManager.instance.clear();
              notifier.sendMessage('Sync stopped by user.');
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _error.withOpacity(0.4)),
              ),
              child: const Text(
                'Stop',
                style: TextStyle(
                  color: _error,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// NEW WIDGET: FILE CONTEXT BADGE
// =============================================================================

class FileContextBadge extends StatelessWidget {
  const FileContextBadge({
    super.key,
    required this.fileName,
    required this.onClear,
  });

  final String fileName;
  final VoidCallback onClear;

  static const _accent = Color(0xFF8AB4F8);
  static const _surface = Color(0xFF1E1E1E);
  static const _border = Color(0x1AFFFFFF);
  static const _textSecondary = Color(0xFF9AA0A6);
  static const _textMuted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 12, color: _accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'File loaded: $fileName',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Ask follow-up questions',
            style: TextStyle(color: _textMuted, fontSize: 10),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, size: 12, color: _textMuted),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// HEADER (modified clear to also clear file context)
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
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _K.surface,
        border: Border(bottom: BorderSide(color: _K.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CruSam AI',
                style: TextStyle(
                  color: _K.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (notifier.messages.isNotEmpty)
                Text(
                  '${notifier.messages.length} messages',
                  style: const TextStyle(color: _K.textMuted, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: phaseColor.withAlpha(30),
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
              notifier.clearFileContext(); // ← ADDED
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
  const _HeaderIcon(
      {required this.icon, required this.tooltip, required this.onTap});
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
// CONTEXT PANEL – unchanged
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
            style: TextStyle(
                color: _K.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500),
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
// MESSAGE LIST – unchanged
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
// MESSAGE BUBBLE – unchanged (already handles extraction blocks)
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
  bool _extractedExpanded = false; // toggle for the collapsible section

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == ChatRole.user;
    final bgColor = widget.message.isError
        ? _K.error.withOpacity(0.08)
        : isUser
            ? _K.userBubble
            : _K.aiBubble;

    // Check if this assistant message contains extracted text (image or file)
    final hasExtractedText =
        !isUser && widget.message.text.contains('[EXTRACTED_TEXT]');
    final hasExtractedFile =
        !isUser && widget.message.text.contains('[EXTRACTED_FILE]');
    final hasExtractedBlock = hasExtractedText || hasExtractedFile;
    String displayText = widget.message.text;
    final hasFollowUpChips =
        !isUser && !hasExtractedBlock && _isFollowupQuestion(displayText);
    String? extractedContent;
    if (hasExtractedText) {
      final start = displayText.indexOf('[EXTRACTED_TEXT]');
      final end = displayText.indexOf('[/EXTRACTED_TEXT]');
      if (start != -1 && end != -1 && end > start) {
        // Extract content and remove the markers for the main display
        extractedContent = displayText
            .substring(start + '[EXTRACTED_TEXT]'.length, end)
            .trim();
        // Build a clean display line (short summary, e.g. "Extracted text from image")
        displayText = '🔍 **Image text extracted** (tap to view)  \n' +
            '${extractedContent!.split('\n').take(2).join('\n')}${extractedContent!.split('\n').length > 2 ? '…' : ''}';
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isUser ? 'You' : 'AI',
                  style: const TextStyle(
                      color: _K.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(widget.message.timestamp),
                  style:
                      const TextStyle(color: _K.textMuted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.all(_K.r8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Show extracted file block if present
                  if (hasExtractedFile) ...[
                    _buildExtractedFileBlock(widget.message.text),
                  ] else if (hasExtractedText && extractedContent != null) ...[
                    // Collapsible extracted text section (image)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(() =>
                              _extractedExpanded = !_extractedExpanded),
                          child: Row(
                            children: [
                              const Icon(Icons.article_outlined,
                                  size: 14, color: _K.accent),
                              const SizedBox(width: 6),
                              Text(
                                'Extracted Text from Image',
                                style: const TextStyle(
                                  color: _K.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                _extractedExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 16,
                                color: _K.textMuted,
                              ),
                            ],
                          ),
                        ),
                        if (_extractedExpanded) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _K.bg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _K.border),
                            ),
                            child: SelectableText(
                              extractedContent,
                              style: const TextStyle(
                                color: _K.textPrimary,
                                fontSize: 12,
                                height: 1.4,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                    // Show the answer's main text (the AI's response) after the collapsible block
                    if (!widget.message.text
                        .contains('[EXTRACTED_TEXT]')) ...[
                      // If not an extracted text message, just render normally
                      if (isUser)
                        SelectableText(
                          displayText,
                          style: const TextStyle(
                              color: _K.textPrimary,
                              fontSize: 14,
                              height: 1.45),
                        )
                      else
                        _MarkdownView(text: displayText),
                    ] else ...[
                      // This is the extracted text message; we already displayed the collapsible block.
                      // Show a small note below the collapsible that the answer is being processed.
                      const SizedBox(height: 4),
                      const Text(
                        'The extracted data will be analysed by the AI…',
                        style: TextStyle(
                            color: _K.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic),
                      ),
                    ],
                  ] else if (isUser) ...[
                    SelectableText(
                      displayText,
                      style: const TextStyle(
                          color: _K.textPrimary,
                          fontSize: 14,
                          height: 1.45),
                    ),
                  ] else ...[
                    _MarkdownView(text: displayText),
                  ],
                  if (hasFollowUpChips)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _QuickReplyChip(
                              label: 'Yes',
                              onTap: () => _sendQuickReply('Yes')),
                          _QuickReplyChip(
                              label: 'No',
                              onTap: () => _sendQuickReply('No')),
                          _QuickReplyChip(
                              label: 'Tell me more',
                              onTap: () =>
                                  _sendQuickReply('Tell me more')),
                        ],
                      ),
                    ),
                  if ((_hovered || widget.isLast) &&
                      !hasExtractedText &&
                      !hasExtractedFile)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisAlignment: isUser
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          _MsgAction(
                            icon: _copied
                                ? Icons.check
                                : Icons.copy_outlined,
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

  // ── build extracted file block (PDF/Excel) ───────────────────────
  Widget _buildExtractedFileBlock(String rawText) {
    // Parse the [EXTRACTED_FILE] block
    final start = rawText.indexOf('[EXTRACTED_FILE]');
    final end = rawText.indexOf('[/EXTRACTED_FILE]');
    if (start == -1 || end == -1) {
      return _MarkdownView(text: rawText);
    }

    final inner = rawText
        .substring(start + '[EXTRACTED_FILE]'.length, end)
        .trim();
    final lines = inner.split('\n');

    String fileType = 'File';
    String summary = '';
    final contentLines = <String>[];

    for (final line in lines) {
      if (line.startsWith('type:')) {
        fileType = line.substring(5).trim();
      } else if (line.startsWith('summary:')) {
        summary = line.substring(8).trim();
      } else {
        contentLines.add(line);
      }
    }

    final content = contentLines.join('\n').trim();
    final icon = fileType.toLowerCase() == 'pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.table_chart_outlined;
    final iconColor = fileType.toLowerCase() == 'pdf'
        ? const Color(0xFFEF5350)
        : const Color(0xFF66BB6A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () =>
              setState(() => _extractedExpanded = !_extractedExpanded),
          child: Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  summary.isNotEmpty ? summary : '$fileType extracted',
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                _extractedExpanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 16,
                color: _K.textMuted,
              ),
            ],
          ),
        ),
        if (_extractedExpanded && content.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _K.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _K.border),
            ),
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: const TextStyle(
                  color: _K.textPrimary,
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        const Text(
          'Data has been passed to the AI for analysis…',
          style: TextStyle(
            color: _K.textSecondary,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  void _copyText() {
    Clipboard.setData(ClipboardData(text: widget.message.text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  bool _isFollowupQuestion(String text) {
    final lower = text.toLowerCase();
    final triggers = [
      'would you like',
      'do you want',
      'should i',
      'would you',
      'can i',
      'shall i',
      'ready to',
      'want to',
    ];
    return triggers.any(lower.contains) || text.trim().endsWith('?');
  }

  void _sendQuickReply(String reply) {
    final notifier = AiChatNotifier.instance;
    if (notifier.isLoading) return;
    notifier.sendMessage(reply);
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _QuickReplyChip extends StatelessWidget {
  const _QuickReplyChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _K.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _K.border),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: _K.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500),
        ),
      ),
    );
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
// TYPING INDICATOR – unchanged
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
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
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
            final t =
                ((_animation.value - i * 0.2) % 1.0).clamp(0.0, 1.0);
            final opacity = (0.2 +
                        0.8 *
                            (0.5 - (t - 0.5).abs() * 2)
                                .clamp(0.0, 1.0))
                    .clamp(0.2, 1.0);
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
// MARKDOWN / CODE BLOCKS – unchanged
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
    final codeBlockRx =
        RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
    int cursor = 0;

    for (final match in codeBlockRx.allMatches(raw)) {
      if (match.start > cursor) {
        result.addAll(
            _parseInlineBlocks(raw.substring(cursor, match.start)));
      }
      result.add(_CodeBlock(
          code: (match.group(2) ?? '').trimRight(),
          language: match.group(1) ?? ''));
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
          child: Text(line.substring(4),
              style: const TextStyle(
                  color: _K.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ));
      } else if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(line.substring(3),
              style: const TextStyle(
                  color: _K.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ));
      } else if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(line.substring(2),
              style: const TextStyle(
                  color: _K.accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(_buildBullet(line.substring(2)));
      } else if (RegExp(r'^\d+\. ').hasMatch(line)) {
        final prefix = RegExp(r'^\d+\. ').stringMatch(line)!;
        widgets.add(
            _buildNumbered(prefix, line.substring(prefix.length)));
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
          Text('$prefix ',
              style: const TextStyle(
                  color: _K.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          Expanded(child: _buildRichLine(text)),
        ],
      ),
    );
  }

  Widget _buildRichLine(String text) {
    return SelectableText.rich(
      TextSpan(children: _parseInlineSpans(text)),
      style: const TextStyle(
          color: _K.textPrimary, fontSize: 14, height: 1.45),
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
      if (i + 1 < text.length &&
          text[i] == '*' &&
          text[i + 1] == '*') {
        flush();
        final end = text.indexOf('**', i + 2);
        if (end != -1) {
          spans.add(TextSpan(
            text: text.substring(i + 2, end),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: _K.textPrimary),
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: _K.surfaceElevated,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                text.substring(i + 1, end),
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: _K.accent),
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
// CODE BLOCK – unchanged
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: const BoxDecoration(
              color: _K.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Text(
                  widget.language.isEmpty ? 'code' : widget.language,
                  style: const TextStyle(
                      color: _K.textSecondary,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                ),
                const Spacer(),
                InkWell(
                  onTap: _copyCode,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          _copied
                              ? Icons.check
                              : Icons.copy_outlined,
                          size: 12,
                          color: _K.textMuted),
                      const SizedBox(width: 4),
                      Text(_copied ? 'Copied' : 'Copy',
                          style: const TextStyle(
                              color: _K.textMuted, fontSize: 11)),
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
// EMPTY STATE – unchanged
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
              style: TextStyle(
                  color: _K.textSecondary, fontSize: 14, height: 1.5),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
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
                        Text(qa.$1,
                            style: const TextStyle(
                                color: _K.textSecondary,
                                fontSize: 13)),
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
// ERROR BANNER – unchanged
// =============================================================================

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(
      {required this.message,
      required this.onRetry,
      required this.onSwitchModel});
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
            child: const Text('Retry',
                style: TextStyle(color: _K.error, fontSize: 12)),
          ),
          TextButton(
            onPressed: onSwitchModel,
            child: const Text('Switch',
                style: TextStyle(color: _K.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INPUT AREA (modified hint to reflect batch sync, using correct getter)
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
    this.pendingImageBytes,
    this.pendingImageName,
    this.pendingFileType,
    this.pendingFileName,
    required this.onSend,
    required this.onCancel,
    required this.onApplySlash,
    required this.onApplySuggestion,
    required this.onPickImage,
    required this.onClearImage,
    required this.onPickFile,
    required this.onClearFile,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AiChatNotifier notifier;
  final bool isEditing;
  final bool showSlashCommands;
  final String slashQuery;
  final List<_SlashCommand> slashCommands;
  final String? smartSuggestion;
  final Uint8List? pendingImageBytes;
  final String? pendingImageName;
  final String? pendingFileType;
  final String? pendingFileName;
  final VoidCallback onSend;
  final VoidCallback? onCancel;
  final void Function(_SlashCommand) onApplySlash;
  final void Function(String) onApplySuggestion;
  final void Function(ImageSource source) onPickImage;
  final VoidCallback onClearImage;
  final VoidCallback onPickFile;
  final VoidCallback onClearFile;

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
            _SlashCommandsOverlay(
                commands: filtered, onTap: onApplySlash),

          if (!showSlashCommands &&
              smartSuggestion != null &&
              !notifier.isLoading)
            GestureDetector(
              onTap: () => onApplySuggestion(smartSuggestion!),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _K.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tips_and_updates_outlined,
                        size: 14, color: _K.accent),
                    const SizedBox(width: 6),
                    Text(smartSuggestion!,
                        style: const TextStyle(
                            color: _K.accent, fontSize: 13)),
                  ],
                ),
              ),
            ),

          if (isEditing)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _K.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined,
                      size: 14, color: _K.accent),
                  const SizedBox(width: 6),
                  const Text('Editing',
                      style:
                          TextStyle(color: _K.accent, fontSize: 12)),
                  const Spacer(),
                  if (onCancel != null)
                    InkWell(
                      onTap: onCancel,
                      child: const Text('Cancel',
                          style: TextStyle(
                              color: _K.error, fontSize: 12)),
                    ),
                ],
              ),
            ),

          // ── Image preview ──────────────────────────────────────────────
          if (pendingImageBytes != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _K.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      pendingImageBytes!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pendingImageName ?? 'Image',
                      style: const TextStyle(
                          color: _K.textSecondary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 16, color: _K.textMuted),
                    splashRadius: 14,
                    onPressed: onClearImage,
                  ),
                ],
              ),
            ),

          // ── File preview (PDF / Excel) ─────────────────────────────────
          if (pendingFileType != null && pendingFileName != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _K.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _K.border),
              ),
              child: Row(
                children: [
                  Icon(
                    pendingFileType == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.table_chart_outlined,
                    size: 20,
                    color: pendingFileType == 'pdf'
                        ? const Color(0xFFEF5350)
                        : const Color(0xFF66BB6A),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pendingFileName!,
                          style: const TextStyle(
                            color: _K.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          pendingFileType == 'pdf'
                              ? 'PDF Document'
                              : 'Excel Spreadsheet',
                          style: const TextStyle(
                              color: _K.textMuted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 16, color: _K.textMuted),
                    splashRadius: 14,
                    onPressed: onClearFile,
                  ),
                ],
              ),
            ),

          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: _K.bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _K.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file,
                      color: _K.textSecondary, size: 20),
                  splashRadius: 18,
                  onPressed: () => _showAttachmentSheet(context),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    enabled:
                        !notifier.isLoading || notifier.isStreaming,
                    style: const TextStyle(
                        color: _K.textPrimary,
                        fontSize: 14,
                        height: 1.4),
                    decoration: InputDecoration(
                      // ✅ FIXED: use `hasBatchSyncActive` instead of undefined `isInBatchSync`
                      hintText: notifier.hasBatchSyncActive
                          ? 'Reply Yes / Skip / Stop…'
                          : 'Message…',
                      hintStyle: const TextStyle(
                          color: _K.textMuted, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, right: 2),
                  child: notifier.isLoading
                      ? IconButton(
                          onPressed: onCancel,
                          icon: const Icon(Icons.stop,
                              color: _K.error, size: 22),
                          splashRadius: 18,
                        )
                      : IconButton(
                          onPressed: onSend,
                          icon: const Icon(Icons.arrow_upward,
                              color: _K.accent, size: 22),
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

  void _showAttachmentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _K.surfaceElevated,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: _K.textPrimary),
              title: const Text('Gallery',
                  style: TextStyle(color: _K.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                onPickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: _K.textPrimary),
              title: const Text('Camera',
                  style: TextStyle(color: _K.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                onPickImage(ImageSource.camera);
              },
            ),
            const Divider(height: 1, color: Color(0x1AFFFFFF)),
            ListTile(
              leading: const Icon(
                Icons.picture_as_pdf_outlined,
                color: Color(0xFFEF5350),
              ),
              title: const Text('PDF Document',
                  style: TextStyle(color: _K.textPrimary)),
              subtitle: const Text(
                'Salary statements, invoices, reports',
                style: TextStyle(color: _K.textMuted, fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onPickFile();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.table_chart_outlined,
                color: Color(0xFF66BB6A),
              ),
              title: const Text('Excel Spreadsheet',
                  style: TextStyle(color: _K.textPrimary)),
              subtitle: const Text(
                '.xlsx / .xls files',
                style: TextStyle(color: _K.textMuted, fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onPickFile();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SLASH COMMANDS OVERLAY – unchanged
// =============================================================================

class _SlashCommandsOverlay extends StatelessWidget {
  const _SlashCommandsOverlay(
      {required this.commands, required this.onTap});
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
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: _K.border),
        itemBuilder: (context, i) {
          final cmd = commands[i];
          return InkWell(
            onTap: () => onTap(cmd),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(cmd.icon, size: 16, color: _K.accent),
                  const SizedBox(width: 10),
                  Text(cmd.command,
                      style: const TextStyle(
                          color: _K.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cmd.description,
                        style: const TextStyle(
                            color: _K.textSecondary, fontSize: 13)),
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
// MODEL PICKER BOTTOM SHEET – simplified (no model selection)
// =============================================================================

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({required this.notifier});
  final AiChatNotifier notifier;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  // --- Server / Gemini state ---
  String _serverMode = 'local';
  final _remoteUrlCtrl = TextEditingController();
  bool _testing = false;
  _ConnStatus _connStatus = _ConnStatus.idle;

  final _geminiKeyCtrl = TextEditingController();
  bool _geminiKeySaved = false;
  bool _obscureKey = true;

  // --- Image settings state ---
  bool _imageSettingsExpanded = false;
  int _extractionTimeout = 30;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final mode = await OllamaService.instance.getServerMode();
    final remoteUrl = await OllamaService.instance.getRemoteUrl();
    final geminiKey = await GeminiService.instance.getApiKey() ?? '';

    final imgSettings = widget.notifier.imageSettings;
    _extractionTimeout = imgSettings.extractionTimeoutSeconds;

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
              // Header
              Row(
                children: [
                  const Icon(Icons.tune_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('AI Settings',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),

              // Provider toggle
              _SectionLabel(
                  label: 'Provider', icon: Icons.smart_toy_outlined),
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
                              size: 16),
                        ))
                    .toList(),
                selected: {widget.notifier.selectedProvider},
                onSelectionChanged: (s) {
                  widget.notifier.selectProvider(s.first);
                  // Reapply hardcoded models when switching to Ollama
                  if (s.first == AiProvider.ollama) {
                    widget.notifier.selectModel('qwen2.3');
                    widget.notifier
                        .setImageProcessingModel('minicpm-v:8b');
                    widget.notifier.setAnalysisModel(null);
                  }
                  // For Gemini, the notifier will load its own models
                },
              ),

              // ------------------------------------------------------------------
              // Chat model info (non-editable)
              // ------------------------------------------------------------------
              const SizedBox(height: 12),
              if (widget.notifier.selectedProvider == AiProvider.ollama)
                _ModelInfoLine(
                  icon: Icons.chat_outlined,
                  label: 'Chat model',
                  value: 'qwen2.3',
                )
              else if (widget.notifier.selectedProvider ==
                  AiProvider.gemini)
                _ModelInfoLine(
                  icon: Icons.chat_outlined,
                  label: 'Chat model',
                  value: 'Gemini 1.5 Flash', // adjust as needed
                ),

              const SizedBox(height: 16),

              // Ollama server config
              if (widget.notifier.selectedProvider ==
                  AiProvider.ollama) ...[
                _SectionLabel(
                    label: 'Ollama Server', icon: Icons.dns_outlined),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'local',
                        label: Text('Local'),
                        icon: Icon(Icons.laptop_outlined, size: 16)),
                    ButtonSegment(
                        value: 'remote',
                        label: Text('Remote'),
                        icon: Icon(Icons.lan_outlined, size: 16)),
                  ],
                  selected: {_serverMode},
                  onSelectionChanged: (s) =>
                      _onServerModeChanged(s.first),
                ),
                const SizedBox(height: 10),
                if (_serverMode == 'remote') ...[
                  TextField(
                    controller: _remoteUrlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'LAN URL',
                      hintText: 'http://192.168.1.5:11434',
                      prefixIcon:
                          const Icon(Icons.link, size: 18),
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(8)),
                    ),
                    onChanged: (_) => setState(
                        () => _connStatus = _ConnStatus.idle),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _testing ? null : _testAndSave,
                          icon: _testing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(
                                  Icons.wifi_find_outlined,
                                  size: 16),
                          label: Text(
                              _testing ? 'Testing…' : 'Connect & Save'),
                        ),
                      ),
                    ],
                  ),
                  if (_connStatus == _ConnStatus.success)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Connected!',
                          style: TextStyle(
                              color: Colors.green, fontSize: 12)),
                    ),
                  if (_connStatus == _ConnStatus.failure)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Connection failed. Check URL.',
                          style: TextStyle(
                              color: _K.error, fontSize: 12)),
                    ),
                ],
                const SizedBox(height: 16),
              ],

              // Gemini API key
              if (widget.notifier.selectedProvider ==
                  AiProvider.gemini) ...[
                _SectionLabel(
                    label: 'Gemini API Key', icon: Icons.key_outlined),
                const SizedBox(height: 8),
                TextField(
                  controller: _geminiKeyCtrl,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'AIza…',
                    prefixIcon: const Icon(Icons.vpn_key_outlined,
                        size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18),
                      onPressed: () => setState(
                          () => _obscureKey = !_obscureKey),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveGeminiKey,
                        icon: Icon(
                            _geminiKeySaved
                                ? Icons.check
                                : Icons.save_outlined,
                            size: 16),
                        label: Text(_geminiKeySaved
                            ? 'Saved!'
                            : 'Save Key'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // --- Image Processing Section (simplified, no model pickers) ---
              InkWell(
                onTap: () => setState(() => _imageSettingsExpanded =
                    !_imageSettingsExpanded),
                child: Row(
                  children: [
                    const Icon(Icons.image_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Image Processing',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Icon(_imageSettingsExpanded
                        ? Icons.expand_less
                        : Icons.expand_more),
                  ],
                ),
              ),
              if (_imageSettingsExpanded) ...[
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  title: const Text('Enable image analysis'),
                  subtitle: const Text(
                      'Allow images to be processed by a vision model'),
                  value: widget.notifier.imageSettings.enableImageProcessing,
                  onChanged: (val) {
                    widget.notifier.updateImageSettings(
                      widget.notifier.imageSettings.copyWith(
                          enableImageProcessing: val),
                    );
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),

                // Show fixed models when Ollama is selected
                if (widget.notifier.selectedProvider ==
                    AiProvider.ollama) ...[
                  _ModelInfoLine(
                    icon: Icons.remove_red_eye_outlined,
                    label: 'Vision model',
                    value: 'minicpm-v:8b',
                  ),
                  const SizedBox(height: 8),
                  _ModelInfoLine(
                    icon: Icons.psychology_outlined,
                    label: 'Analysis model',
                    value: 'qwen2.3 (same as chat)',
                  ),
                ],

                // Timeout slider
                ListTile(
                  title: Text(
                      'Extraction timeout ($_extractionTimeout s)'),
                  subtitle: Slider(
                    value: _extractionTimeout.toDouble(),
                    min: 5,
                    max: 60,
                    divisions: 11,
                    label: '$_extractionTimeout s',
                    onChanged: (val) {
                      setState(
                          () => _extractionTimeout = val.toInt());
                      widget.notifier.updateImageSettings(
                        widget.notifier.imageSettings.copyWith(
                            extractionTimeoutSeconds: val.toInt()),
                      );
                    },
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ModelInfoLine extends StatelessWidget {
  const _ModelInfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _K.textSecondary),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(
                color: _K.textSecondary, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                color: _K.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
        Icon(icon,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
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