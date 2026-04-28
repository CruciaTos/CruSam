import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ai_provider.dart';
import '../services/ai_service.dart';
import '../services/ollama_service.dart';
import '../services/gemini_service.dart';

// ---------------------------------------------------------------------------
// NEW: Granular loading phases for richer UI feedback.
// ---------------------------------------------------------------------------

/// Describes the fine-grained phase of an AI request so the UI can show
/// meaningful status text instead of a generic spinner.
enum ChatPhase {
  /// Nothing in progress.
  idle,

  /// Opening a connection to the model endpoint.
  connecting,

  /// Waiting for the first token (model is "thinking").
  thinking,

  /// Tokens are actively being streamed into the pending message.
  streaming,
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

enum ChatRole { user, assistant }

enum ChatStatus { idle, loading, error }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
    this.isError = false,
    this.id,
  });

  final ChatRole role;
  final String text;
  final DateTime timestamp;
  final bool isError;

  /// Optional stable identifier – useful for targeting a specific message
  /// in edit / delete operations from the UI.
  final String? id;

  /// Returns a copy of this message with [text] replaced.
  ChatMessage copyWith({String? text}) => ChatMessage(
        role: role,
        text: text ?? this.text,
        timestamp: timestamp,
        isError: isError,
        id: id,
      );
}

class AppContext {
  const AppContext({
    this.employeeCount,
    this.totalSalary,
    this.pendingVouchers,
    this.dashboardSummary,
    this.extra,
  });

  final int? employeeCount;
  final double? totalSalary;
  final int? pendingVouchers;
  final String? dashboardSummary;
  final Map<String, String>? extra;

  String toPromptSection() {
    final lines = <String>['=== Current App Data ==='];
    if (employeeCount != null) lines.add('Total employees: $employeeCount');
    if (totalSalary != null) {
      lines.add('Total salary disbursed: ₹${totalSalary!.toStringAsFixed(2)}');
    }
    if (pendingVouchers != null) lines.add('Pending vouchers: $pendingVouchers');
    if (dashboardSummary != null) lines.add(dashboardSummary!);
    extra?.forEach((k, v) => lines.add('$k: $v'));
    lines.add('========================');
    return lines.join('\n');
  }
}

// ---------------------------------------------------------------------------
// Notifier – provider-aware AI chat state
// ---------------------------------------------------------------------------

class AiChatNotifier extends ChangeNotifier {
  AiChatNotifier._();
  static final AiChatNotifier instance = AiChatNotifier._();

  // ---- Chat messages & UI state ------------------------------------------
  final List<ChatMessage> _messages = [];
  ChatStatus _status = ChatStatus.idle;
  String? _errorMessage;
  bool _panelOpen = false;
  AppContext _context = const AppContext();

  // ---- Provider-aware state -----------------------------------------------
  AiProvider _selectedProvider = AiProvider.ollama;
  String _selectedModel = '';
  List<AiModelInfo> _availableModels = [];
  bool _initializing = true;
  bool _loadingModels = false;

  // ---- NEW: Streaming state -----------------------------------------------

  /// Accumulated text for the message currently being streamed.
  /// `null` when not streaming; `''` while waiting for the first token.
  String? _pendingStreamText;

  /// Fine-grained phase so the UI can show descriptive status text.
  ChatPhase _chatPhase = ChatPhase.idle;

  /// Active stream subscription – used for clean cancellation.
  StreamSubscription<String>? _streamSubscription;

  // ---- Public getters (chat) ----------------------------------------------
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  ChatStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get panelOpen => _panelOpen;
  bool get isLoading => _status == ChatStatus.loading;
  bool get hasMessages => _messages.isNotEmpty;

  // ---- NEW: Streaming getters ---------------------------------------------

  /// The text currently being streamed into the pending AI message.
  /// Non-null only while a response is in flight.
  String? get pendingStreamText => _pendingStreamText;

  /// Whether the notifier is actively receiving streamed tokens.
  bool get isStreaming => _chatPhase == ChatPhase.streaming;

  /// Fine-grained loading phase for richer UI feedback.
  ChatPhase get chatPhase => _chatPhase;

  // ---- Public getters (provider / model) ----------------------------------
  AiProvider get selectedProvider => _selectedProvider;
  String get selectedModel => _selectedModel;
  List<AiModelInfo> get availableModels => List.unmodifiable(_availableModels);
  bool get hasModels => _availableModels.isNotEmpty;
  bool get isInitializing => _initializing;
  bool get isLoadingModels => _loadingModels;

  // ---- Initialization -----------------------------------------------------
  Future<void> initialize() async {
    _initializing = true;
    notifyListeners();

    try {
      _selectedProvider = await AiService.instance.getSelectedProvider();
      await refreshModels();
    } catch (_) {
      _availableModels = [];
      _selectedModel = '';
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  // ---- Provider & model management ----------------------------------------
  Future<void> selectProvider(AiProvider provider) async {
    if (_selectedProvider == provider && !_initializing) return;
    _selectedProvider = provider;
    await AiService.instance.saveSelectedProvider(provider);
    await refreshModels();
    notifyListeners();
  }

  Future<void> refreshModels() async {
    _loadingModels = true;
    notifyListeners();

    try {
      _availableModels =
          await AiService.instance.getAvailableModels(_selectedProvider);

      if (_availableModels.isNotEmpty) {
        final currentValid =
            _availableModels.any((m) => m.id == _selectedModel);
        if (!currentValid || _selectedModel.isEmpty) {
          _selectedModel = _availableModels.first.id;
        }
      } else {
        _selectedModel = '';
        if (_selectedProvider == AiProvider.ollama) {
          _errorMessage =
              'No Ollama models found. Run: ollama pull llama3.2:3b';
        } else {
          _errorMessage = 'No Gemini models available.';
        }
      }
    } catch (e) {
      _availableModels = [];
      _selectedModel = '';
      _errorMessage = 'Failed to load models.';
    } finally {
      _loadingModels = false;
      notifyListeners();
    }
  }

  void selectModel(String modelId) {
    _selectedModel = modelId;
    notifyListeners();
  }

  // ---- Panel controls -----------------------------------------------------
  void openPanel() {
    _panelOpen = true;
    notifyListeners();
  }

  void closePanel() {
    _panelOpen = false;
    notifyListeners();
  }

  void togglePanel() {
    _panelOpen = !_panelOpen;
    notifyListeners();
  }

  // ---- Context injection --------------------------------------------------
  void updateContext(AppContext ctx) {
    _context = ctx;
  }

  // ---- Cancel in‑flight request -------------------------------------------
  void cancelGeneration() {
    if (!isLoading) return;
    // Cancel both the Dart stream subscription and the underlying HTTP client.
    _streamSubscription?.cancel();
    _streamSubscription = null;
    AiService.instance.cancelCurrentRequest(_selectedProvider);

    _pendingStreamText = null;
    _chatPhase = ChatPhase.idle;
    _status = ChatStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  // ---- Messaging ----------------------------------------------------------

  /// Sends [userText] to the AI model using real-time streaming.
  Future<void> sendMessage(String userText) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty || isLoading) return;

    if (_selectedModel.isEmpty) {
      _handleError('No AI model selected. Please select a model first.');
      return;
    }

    _addMessage(ChatMessage(
      role: ChatRole.user,
      text: trimmed,
      timestamp: DateTime.now(),
    ));

    _status = ChatStatus.loading;
    _errorMessage = null;
    _pendingStreamText = ''; // Empty string = waiting for first token.
    _chatPhase = ChatPhase.connecting;
    notifyListeners();

    try {
      final history = _buildValidHistory();

      final stream = AiService.instance.sendMessagesStream(
        provider: _selectedProvider,
        messages: history,
        model: _selectedModel,
        systemPrompt: _buildSystemPrompt(),
      );

      _streamSubscription = stream.listen(
        (token) {
          _pendingStreamText = (_pendingStreamText ?? '') + token;
          _chatPhase = ChatPhase.streaming;
          notifyListeners();
        },
        onDone: () {
          final finalText = _pendingStreamText ?? '';
          _pendingStreamText = null;
          _chatPhase = ChatPhase.idle;
          _status = ChatStatus.idle;

          if (finalText.trim().isNotEmpty) {
            _addMessage(ChatMessage(
              role: ChatRole.assistant,
              text: finalText,
              timestamp: DateTime.now(),
            ));
          } else {
            _handleError('The model returned an empty response.');
          }

          _streamSubscription = null;
          notifyListeners();
        },
        onError: (Object e) {
          _pendingStreamText = null;
          _chatPhase = ChatPhase.idle;
          _streamSubscription = null;

          if (e is OllamaCancelledException || e is GeminiCancelledException) {
            _status = ChatStatus.idle;
          } else {
            String msg = e.toString();
            if (e is OllamaException) msg = e.message;
            if (e is GeminiException) msg = e.message;
            _handleError(msg);
          }
          notifyListeners();
        },
        cancelOnError: true,
      );

      // Transition to "thinking" phase once the stream is set up.
      if (_chatPhase == ChatPhase.connecting) {
        _chatPhase = ChatPhase.thinking;
        notifyListeners();
      }
    } catch (e) {
      _pendingStreamText = null;
      _chatPhase = ChatPhase.idle;
      _streamSubscription = null;

      if (e is OllamaCancelledException || e is GeminiCancelledException) {
        _status = ChatStatus.idle;
      } else {
        String msg = e.toString();
        if (e is OllamaException) msg = e.message;
        if (e is GeminiException) msg = e.message;
        _handleError(msg);
      }
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // NEW: Regenerate / Edit / Delete
  // ---------------------------------------------------------------------------

  /// Removes the last assistant reply and re-sends the last user message,
  /// producing a fresh response.
  Future<void> regenerateLastResponse() async {
    if (isLoading) return;

    // Strip trailing assistant messages.
    while (_messages.isNotEmpty &&
        _messages.last.role == ChatRole.assistant) {
      _messages.removeLast();
    }

    if (_messages.isEmpty || _messages.last.role != ChatRole.user) return;

    final lastUserText = _messages.last.text;
    _messages.removeLast(); // sendMessage will re-add it.
    notifyListeners();

    await sendMessage(lastUserText);
  }

  /// Truncates the history at [messageIndex] (user message) and re-sends
  /// [newText] as the replacement user message.
  ///
  /// Only valid for user messages. No-ops on out-of-bounds or assistant messages.
  Future<void> editAndResend(int messageIndex, String newText) async {
    if (isLoading) return;
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    if (_messages[messageIndex].role != ChatRole.user) return;

    // Remove this message and everything after it.
    _messages.removeRange(messageIndex, _messages.length);
    notifyListeners();

    await sendMessage(newText);
  }

  /// Deletes the message at [index] from the history.
  void deleteMessage(int index) {
    if (index < 0 || index >= _messages.length) return;
    _messages.removeAt(index);
    notifyListeners();
  }

  void clearHistory() {
    cancelGeneration();
    _messages.clear();
    _status = ChatStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  // ---- Private helpers ----------------------------------------------------
  void _addMessage(ChatMessage msg) => _messages.add(msg);

  void _handleError(String message) {
    _errorMessage = message;
    _status = ChatStatus.error;
    _addMessage(ChatMessage(
      role: ChatRole.assistant,
      text: '⚠️ $message',
      timestamp: DateTime.now(),
      isError: true,
    ));
  }

  /// Builds a valid alternating-pair history excluding error messages.
  List<Map<String, String>> _buildValidHistory() {
    // Exclude the user message we just pushed (it's the last one).
    final history = _messages.sublist(0, _messages.length - 1);
    final valid = <ChatMessage>[];
    int i = 0;

    while (i < history.length) {
      final msg = history[i];
      if (msg.role == ChatRole.user && i + 1 < history.length) {
        final next = history[i + 1];
        if (next.role == ChatRole.assistant && !next.isError) {
          valid.add(msg);
          valid.add(next);
          i += 2;
          continue;
        }
      }
      i++;
    }

    // Always include the last message (the user message just added).
    valid.add(_messages.last);

    return valid
        .map((m) => {
              'role': m.role == ChatRole.user ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();
  }

  String _buildSystemPrompt() => '''
You are a personal helpful Auditing assistant for Bharat Boridkar for app named Crusam.
You help him understand employee data, salary details, voucher information, and dashboard metrics and also solve queries given my him.
Be helpful confident and use ₹ for Indian Rupee amounts.
If you don't know something or not sure about any query, say so clearly.

${_context.toPromptSection()}
''';
}