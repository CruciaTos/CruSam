import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crusam/core/ai/models/ai_image_settings.dart';
import 'package:crusam/core/ai/models/ai_provider.dart';
import 'package:crusam/core/ai/models/app_context.dart';
import 'package:crusam/core/ai/presentation/ai_context_builder.dart';
import 'package:crusam/core/ai/services/ai_service.dart';
import 'package:crusam/core/ai/services/gemini_service.dart';
import 'package:crusam/core/ai/services/ollama_service.dart';
import 'package:crusam/core/ai/tools/ai_tool_executor.dart';
import 'package:crusam/features/master_data/notifiers/employee_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import 'package:crusam/features/vouchers/notifiers/voucher_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChatPhase { idle, connecting, thinking, streaming, verifying }
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
  final String? id;

  ChatMessage copyWith({String? text}) => ChatMessage(
        role: role,
        text: text ?? this.text,
        timestamp: timestamp,
        isError: isError,
        id: id,
      );
}

class AiChatNotifier extends ChangeNotifier {
  AiChatNotifier._();
  static final AiChatNotifier instance = AiChatNotifier._();

  // ---- Chat messages & UI state ------------------------------------------
  final List<ChatMessage> _messages = [];
  ChatStatus _status = ChatStatus.idle;
  String? _errorMessage;
  bool _panelOpen = false;
  AppContext _context = const AppContext();

  // ---- Provider‑aware state -----------------------------------------------
  AiProvider _selectedProvider = AiProvider.ollama;
  String _selectedModel = '';
  List<AiModelInfo> _availableModels = [];
  bool _initializing = true;
  bool _loadingModels = false;

  // ---- Streaming state ----------------------------------------------------
  String? _pendingStreamText;
  ChatPhase _chatPhase = ChatPhase.idle;
  StreamSubscription<String>? _streamSubscription;
  String _lastUserQuery = '';

  // ---- Extraction guard (step 1 of image pipeline) -----------------------
  /// True while the minicpm-v OCR extraction is running (before the main
  /// stream begins).  Used by [cancelGeneration] to abort that phase too.
  bool _isExtracting = false;

  // ---- Image settings (multimodal configuration) --------------------------
  AiImageSettings _imageSettings = AiImageSettings.defaults;

  // ---- Pending action (interactive confirmation) --------------------------
  Completer<bool>? _pendingActionCompleter;
  String? _pendingActionDescription;

  // ---- NEW: Rate limit for image extraction -------------------------------
  DateTime? _lastExtractionTime;
  static const Duration _extractionCooldown = Duration(seconds: 5);

  // ---- Public getters (chat) ----------------------------------------------
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  ChatStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get panelOpen => _panelOpen;
  bool get isLoading => _status == ChatStatus.loading;
  bool get hasMessages => _messages.isNotEmpty;

  // ---- Streaming getters --------------------------------------------------
  String? get pendingStreamText => _pendingStreamText;
  bool get isStreaming => _chatPhase == ChatPhase.streaming;
  ChatPhase get chatPhase => _chatPhase;

  // ---- Pending action getters ---------------------------------------------
  bool get hasPendingAction => _pendingActionCompleter != null;
  String? get pendingActionDescription => _pendingActionDescription;

  // ---- Provider / model getters -------------------------------------------
  AiProvider get selectedProvider => _selectedProvider;
  String get selectedModel => _selectedModel;
  List<AiModelInfo> get availableModels => List.unmodifiable(_availableModels);
  bool get hasModels => _availableModels.isNotEmpty;
  bool get isInitializing => _initializing;
  bool get isLoadingModels => _loadingModels;

  // ---- Image settings getter ----------------------------------------------
  AiImageSettings get imageSettings => _imageSettings;

  // ---- Initialization -----------------------------------------------------
  Future<void> initialize() async {
    _initializing = true;
    notifyListeners();

    try {
      _selectedProvider = await AiService.instance.getSelectedProvider();
      await _loadImageSettings();
      await refreshModels();
    } catch (_) {
      _availableModels = [];
      _selectedModel = '';
      _imageSettings = AiImageSettings.defaults;
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  /// Load image settings from SharedPreferences
  Future<void> _loadImageSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson =
          prefs.getString('ai_image_settings_json') ?? '';
      if (settingsJson.isNotEmpty) {
        final decoded =
            jsonDecode(settingsJson) as Map<String, dynamic>;
        _imageSettings = AiImageSettings.fromMap(decoded);
      } else {
        _imageSettings = AiImageSettings.defaults;
      }
    } catch (_) {
      _imageSettings = AiImageSettings.defaults;
    }
  }

  /// Save image settings to SharedPreferences
  Future<void> _saveImageSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'ai_image_settings_json',
        jsonEncode(_imageSettings.toMap()),
      );
    } catch (_) {
      debugPrint('Failed to save image settings');
    }
  }

  /// Update image processing model
  Future<void> setImageProcessingModel(String modelName) async {
    _imageSettings = _imageSettings.copyWith(
      imageProcessingModel: modelName,
    );
    await _saveImageSettings();
    notifyListeners();
  }

  /// Update analysis model
  Future<void> setAnalysisModel(String? modelName) async {
    _imageSettings = _imageSettings.copyWith(
      analysisModel: modelName,
    );
    await _saveImageSettings();
    notifyListeners();
  }

  /// Convenience to update the entire image settings object at once.
  Future<void> updateImageSettings(AiImageSettings newSettings) async {
    _imageSettings = newSettings;
    await _saveImageSettings();
    notifyListeners();
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
      _errorMessage = 'Failed to load models: ${_friendlyError(e)}';
    } finally {
      _loadingModels = false;
      notifyListeners();
    }
  }

  void selectModel(String modelId) {
    if (_selectedModel == modelId) return;
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

  Future<void> _refreshContext() async {
    final ctx = await AiContextBuilder.build(
      employeeNotifier: EmployeeNotifier.instance,
      salaryStateController: SalaryStateController.instance,
      salaryDataNotifier: SalaryDataNotifier.instance,
      voucherNotifier: VoucherNotifier.instance,
      currentVoucher: VoucherNotifier.instance.current,
    );
    updateContext(ctx);
  }

  // ---- Cancel in‑flight request -------------------------------------------
  void cancelGeneration() {
    if (!isLoading) return;

    // Cancel the main stream subscription (step 2).
    _streamSubscription?.cancel();
    _streamSubscription = null;

    // Cancel the user-selected provider in case step 2 is already running.
    AiService.instance.cancelCurrentRequest(_selectedProvider);

    // Also cancel Ollama if we are still in the extraction phase (step 1).
    // OllamaService is always used for extraction regardless of _selectedProvider.
    if (_isExtracting) {
      OllamaService.instance.cancelCurrentRequest();
      _isExtracting = false;
    }

    _pendingStreamText = null;
    _chatPhase = ChatPhase.idle;
    _status = ChatStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  // ---- Messaging (accepts optional imageBytes) ----------------------------
  Future<void> sendMessage(String userText, {Uint8List? imageBytes}) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty && imageBytes == null) return;
    if (isLoading) return;

    await _refreshContext();

    // ── Image path: guard rails ───────────────────────────────────────────
    if (imageBytes != null) {
      // 1) Toggle check – feature enabled?
      if (!_imageSettings.enableImageProcessing) {
        _handleError('Image processing is disabled in settings. Enable it in the AI settings panel.');
        return;
      }

      // 2) Rate limit – prevent rapid consecutive extractions
      final now = DateTime.now();
      if (_lastExtractionTime != null &&
          now.difference(_lastExtractionTime!) < _extractionCooldown) {
        _handleError('Please wait a few seconds before sending another image.');
        return;
      }

      // 3) Validate the configured vision model is available & vision-capable
      final modelOk = await OllamaService.instance.isVisionModel(
        _imageSettings.imageProcessingModel,
      );
      if (!modelOk) {
        _handleError(
          'The selected vision model "${_imageSettings.imageProcessingModel}" '
          'is not available or not a vision model.\n'
          'Check your Image Processing settings and ensure the model is pulled.',
        );
        return;
      }

      // 4) Ensure a main model is selected for the second step
      if (_selectedModel.isEmpty) {
        _handleError('No main model selected. Please select a model first.');
        return;
      }

      _lastExtractionTime = now;
    }

    // ── Add user message to the chat ──────────────────────────────────────
    final userMessageText = imageBytes != null
        ? (trimmed.isEmpty ? '📎 Image uploaded' : trimmed)
        : trimmed;

    final userMsg = ChatMessage(
      role: ChatRole.user,
      text: userMessageText,
      timestamp: DateTime.now(),
    );
    _addMessage(userMsg);

    _status = ChatStatus.loading;
    _errorMessage = null;
    _pendingStreamText = '';
    _chatPhase = ChatPhase.connecting;
    notifyListeners();

    try {
      final history = _buildValidHistory();

      // ────────────────────────────────────────────────────────────────────
      // IMAGE PROCESSING BRANCH (step-by-step)
      // --------------------------------------------------------------------
      if (imageBytes != null) {
        _isExtracting = true;

        // Show a placeholder while we start extraction
        _pendingStreamText = '🔍 Reading image with ${_imageSettings.imageProcessingModel}…';
        _chatPhase = ChatPhase.thinking;
        notifyListeners();

        // STEP 1: Real‑time streaming extraction from the vision model
        final extractionStream = OllamaService.instance.sendMultimodalExtractionStream(
          model: _imageSettings.imageProcessingModel,
          prompt:
              'Extract all readable text and data from this image. '
              'If the image contains a table, preserve the row and column '
              'structure by separating columns with " | " and each row on '
              'its own line. Include all numbers, names, codes, and headers '
              'exactly as they appear. Do not summarise or add commentary.',
          imageBytes: imageBytes,
          timeout: Duration(seconds: _imageSettings.extractionTimeoutSeconds),
        );

        final extractedBuffer = StringBuffer();
        StreamSubscription<String>? extractionSub;

        try {
          final completer = Completer<void>();
          extractionSub = extractionStream.listen(
            (token) {
              extractedBuffer.write(token);
              // Show live extraction preview in the pending text area
              _pendingStreamText = extractedBuffer.toString();
              notifyListeners();
            },
            onDone: () => completer.complete(),
            onError: (e) => completer.completeError(e),
            cancelOnError: true,
          );
          await completer.future;
        } on OllamaCancelledException {
          // Cancelled by user – bail out cleanly
          _isExtracting = false;
          _pendingStreamText = null;
          _chatPhase = ChatPhase.idle;
          _status = ChatStatus.idle;
          notifyListeners();
          return;
        } on OllamaException catch (e) {
          _isExtracting = false;
          _pendingStreamText = null;
          _chatPhase = ChatPhase.idle;
          final errorMsg =
              '❌ Image processing failed: ${e.message}\n\n'
              'Configured model: ${_imageSettings.imageProcessingModel}';
          _handleError(errorMsg);
          return;
        } finally {
          extractionSub?.cancel();
        }

        _isExtracting = false;
        final rawText = extractedBuffer.toString().trim();

        if (rawText.isEmpty) {
          _handleError('The vision model did not extract any text from the image.');
          return;
        }

        // ---- Add an "Extracted Text" preview message (collapsible in UI) ----
        _addMessage(ChatMessage(
          role: ChatRole.assistant,
          text: '[EXTRACTED_TEXT]\n$rawText\n[/EXTRACTED_TEXT]',
          timestamp: DateTime.now(),
        ));

        // ---- Prepare for step 2 ----
        final userQuestion = trimmed.isEmpty
            ? 'Please summarise the key data shown in this image.'
            : trimmed;
        final analysisModel = _imageSettings.analysisModel ?? _selectedModel;
        _pendingStreamText = '💬 Passing data to $analysisModel…';
        _chatPhase = ChatPhase.connecting;
        notifyListeners();

        // Create the message for the analysis model
        final analysisPrompt = '''
[IMAGE DATA — text extracted from the uploaded image by vision model]
$rawText
[END IMAGE DATA]

Using the image data above, please answer this question: $userQuestion
''';

        // Use the normal streaming pathway for the final answer
        await _startStreamingAnswer(
          messages: [
            {'role': 'user', 'content': analysisPrompt}
          ],
          model: analysisModel,
        );
      } else {
        // --- Normal text‑only stream ---
        await _startStreamingAnswer(
          messages: history,
          model: _selectedModel,
        );
      }
    } catch (e) {
      _pendingStreamText = null;
      _chatPhase = ChatPhase.idle;
      _streamSubscription = null;
      _isExtracting = false;

      if (e is OllamaCancelledException || e is GeminiCancelledException) {
        _status = ChatStatus.idle;
      } else {
        _handleError(_friendlyError(e));
      }
      notifyListeners();
    }
  }

  // ---- Helper to start the final streaming response -----------------------
  Future<void> _startStreamingAnswer({
    required List<Map<String, String>> messages,
    required String model,
  }) async {
    // Cancel any previous stream
    _streamSubscription?.cancel();

    final stream = AiService.instance.sendMessagesStream(
      provider: _selectedProvider,
      messages: messages,
      model: model,
      systemPrompt: _buildSystemPrompt(),
    );

    _chatPhase = ChatPhase.thinking;
    notifyListeners();

    _streamSubscription = stream.listen(
      (token) {
        _pendingStreamText = (_pendingStreamText ?? '') + token;
        if (_chatPhase != ChatPhase.streaming) {
          _chatPhase = ChatPhase.streaming;
        }
        notifyListeners();
      },
      onDone: () async {
        final rawStreamText = _pendingStreamText ?? '';
        _pendingStreamText = null;
        _streamSubscription = null;

        if (rawStreamText.trim().isEmpty) {
          _chatPhase = ChatPhase.idle;
          _status = ChatStatus.idle;
          _handleError('The model returned an empty response.');
          notifyListeners();
          return;
        }

        final sanitized = _sanitizeAssistantOutput(
          AiToolExecutor.stripActionBlock(rawStreamText),
        );

        _chatPhase = ChatPhase.verifying;
        notifyListeners();

        final verifiedText = await _verifyResponse(
          userQuery: _lastUserQuery,
          modelResponse: sanitized,
        );

        _chatPhase = ChatPhase.idle;
        _status = ChatStatus.idle;

        _addMessage(ChatMessage(
          role: ChatRole.assistant,
          text: verifiedText,
          timestamp: DateTime.now(),
        ));

        // Execute any tool actions (single or batch).
        await _executeToolFromAssistantResponse(rawStreamText);

        notifyListeners();
      },
      onError: (Object e) {
        _pendingStreamText = null;
        _chatPhase = ChatPhase.idle;
        _streamSubscription = null;

        if (e is OllamaCancelledException || e is GeminiCancelledException) {
          _status = ChatStatus.idle;
        } else {
          _handleError(_friendlyError(e));
        }
        notifyListeners();
      },
      cancelOnError: true,
    );
  }

  // ---- Tool execution from assistant response (now handles batch actions) ---
  Future<void> _executeToolFromAssistantResponse(String assistantText) async {
    final actionJsons = AiToolExecutor.extractAllActionJsons(assistantText);
    if (actionJsons.isEmpty) return;

    final description = actionJsons.length == 1
        ? _buildSingleActionDescription(actionJsons.first)
        : 'Add ${actionJsons.length} voucher rows?';

    _pendingActionCompleter = Completer<bool>();
    _pendingActionDescription = description;
    notifyListeners();

    try {
      final confirmed = await _pendingActionCompleter!.future;

      if (confirmed) {
        final result = await AiToolExecutor.instance.executeBatch(
          actionJsons,
          employeeNotifier: EmployeeNotifier.instance,
          voucherNotifier: VoucherNotifier.instance,
        );

        if (result is AiToolSuccess) {
          _addMessage(ChatMessage(
            role: ChatRole.assistant,
            text: result.confirmation,
            timestamp: DateTime.now(),
          ));
        } else if (result is AiToolFailure) {
          _addMessage(ChatMessage(
            role: ChatRole.assistant,
            text: '⚠️ Actions failed: ${result.reason}',
            timestamp: DateTime.now(),
            isError: true,
          ));
        }
      } else {
        _addMessage(ChatMessage(
          role: ChatRole.assistant,
          text: 'Action cancelled.',
          timestamp: DateTime.now(),
        ));
      }
    } finally {
      _pendingActionCompleter = null;
      _pendingActionDescription = null;
      notifyListeners();
    }
  }

  String _buildSingleActionDescription(String json) {
    try {
      final action = jsonDecode(json) as Map<String, dynamic>;
      return _buildActionDescription(action);
    } catch (_) {
      return 'Perform this action?';
    }
  }

  void resolvePendingAction(bool confirmed) {
    final completer = _pendingActionCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(confirmed);
    }
  }

  String _buildActionDescription(Map<String, dynamic> actionJson) {
    final action = actionJson['action'] as String?;
    if (action == null) return 'Perform action?';
    switch (action) {
      case 'delete_employee':
        return 'Delete employee with ID ${actionJson['employeeId']}?';
      case 'update_employee':
        return 'Update employee with ID ${actionJson['employeeId']}?';
      case 'add_employee':
        return 'Add employee "${actionJson['name'] ?? 'new'}"?';
      case 'set_company_filter':
        return 'Set company filter to "${actionJson['code']}"?';
      case 'set_company_config':
        return 'Update company config field "${actionJson['field'] ?? actionJson.keys.where((k) => k != "action").join(", ")}"?';
      case 'approve_voucher':
        return 'Approve and save the current voucher?';
      case 'set_month_year':
        return 'Set month to ${actionJson['month']} ${actionJson['year']}?';
      case 'set_days_present':
        return 'Set days present for employee ${actionJson['employeeId']} to ${actionJson['days']}?';
      case 'set_salary_meta':
        return 'Change salary meta field "${actionJson['field']}"?';
      case 'set_voucher_field':
        return 'Change voucher field "${actionJson['field']}"?';
      case 'add_voucher_row':
        return 'Add voucher row for ${actionJson['employeeName'] ?? 'employee'} (₹${actionJson['amount'] ?? '?'})?';
      default:
        return 'Perform action: $action';
    }
  }

  // ---- Regenerate / Edit / Delete -----------------------------------------
  Future<void> regenerateLastResponse() async {
    if (isLoading) return;

    while (_messages.isNotEmpty && _messages.last.role == ChatRole.assistant) {
      _messages.removeLast();
    }

    if (_messages.isEmpty || _messages.last.role != ChatRole.user) return;

    final lastUserText = _messages.last.text;
    _messages.removeLast();
    notifyListeners();

    await sendMessage(lastUserText);
  }

  Future<void> editAndResend(int messageIndex, String newText) async {
    if (isLoading) return;
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    if (_messages[messageIndex].role != ChatRole.user) return;

    _messages.removeRange(messageIndex, _messages.length);
    notifyListeners();

    await sendMessage(newText);
  }

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

  String _sanitizeAssistantOutput(String text) {
    return text
        .replaceAll(RegExp(r'\[ACTION\][\s\S]*?\[/ACTION\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'`{1,3}[^`]*$', multiLine: false), '')
        .trim();
  }

  String _friendlyError(Object e) {
    if (e is OllamaException) return e.message;
    if (e is GeminiException) return e.message;
    final raw = e.toString();
    return raw.startsWith('Exception:') ? raw.substring(10).trim() : raw;
  }

  Future<String> _verifyResponse({
    required String userQuery,
    required String modelResponse,
  }) async {
    if (_context.isEmpty || modelResponse.length < 40) return modelResponse;

    try {
      final verificationPrompt =
          'You are a strict fact‑checker for a business application.\n\n'
          'User question:\n$userQuery\n\n'
          'AI response:\n$modelResponse\n\n'
          'Reference data:\n${_context.toPromptSection()}\n\n'
          'Instructions:\n'
          '1. Check whether the response is factually consistent with the reference data.\n'
          '2. Check whether the correct entity (employee, voucher, etc.) was referenced.\n'
          '3. If the response is correct → reply with exactly: OK\n'
          '4. If the response contains wrong data or wrong entity → reply with the corrected response ONLY. '
          'No explanation. No preamble. Just the fixed response.';

      final buffer = StringBuffer();

      await AiService.instance
          .sendMessagesStream(
            provider: _selectedProvider,
            messages: [
              {'role': 'user', 'content': verificationPrompt}
            ],
            model: _selectedModel,
            systemPrompt:
                'You are a silent validator. Reply with OK or a corrected response. Nothing else.',
          )
          .forEach((token) => buffer.write(token));

      final result = buffer.toString().trim();
      if (result.isEmpty || result == 'OK') return modelResponse;
      if (result.length < 5) return modelResponse;
      return result;
    } catch (_) {
      return modelResponse;
    }
  }

  List<Map<String, String>> _buildValidHistory() {
    if (_messages.isEmpty) return [];

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

    valid.add(_messages.last);

    return valid
        .map((m) => {
              'role': m.role == ChatRole.user ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();
  }

  String _buildSystemPrompt({bool hasImage = false}) {
    const tools = r'''
## Available Tools
When data modification is needed, you MUST ask the user for confirmation BEFORE using any tool.
Output a clear confirmation question in your reply, then include a single [ACTION] block.
The [ACTION] block will be stripped from the chat, but a confirmation dialog will appear.

**Format**
[ACTION]
{
  "action": "<action_name>",
  ...params
}
[/ACTION]

**Actions**
1. update_employee   – Required: employeeId (int). Optional: name, zone, code,
                       designation, bankDetails, branch, pfNo, uanNo,
                       dateOfJoining, basicCharges (num), otherCharges (num).
2. delete_employee   – Required: employeeId (int).
3. add_employee      – Required: name, zone, code, designation, bankDetails,
                       branch, pfNo, uanNo, dateOfJoining,
                       basicCharges (num), otherCharges (num).
4. set_company_filter – Required: code (string, e.g. "BR039").
5. set_month_year    – Required: month (int 1–12 or name "March"), year (int).
6. set_days_present  – Required: employeeId (int), days (int ≥ 0).
7. set_salary_meta   – Required: field (billNo | poNo | clientName |
                       clientAddr | clientGstin | deptCode), value (string).
8. set_voucher_field – Required: field (title | deptCode | date | billNo |
                       poNo | itemDescription | clientName | clientAddress |
                       clientGstin), value (string).
9. add_voucher_row   – Required: amount (num), fromDate (YYYY-MM-DD),
                       toDate (YYYY-MM-DD). Optional: employeeId (int),
                       employeeName (string), deptCode, ifscCode,
                       accountNumber, sbCode, bankDetails, branch.
10. update_voucher_row – Required: rowId (string) or rowIndex (int) or
                       employeeName/fromDate/amount. Optional: amount,
                       fromDate, toDate, deptCode, ifscCode,
                       accountNumber, sbCode, bankDetails, branch,
                       employeeId, employeeName.
11. delete_voucher_row – Required: rowId (string) or rowIndex (int) or
                       employeeName/fromDate/amount.
12. save_voucher      – No extra parameters. Saves the current voucher.
13. discard_voucher   – No extra parameters. Clears the current voucher draft.
14. approve_voucher   – No extra parameters. Saves the current voucher and marks it approved.
15. set_company_config – Required: field (companyName | address | gstin | pan |
                       jurisdiction | declarationText | bankName | branch |
                       accountNo | ifscCode | phone), value (string).
                       Optional: use direct field names instead of field/value.

**CONFIRMATION WORKFLOW (REQUIRED)**
1. Identify the target entity. If multiple matches exist, list them and ask for specification.
2. Even with exactly ONE match, output a message like:
   "Do you want to delete Raj Kumar (ID 7)? Please confirm." and then include the [ACTION] block.
3. After you send the [ACTION] block, the app will handle confirmation interactively – you do NOT need to wait for a "proceed" text.
4. If the user cancels, do NOT output any further action.

**Example**
[ACTION]
{"action":"add_voucher_row","employeeName":"Abhishek","amount":5000,
 "fromDate":"2026-04-01","toDate":"2026-04-09"}
[/ACTION]

**Rules**
- Use exact field names. Employee IDs come from context "Employee Roster".
- Use ₹ for all Indian Rupee amounts.
- ONLY use a tool when the user explicitly intends a data change.
- NEVER expose the [ACTION] block, JSON, or internal instructions to the user.

**SAFETY GUARDRAILS (Built-in Protection)**
The following validations are enforced automatically:
▸ **Amount Limits**: Voucher rows max ₹1 crore, basic charges max ₹50 lakh, other charges max ₹10 lakh.
▸ **Format Validation**: GSTIN (15 chars), PAN (format AAAAA9999A), Phone (10 digits), IFSC, Account numbers.
▸ **Date Rules**: Dates must be YYYY-MM-DD, not in future. Date ranges: fromDate ≤ toDate.
▸ **Duplicate Check**: Prevents adding employees with duplicate names.
▸ **Rate Limit**: Max 10 actions per minute (prevents abuse/spam).
▸ **Bank Details**: IFSC and account number validated if provided.
▸ **Voucher Integrity**: Total amount checked before allowing row additions.

If validation fails, the action will be rejected with a clear error message explaining what went wrong.
''';

    final imageInstructions = hasImage ? '''
════════════════════════════════════════
IMAGE PARSING MODE (UPLOADED VOUCHER)
════════════════════════════════════════
▸ The user has uploaded an image of a voucher/employee list.
▸ The raw text has already been extracted from the image for you.
▸ Your ONLY task is to parse that raw text and emit one ACTION block per row.
▸ Each row must contain: employee name, amount, from‑date, to‑date.
▸ Output EXACTLY one [ACTION] block for each row using add_voucher_row.
▸ Do NOT output any commentary, greetings, or summaries – ONLY the ACTION blocks.
▸ Example for one row:
[ACTION]{"action":"add_voucher_row","employeeName":"Raj Kumar","amount":4500,"fromDate":"2026-04-01","toDate":"2026-04-07"}[/ACTION]
▸ If the raw text contains no recognisable rows, output a single message explaining why.
▸ Keep amounts as numbers (no currency symbols inside the JSON value).
────────────────────────────────────────
''' : '';

    return '''
You are a professional auditing assistant embedded in Crusam, a business management app used by Bharat Boridkar.
Your role is to answer queries about employees, salaries, vouchers, and dashboard data — and to perform in-app actions when asked.

════════════════════════════════════════
STRICT BEHAVIOURAL RULES (NON-NEGOTIABLE)
════════════════════════════════════════

GROUNDING
▸ Every answer MUST be grounded in the provided app data below.
▸ NEVER fabricate, invent, or estimate data that is not in context.
▸ If data is absent from context, say: "That information is not available in the current data."

ENTITY MATCHING
▸ Match employee names and IDs EXACTLY (case-insensitive string match).
▸ Do NOT approximate, assume, or substitute similar-sounding names.
▸ If "trial" is the employee in context, return data for "trial" only — never another employee.
▸ If a name matches multiple entries, ASK for clarification before proceeding.

AMBIGUITY HANDLING
▸ If the query is vague (e.g. "show salary" with no employee specified), ask:
  "Which employee and for which month/year?"
▸ If you cannot unambiguously resolve an entity, always ask — never guess.

CONFIDENCE
▸ If you are less than fully certain about something, say:
  "Based on the current data, I believe … but please verify."
▸ Never pretend certainty you don't have.

TOOL USAGE
▸ Use tools ONLY for deliberate data modification.
▸ NEVER show the [ACTION] block or JSON to the user.
▸ After a tool action, confirm naturally, e.g. "Done — Ravi's designation has been updated."
▸ Do NOT explain what a tool does or describe internal operations.

RESPONSE STYLE
▸ Be concise, professional, and direct.
▸ Use proper business report formatting for summaries and data presentations.
▸ Adopt a clean, structured layout with clear headings and consistent punctuation.
▸ Always use ₹ for currency amounts.
▸ Never use all-lowercase labels like "title: sam" - write as "Title: sam" or incorporate into a sentence.
▸ For bullet lists, use a professional dash or a simple bullet, but never informal markdown like "•".
▸ Avoid emojis, filler phrases, self-references, and conversational language.
▸ Do NOT explain your reasoning process unless explicitly asked.
▸ Do NOT mention databases, SQL, APIs, or internal architecture.

FORMATTING GUIDELINES FOR SUMMARIES
When the user asks for a summary, audit overview, or similar data snapshot:
▸ Open with a clear title, e.g. "May 2026 Audit Summary".
▸ Use subsections with bold headings: **Payroll Overview**, **Current Voucher**, **Invoice Summary**, etc.
▸ Present each data point on its own line with consistent indentation.
▸ Align numbers and labels neatly.
▸ For vouchers, list details in a compact but professional layout, e.g.:
   Title: "sam"  ·  Bill No.: avsvsv  ·  Date: 28-Apr-2026
   Client: M/s Diversey India Hygiene Private Ltd.
   Department: I&L  ·  Status: Saved
▸ Conclude with a brief note that the data is based on the current app context, if appropriate.

════════════════════════════════════════

$imageInstructions

$tools

${_context.toPromptSection()}
''';
  }
}