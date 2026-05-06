import 'dart:async';
import 'dart:convert';

import 'package:crusam/core/ai/models/ai_image_settings.dart';
import 'package:crusam/core/ai/models/ai_provider.dart';
import 'package:crusam/core/ai/models/app_context.dart';
import 'package:crusam/core/ai/presentation/ai_context_builder.dart';
import 'package:crusam/core/ai/services/ai_service.dart';
import 'package:crusam/core/ai/services/file_extraction_service.dart'; // NEW â€“ PDF/Excel support
import 'package:crusam/core/ai/services/employee_verification_service.dart';
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

  // ---- Providerâ€‘aware state -----------------------------------------------
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
  bool _isExtracting = false;

  // ---- Image settings (multimodal configuration) --------------------------
  AiImageSettings _imageSettings = AiImageSettings.defaults;

  // ---- Pending action (interactive confirmation) --------------------------
  Completer<bool>? _pendingActionCompleter;
  String? _pendingActionDescription;

  // ---- Rate limit for image extraction ------------------------------------
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
      final settingsJson = prefs.getString('ai_image_settings_json') ?? '';
      if (settingsJson.isNotEmpty) {
        final decoded = jsonDecode(settingsJson) as Map<String, dynamic>;
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

  // ---- Cancel inâ€‘flight request -------------------------------------------
  void cancelGeneration() {
    if (!isLoading) return;

    _streamSubscription?.cancel();
    _streamSubscription = null;

    AiService.instance.cancelCurrentRequest(_selectedProvider);

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

  // ---- Messaging (accepts optional imageBytes / fileBytes) -----------------
  Future<void> sendMessage(
    String userText, {
    Uint8List? imageBytes,
    // â”€â”€ NEW: PDF / Excel attachment â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Uint8List? fileBytes,   // raw bytes from file_picker
    String? fileType,       // 'pdf' or 'excel'
    String? fileName,       // display name, e.g. "salary_april.xlsx"
  }) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty && imageBytes == null && fileBytes == null) return;
    if (isLoading) return;

    await _refreshContext();

    // â”€â”€ Image path: guard rails (only if imageBytes provided) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (imageBytes != null) {
      if (!_imageSettings.enableImageProcessing) {
        _handleError('Image processing is disabled in settings. Enable it in the AI settings panel.');
        return;
      }

      final now = DateTime.now();
      if (_lastExtractionTime != null &&
          now.difference(_lastExtractionTime!) < _extractionCooldown) {
        _handleError('Please wait a few seconds before sending another image.');
        return;
      }

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

      if (_selectedModel.isEmpty) {
        _handleError('No main model selected. Please select a model first.');
        return;
      }

      _lastExtractionTime = now;
    }

    // â”€â”€ Add user message to the chat â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final userMessageText = imageBytes != null
        ? (trimmed.isEmpty ? 'ðŸ“Ž Image uploaded' : trimmed)
        : fileBytes != null
            ? (trimmed.isEmpty
                ? 'ðŸ“Ž ${fileName ?? fileType ?? 'File'} uploaded'
                : trimmed)
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

      // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // FILE PROCESSING BRANCH â€” PDF / Excel
      // No vision model needed: pure-Dart text extraction â†’ qwen2.3
      // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      if (fileBytes != null && fileType != null) {
        _pendingStreamText = 'ðŸ“‚ Reading ${fileName ?? fileType} â€¦';
        _chatPhase = ChatPhase.thinking;
        notifyListeners();

        FileExtractionResult extraction;
        try {
          // Extraction is now async with progress callbacks
          extraction = await FileExtractionService.extract(
            bytes: fileBytes,
            fileName: fileName ?? (fileType == 'pdf' ? 'document.pdf' : 'spreadsheet.xlsx'),
            onProgress: (progress) {
              _pendingStreamText = 'ðŸ“‚ $progress';
              notifyListeners();
            },
          );
        } on FileExtractionException catch (e) {
          _pendingStreamText = null;
          _chatPhase = ChatPhase.idle;
          _handleError('âŒ ${e.message}');
          return;
        } catch (e) {
          _pendingStreamText = null;
          _chatPhase = ChatPhase.idle;
          _handleError('âŒ Could not read file: $e');
          return;
        }

        // Show extracted-text preview message (collapsible in UI, same as image)
        _addMessage(ChatMessage(
          role: ChatRole.assistant,
          text: '[EXTRACTED_FILE]\n'
              'type:${extraction.fileType.label}\n'
              'summary:${extraction.summaryLine}\n'
              '${extraction.toPromptString()}\n'
              '[/EXTRACTED_FILE]',
          timestamp: DateTime.now(),
        ));

        final userQuestion = trimmed.isEmpty
            ? 'Please summarise the key data in this ${extraction.fileType.label} file.'
            : trimmed;

        // Check if this is an employee data verification request
        final isEmployeeVerification = _isEmployeeVerificationQuery(userQuestion);

        String analysisPrompt = '[${extraction.fileType.label.toUpperCase()} DATA â€” '
            'extracted from "${fileName ?? 'uploaded file'}"]\n'
            '${extraction.summaryLine}\n\n'
            '${extraction.toPromptString()}\n'
            '[END ${extraction.fileType.label.toUpperCase()} DATA]\n\n';

        if (isEmployeeVerification) {
          // Include app's employee master data for comparison
          final appEmployees = EmployeeNotifier.instance.employees;
          if (appEmployees.isNotEmpty) {
            final verification = EmployeeVerificationService.compare(extraction, appEmployees);
            analysisPrompt += verification.toPromptString();
            analysisPrompt += '\n\n';
          } else {
            analysisPrompt += '[APP EMPLOYEE MASTER DATA]\n'
                'No employees are currently loaded in the app context; compare using extracted file data only.\n'
                '[END APP EMPLOYEE MASTER DATA]\n\n';
          }
        }

        analysisPrompt += 'Using the data above, please answer: $userQuestion';

        _pendingStreamText = 'ðŸ’¬ Analysing with $_selectedModelâ€¦';
        _chatPhase = ChatPhase.connecting;
        notifyListeners();

        await _startStreamingAnswer(
          messages: [
            {'role': 'user', 'content': analysisPrompt}
          ],
          model: _selectedModel,
          skipVerification: true,               // file data â‰  app DB, no point verifying
          systemPromptOverride: isEmployeeVerification
              ? _buildEmployeeDiffPrompt()
              : _buildFileAnalysisPrompt(extraction.fileType),
        );
        return; // â† important: don't fall through to image/text branches
      }

      // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // IMAGE PROCESSING BRANCH (step-by-step)
      // --------------------------------------------------------------------
      if (imageBytes != null) {
        _isExtracting = true;

        _pendingStreamText = 'ðŸ” Reading image with ${_imageSettings.imageProcessingModel}â€¦';
        _chatPhase = ChatPhase.thinking;
        notifyListeners();

        // STEP 1: Real-time streaming extraction â€” NO system prompt,
        // NO context. minicpm-v only sees the image + extraction instruction.
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
              _pendingStreamText = extractedBuffer.toString();
              notifyListeners();
            },
            onDone: () => completer.complete(),
            onError: (e) => completer.completeError(e),
            cancelOnError: true,
          );
          await completer.future;
        } on OllamaCancelledException {
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
              'âŒ Image processing failed: ${e.message}\n\n'
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

        // Show the extracted text preview in chat (collapsible in UI)
        _addMessage(ChatMessage(
          role: ChatRole.assistant,
          text: '[EXTRACTED_TEXT]\n$rawText\n[/EXTRACTED_TEXT]',
          timestamp: DateTime.now(),
        ));

        // STEP 2: Pass extracted text to the analysis model.
        final userQuestion = trimmed.isEmpty
            ? 'Please summarise the key data shown in this image.'
            : trimmed;
        final analysisModel = _imageSettings.analysisModel ?? _selectedModel;

        _pendingStreamText = 'ðŸ’¬ Analysing with $analysisModelâ€¦';
        _chatPhase = ChatPhase.connecting;
        notifyListeners();

        final analysisPrompt =
            '[IMAGE DATA â€” text extracted from the uploaded image]\n'
            '$rawText\n'
            '[END IMAGE DATA]\n\n'
            'Using the image data above, please answer: $userQuestion';

        await _startStreamingAnswer(
          messages: [
            {'role': 'user', 'content': analysisPrompt}
          ],
          model: analysisModel,
          // skip verification for image-derived data
          skipVerification: true,
          // use a lightweight system prompt (no employee roster / tools)
          systemPromptOverride: _buildImageAnalysisPrompt(),
        );

      } else {
        // Normal text-only stream â€” full context + verification as before
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

  // ---- Helper to start the final streaming response ------------------------
  Future<void> _startStreamingAnswer({
    required List<Map<String, String>> messages,
    required String model,
    bool skipVerification = false,          // skip _verifyResponse for file/image answers
    String? systemPromptOverride,           // use a lightweight prompt for file/image analysis
  }) async {
    _streamSubscription?.cancel();

    final stream = AiService.instance.sendMessagesStream(
      provider: _selectedProvider,
      messages: messages,
      model: model,
      systemPrompt: systemPromptOverride ?? _buildSystemPrompt(),
    );

    _chatPhase = ChatPhase.thinking;
    notifyListeners();

    _streamSubscription = stream.listen(
      (token) {
        // Clear any status/progress message that was shown before streaming began
        // (e.g. "💬 Analysing with model…") so it doesn't leak into the response.
        if (_chatPhase != ChatPhase.streaming) {
          _pendingStreamText = '';
          _chatPhase = ChatPhase.streaming;
        }
        _pendingStreamText = (_pendingStreamText ?? '') + token;
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

        String verifiedText = sanitized;
        if (!skipVerification) {
          _chatPhase = ChatPhase.verifying;
          notifyListeners();
          verifiedText = await _verifyResponse(
            userQuery: _lastUserQuery,
            modelResponse: sanitized,
          );
        }

        _chatPhase = ChatPhase.idle;
        _status = ChatStatus.idle;

        _addMessage(ChatMessage(
          role: ChatRole.assistant,
          text: verifiedText,
          timestamp: DateTime.now(),
        ));

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
            text: 'âš ï¸ Actions failed: ${result.reason}',
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
        return 'Add voucher row for ${actionJson['employeeName'] ?? 'employee'} (â‚¹${actionJson['amount'] ?? '?'})?';
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
      text: 'âš ï¸ $message',
      timestamp: DateTime.now(),
      isError: true,
    ));
  }

  String _sanitizeAssistantOutput(String text) {
    return text
        // Strip [ACTION] blocks
        .replaceAll(RegExp(r'\[ACTION\][\s\S]*?\[/ACTION\]', caseSensitive: false), '')
        // Strip fenced code blocks that sneak through
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'`{1,3}[^`]*$', multiLine: false), '')
        // Strip status/progress prefixes like "💬 Analysing with model…", "📂 Reading…"
        .replaceAll(RegExp(r'^[📂💬🔍📊⏳✅]\s*[^\n]{0,80}[…\.]{1,3}\s*', multiLine: false), '')
        // Strip leading status lines that end with "…" or "..." before the real answer
        .replaceAll(RegExp(r'^(?:(?:Analysing|Reading|Extracting|Processing|Thinking)[^\n]*\n)+', caseSensitive: false), '')
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
          'You are a strict factâ€‘checker for a business application.\n\n'
          'User question:\n$userQuery\n\n'
          'AI response:\n$modelResponse\n\n'
          'Reference data:\n${_context.toPromptSection()}\n\n'
          'Instructions:\n'
          '1. Check whether the response is factually consistent with the reference data.\n'
          '2. Check whether the correct entity (employee, voucher, etc.) was referenced.\n'
          '3. If the response is correct â†’ reply with exactly: OK\n'
          '4. If the response contains wrong data or wrong entity â†’ reply with the corrected response ONLY. '
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

  /// Minimal system prompt for image analysis responses.
  /// Excludes the full employee roster and tool definitions to keep
  /// time-to-first-token fast.
  String _buildImageAnalysisPrompt() => '''
You are a professional data analyst embedded in Crusam, a business management app.
The user has uploaded an image. Raw text has been extracted and provided as [IMAGE DATA].

════════════════════════════════════════
RESPONSE STYLE RULES (NON-NEGOTIABLE)
════════════════════════════════════════

OPENING
▸ Begin your answer DIRECTLY — no greetings, no preamble, no "Let me analyse..." phrases.
▸ NEVER start with a status message, thinking note, or progress description.
▸ The very first word must be part of the actual answer.

FORMATTING FOR SIMPLE FACTUAL QUERIES (name, number, single field)
▸ State the answer on the first line, with the key entity in **bold**.
▸ Follow with a short bullet list of closely related details (only if directly relevant).
▸ End with one brief, natural follow-up question (like "Would you like more details?").

Example — query: "what is the name of the third employee?"
**Ashish Kumar Pal** is the third employee listed.

- PF Number: MH/212395/0117
- UAN Number: 100809466

Would you like to see more details for Ashish Kumar Pal?

FORMATTING FOR MULTI-FIELD QUERIES
▸ Use a **bold** heading for each entity or section.
▸ List each field on its own line using a dash bullet: `- Field: Value`
▸ Group related fields under their entity heading; separate entities with a blank line.

FORMATTING FOR TABULAR DATA
▸ Use a clean markdown table ONLY when the user explicitly asks for a table or comparison.
▸ Otherwise, use bullet lists — do NOT dump raw extracted table text.
▸ Show only columns/rows directly relevant to the query.

GENERAL RULES
▸ Use **bold** for: employee names, IDs, PF numbers, UAN numbers, amounts, key identifiers.
▸ Use ₹ for all Indian Rupee amounts.
▸ Do NOT include fields not asked for (e.g. bank account, IFSC) unless specifically requested.
▸ Do NOT mention "image data", "extracted text", "the image shows" — just answer directly.
▸ Do NOT repeat the user’s question back to them.
▸ If data is unclear or ambiguous, say so in one short sentence.
▸ Keep responses concise — answer + relevant details + one follow-up question.
▸ Never fabricate or estimate values not present in the data.
''';

  /// Minimal system prompt for PDF / Excel file analysis.
  /// Tailored slightly per file type.
  String _buildFileAnalysisPrompt(AttachedFileType type) {
    final typeName = type.label;
    return '''
You are a professional data analyst embedded in Crusam, a business management app.
The user has uploaded a $typeName file. The full extracted text is provided as [${typeName.toUpperCase()} DATA].

════════════════════════════════════════
RESPONSE STYLE RULES (NON-NEGOTIABLE)
════════════════════════════════════════

OPENING
▸ Begin your answer DIRECTLY — no greetings, no preamble, no "Let me analyse..." phrases.
▸ NEVER start with a status message, thinking note, or progress description.
▸ The very first word must be part of the actual answer.

FORMATTING FOR SIMPLE FACTUAL QUERIES (name, number, single field)
▸ State the answer on the first line, with the key entity in **bold**.
▸ Follow with a short bullet list of closely related details (only if directly relevant).
▸ End with one brief, natural follow-up question (like "Would you like more details about this employee?").

Example — query: "what is the name of the third employee?"
**Ashish Kumar Pal** is the third employee listed in the file.

- PF Number: MH/212395/0117
- UAN Number: 100809466

Would you like to see more details for Ashish Kumar Pal?

FORMATTING FOR MULTI-FIELD QUERIES
▸ Use a **bold** heading for each entity or section.
▸ List each field on its own line using a dash bullet: `- Field: Value`
▸ Group related fields together under their entity heading.
▸ Separate multiple entities with a blank line.

FORMATTING FOR TABULAR / COMPARATIVE DATA
▸ Use a clean markdown table ONLY when the user explicitly asks for a table or comparison.
▸ Otherwise, use bullet lists — do NOT dump raw extracted table text.
▸ Show only the columns/rows directly relevant to the query.

GENERAL RULES
▸ Use **bold** for: employee names, IDs, PF numbers, UAN numbers, key identifiers.
▸ Use ₹ for all Indian Rupee amounts.
▸ Do NOT include fields that were not asked for (e.g. bank account, IFSC) unless specifically requested.
▸ Do NOT mention "extracted text", "the file says", "according to the data" — just answer directly.
▸ Do NOT repeat the user's question back to them.
▸ If data is unclear or missing, say so in one short sentence.
▸ If the file was truncated, note it briefly at the end.
▸ Keep the total response concise — answer + relevant details + one follow-up question.
▸ Never fabricate or estimate values not present in the data.
▸ Use ₹ for currency amounts; format numbers clearly (no raw decimal junk).
''';
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
1. update_employee   â€“ Required: employeeId (int). Optional: name, zone, code,
                       designation, bankDetails, branch, pfNo, uanNo,
                       dateOfJoining, basicCharges (num), otherCharges (num).
2. delete_employee   â€“ Required: employeeId (int).
3. add_employee      â€“ Required: name, zone, code, designation, bankDetails,
                       branch, pfNo, uanNo, dateOfJoining,
                       basicCharges (num), otherCharges (num).
4. set_company_filter â€“ Required: code (string, e.g. "BR039").
5. set_month_year    â€“ Required: month (int 1â€“12 or name "March"), year (int).
6. set_days_present  â€“ Required: employeeId (int), days (int â‰¥ 0).
7. set_salary_meta   â€“ Required: field (billNo | poNo | clientName |
                       clientAddr | clientGstin | deptCode), value (string).
8. set_voucher_field â€“ Required: field (title | deptCode | date | billNo |
                       poNo | itemDescription | clientName | clientAddress |
                       clientGstin), value (string).
9. add_voucher_row   â€“ Required: amount (num), fromDate (YYYY-MM-DD),
                       toDate (YYYY-MM-DD). Optional: employeeId (int),
                       employeeName (string), deptCode, ifscCode,
                       accountNumber, sbCode, bankDetails, branch.
10. update_voucher_row â€“ Required: rowId (string) or rowIndex (int) or
                       employeeName/fromDate/amount. Optional: amount,
                       fromDate, toDate, deptCode, ifscCode,
                       accountNumber, sbCode, bankDetails, branch,
                       employeeId, employeeName.
11. delete_voucher_row â€“ Required: rowId (string) or rowIndex (int) or
                       employeeName/fromDate/amount.
12. save_voucher      â€“ No extra parameters. Saves the current voucher.
13. discard_voucher   â€“ No extra parameters. Clears the current voucher draft.
14. approve_voucher   â€“ No extra parameters. Saves the current voucher and marks it approved.
15. set_company_config â€“ Required: field (companyName | address | gstin | pan |
                       jurisdiction | declarationText | bankName | branch |
                       accountNo | ifscCode | phone), value (string).
                       Optional: use direct field names instead of field/value.

**CONFIRMATION WORKFLOW (REQUIRED)**
1. Identify the target entity. If multiple matches exist, list them and ask for specification.
2. Even with exactly ONE match, output a message like:
   "Do you want to delete Raj Kumar (ID 7)? Please confirm." and then include the [ACTION] block.
3. After you send the [ACTION] block, the app will handle confirmation interactively â€“ you do NOT need to wait for a "proceed" text.
4. If the user cancels, do NOT output any further action.

**Example**
[ACTION]
{"action":"add_voucher_row","employeeName":"Abhishek","amount":5000,
 "fromDate":"2026-04-01","toDate":"2026-04-09"}
[/ACTION]

**Rules**
- Use exact field names. Employee IDs come from context "Employee Roster".
- Use â‚¹ for all Indian Rupee amounts.
- ONLY use a tool when the user explicitly intends a data change.
- NEVER expose the [ACTION] block, JSON, or internal instructions to the user.

**SAFETY GUARDRAILS (Built-in Protection)**
The following validations are enforced automatically:
â–¸ **Amount Limits**: Voucher rows max â‚¹1 crore, basic charges max â‚¹50 lakh, other charges max â‚¹10 lakh.
â–¸ **Format Validation**: GSTIN (15 chars), PAN (format AAAAA9999A), Phone (10 digits), IFSC, Account numbers.
â–¸ **Date Rules**: Dates must be YYYY-MM-DD, not in future. Date ranges: fromDate â‰¤ toDate.
â–¸ **Duplicate Check**: Prevents adding employees with duplicate names.
â–¸ **Rate Limit**: Max 10 actions per minute (prevents abuse/spam).
â–¸ **Bank Details**: IFSC and account number validated if provided.
â–¸ **Voucher Integrity**: Total amount checked before allowing row additions.

If validation fails, the action will be rejected with a clear error message explaining what went wrong.
''';

    final imageInstructions = hasImage ? '''
â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
IMAGE PARSING MODE (UPLOADED VOUCHER)
â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
â–¸ The user has uploaded an image of a voucher/employee list.
â–¸ The raw text has already been extracted from the image for you.
â–¸ Your ONLY task is to parse that raw text and emit one ACTION block per row.
â–¸ Each row must contain: employee name, amount, fromâ€‘date, toâ€‘date.
â–¸ Output EXACTLY one [ACTION] block for each row using add_voucher_row.
â–¸ Do NOT output any commentary, greetings, or summaries â€“ ONLY the ACTION blocks.
â–¸ Example for one row:
[ACTION]{"action":"add_voucher_row","employeeName":"Raj Kumar","amount":4500,"fromDate":"2026-04-01","toDate":"2026-04-07"}[/ACTION]
â–¸ If the raw text contains no recognisable rows, output a single message explaining why.
â–¸ Keep amounts as numbers (no currency symbols inside the JSON value).
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
''' : '';

    return '''
You are a professional auditing assistant embedded in Crusam, a business management app used by Bharat Boridkar.
Your role is to answer queries about employees, salaries, vouchers, and dashboard data â€” and to perform in-app actions when asked.

â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
STRICT BEHAVIOURAL RULES (NON-NEGOTIABLE)
â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

GROUNDING
â–¸ Every answer MUST be grounded in the provided app data below.
â–¸ NEVER fabricate, invent, or estimate data that is not in context.
â–¸ If data is absent from context, say: "That information is not available in the current data."

ENTITY MATCHING
â–¸ Match employee names and IDs EXACTLY (case-insensitive string match).
â–¸ Do NOT approximate, assume, or substitute similar-sounding names.
â–¸ If "trial" is the employee in context, return data for "trial" only â€” never another employee.
â–¸ If a name matches multiple entries, ASK for clarification before proceeding.

AMBIGUITY HANDLING
â–¸ If the query is vague (e.g. "show salary" with no employee specified), ask:
  "Which employee and for which month/year?"
â–¸ If you cannot unambiguously resolve an entity, always ask â€” never guess.

CONFIDENCE
â–¸ If you are less than fully certain about something, say:
  "Based on the current data, I believe â€¦ but please verify."
â–¸ Never pretend certainty you don't have.

TOOL USAGE
â–¸ Use tools ONLY for deliberate data modification.
â–¸ NEVER show the [ACTION] block or JSON to the user.
â–¸ After a tool action, confirm naturally, e.g. "Done â€” Ravi's designation has been updated."
â–¸ Do NOT explain what a tool does or describe internal operations.

RESPONSE STYLE
â–¸ Be concise, professional, and direct.
â–¸ Use proper business report formatting for summaries and data presentations.
â–¸ Adopt a clean, structured layout with clear headings and consistent punctuation.
â–¸ Always use â‚¹ for currency amounts.
â–¸ Never use all-lowercase labels like "title: sam" - write as "Title: sam" or incorporate into a sentence.
â–¸ For bullet lists, use a professional dash or a simple bullet, but never informal markdown like "â€¢".
â–¸ Avoid emojis, filler phrases, self-references, and conversational language.
â–¸ Do NOT explain your reasoning process unless explicitly asked.
â–¸ Do NOT mention databases, SQL, APIs, or internal architecture.

FORMATTING GUIDELINES FOR SUMMARIES
When the user asks for a summary, audit overview, or similar data snapshot:
â–¸ Open with a clear title, e.g. "May 2026 Audit Summary".
â–¸ Use subsections with bold headings: **Payroll Overview**, **Current Voucher**, **Invoice Summary**, etc.
â–¸ Present each data point on its own line with consistent indentation.
â–¸ Align numbers and labels neatly.
â–¸ For vouchers, list details in a compact but professional layout, e.g.:
   Title: "sam"  Â·  Bill No.: avsvsv  Â·  Date: 28-Apr-2026
   Client: M/s Diversey India Hygiene Private Ltd.
   Department: I&L  Â·  Status: Saved
â–¸ Conclude with a brief note that the data is based on the current app context, if appropriate.

â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

$imageInstructions

$tools

${_context.toPromptSection()}
''';
  }

  /// Check if the user query is about employee data verification/diff.
  bool _isEmployeeVerificationQuery(String query) {
    final lower = query.toLowerCase();
    return lower.contains('employee') ||
           lower.contains('verify') ||
           lower.contains('master') ||
           lower.contains('compare') ||
           lower.contains('diff') ||
           lower.contains('missing') ||
           lower.contains('addition') ||
           lower.contains('deletion') ||
           lower.contains('update');
  }

  /// Specialized prompt for employee data comparison/verification.
  String _buildEmployeeDiffPrompt() {
    return '''
You are a professional data analyst embedded in Crusam, a business management app.
The user has uploaded a file containing employee data to compare with the app's master employee list.

**FORMAT YOUR RESPONSE CLEARLY:**
- Use **bold** for employee names and key identifiers
- Use bullet points (dash lines) for differences and recommendations
- Keep answers concise and well-structured
- Focus ONLY on relevant differences
- Do NOT include irrelevant bank/account fields unless specifically asked

Example format:
**Ashish Kumar Pal**
- PF Number: MH/212395/0117
- UAN Number: UBIN0809466
- Status: Exists in file

Analysis steps:
1. Analyze the extracted file data — look for employee records, names, IDs, PF numbers, etc.
2. Compare with the [APP EMPLOYEE MASTER DATA] provided
3. Identify additions, deletions, and updates
4. Match employees by name, PF number, or unique identifiers
5. Suggest specific actions: add_employee, update_employee, delete_employee
6. Be precise about what fields differ
7. Format suggestions as clear, actionable recommendations
8. Use ₹ for currency amounts
''';
  }
}