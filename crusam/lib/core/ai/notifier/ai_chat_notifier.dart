// crusam/lib/core/ai/notifier/ai_chat_notifier.dart
//
// Key additions vs. previous version:
//  1. _activeFileContext         — persists last uploaded file across follow‑ups
//  2. _lastTaskDescription      — remembers the most recent task
//  3. _isContinueIntent()       — detects "continue", "next", "resume" etc.
//  4. BatchSyncManager          — drives one‑by‑one employee sync
//  5. _buildValidHistory()      — injects file content into the AI context window
//  6. AutonomousSyncService     — runs all changes automatically when triggered

import 'dart:async';
import 'dart:convert';

import 'package:crusam/core/ai/models/ai_image_settings.dart';
import 'package:crusam/core/ai/models/ai_provider.dart';
import 'package:crusam/core/ai/models/app_context.dart';
import 'package:crusam/core/ai/presentation/ai_context_builder.dart';
import 'package:crusam/core/ai/services/ai_service.dart';
import 'package:crusam/core/ai/services/autonomous_sync_service.dart';   // NEW
import 'package:crusam/core/ai/services/batch_sync_manager.dart';
import 'package:crusam/core/ai/services/file_extraction_service.dart';
import 'package:crusam/core/ai/services/employee_verification_service.dart';
import 'package:crusam/core/ai/services/voucher_image_processing_service.dart';   // NEW: voucher image parsing
import 'package:crusam/core/ai/services/parsers/name_resolver.dart';             // NEW
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

  // ── Chat messages & UI state ─────────────────────────────────────────────
  final List<ChatMessage> _messages = [];
  ChatStatus _status = ChatStatus.idle;
  String? _errorMessage;
  bool _panelOpen = false;
  AppContext _context = const AppContext();

  // ── Provider‑aware state ─────────────────────────────────────────────────
  AiProvider _selectedProvider = AiProvider.ollama;
  String _selectedModel = '';
  List<AiModelInfo> _availableModels = [];
  bool _initializing = true;
  bool _loadingModels = false;

  // ── Streaming state ──────────────────────────────────────────────────────
  String? _pendingStreamText;
  ChatPhase _chatPhase = ChatPhase.idle;
  StreamSubscription<String>? _streamSubscription;
  String _lastUserQuery = '';

  // ── Extraction guard ─────────────────────────────────────────────────────
  bool _isExtracting = false;

  // ── Image settings ───────────────────────────────────────────────────────
  AiImageSettings _imageSettings = AiImageSettings.defaults;

  // ── Pending action (interactive confirmation) ────────────────────────────
  Completer<bool>? _pendingActionCompleter;
  String? _pendingActionDescription;

  // ── Rate limit for image extraction ─────────────────────────────────────
  DateTime? _lastExtractionTime;
  static const Duration _extractionCooldown = Duration(seconds: 5);

  // ── File context persistence ─────────────────────────────────────────────
  FileExtractionResult? _activeFileContext;
  String? _activeFileName;

  // ── Task memory (for "continue last task") ───────────────────────────────
  String? _lastTaskDescription;

  // ── Batch sync state ─────────────────────────────────────────────────────
  bool _batchSyncActive = false;

  // ── Public getters ───────────────────────────────────────────────────────
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  ChatStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get panelOpen => _panelOpen;
  bool get isLoading => _status == ChatStatus.loading;
  bool get hasMessages => _messages.isNotEmpty;

  String? get pendingStreamText => _pendingStreamText;
  bool get isStreaming => _chatPhase == ChatPhase.streaming;
  ChatPhase get chatPhase => _chatPhase;

  bool get hasPendingAction => _pendingActionCompleter != null;
  String? get pendingActionDescription => _pendingActionDescription;

  AiProvider get selectedProvider => _selectedProvider;
  String get selectedModel => _selectedModel;
  List<AiModelInfo> get availableModels => List.unmodifiable(_availableModels);
  bool get hasModels => _availableModels.isNotEmpty;
  bool get isInitializing => _initializing;
  bool get isLoadingModels => _loadingModels;

  AiImageSettings get imageSettings => _imageSettings;

  bool get hasActiveFileContext => _activeFileContext != null;
  String? get activeFileName => _activeFileName;
  bool get hasBatchSyncActive => _batchSyncActive;

  // ── Initialization ───────────────────────────────────────────────────────
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

  Future<void> setImageProcessingModel(String modelName) async {
    _imageSettings = _imageSettings.copyWith(imageProcessingModel: modelName);
    await _saveImageSettings();
    notifyListeners();
  }

  Future<void> setAnalysisModel(String? modelName) async {
    _imageSettings = _imageSettings.copyWith(analysisModel: modelName);
    await _saveImageSettings();
    notifyListeners();
  }

  Future<void> updateImageSettings(AiImageSettings newSettings) async {
    _imageSettings = newSettings;
    await _saveImageSettings();
    notifyListeners();
  }

  // ── Provider & model management ──────────────────────────────────────────
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
        _errorMessage = _selectedProvider == AiProvider.ollama
            ? 'No Ollama models found. Run: ollama pull llama3.2:3b'
            : 'No Gemini models available.';
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

  // ── Panel controls ───────────────────────────────────────────────────────
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

  // ── Context injection ────────────────────────────────────────────────────
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

  // ── Cancel in‑flight request ─────────────────────────────────────────────
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

  // ── Clear file context ───────────────────────────────────────────────────
  void clearFileContext() {
    _activeFileContext = null;
    _activeFileName = null;
    _lastTaskDescription = null;
    _batchSyncActive = false;
    BatchSyncManager.instance.clear();
  }

  // ── Intent detection helpers ─────────────────────────────────────────────

  bool _isContinueIntent(String text) {
    final lower = text.toLowerCase().trim();
    if (['continue', 'next', 'proceed', 'go ahead', 'go on',
         'resume', 'carry on', 'keep going', 'do it', 'do it all',
         'apply all', 'sync all'].contains(lower)) return true;
    return lower.startsWith('continue with') ||
        lower.startsWith('resume the') ||
        lower.startsWith('continue the') ||
        lower.startsWith('continue from') ||
        lower.contains('continue with last') ||
        lower.contains('resume last');
  }

  bool _isSkipIntent(String text) {
    final lower = text.toLowerCase().trim();
    return ['skip', 'no', 'nope', 'ignore', 'skip this', 'skip it',
            'leave it', 'not this one'].contains(lower);
  }

  /// NEW: detects autonomous “sync all” / “apply all” intent
  bool _isAutonomousSyncQuery(String query) {
    final lower = query.toLowerCase();
    return (lower.contains('sync') && (lower.contains('all') || lower.contains('auto'))) ||
        lower.contains('apply all') ||
        lower.contains('make changes') ||
        lower.contains('update all') ||
        lower.contains('match the') ||
        (lower.contains('sync') && lower.contains('employee')) ||
        lower.contains('autonomous') ||
        lower.contains('bulk update') ||
        lower.contains('just do it') ||
        lower.contains('run all');
  }

  /// NEW: detects voucher creation intent from images
  bool _isVoucherCreationRequest(String query) {
    final lower = query.toLowerCase();
    return (lower.contains('create') ||
            lower.contains('add') ||
            lower.contains('make') ||
            lower.contains('voucher') ||
            lower.contains('import') ||
            lower.contains('enter')) &&
        (lower.contains('voucher') ||
            lower.contains('image') ||
            lower.contains('data') ||
            lower.contains('employee'));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN: sendMessage
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendMessage(
    String userText, {
    Uint8List? imageBytes,
    Uint8List? fileBytes,
    String? fileType,
    String? fileName,
  }) async {
    final trimmed = userText.trim();
    if (trimmed.isEmpty && imageBytes == null && fileBytes == null) return;
    if (isLoading) return;

    await _refreshContext();

    // ── Guard: image processing checks ─────────────────────────────────────
    if (imageBytes != null) {
      if (!_imageSettings.enableImageProcessing) {
        _handleError('Image processing is disabled in settings.');
        return;
      }
      final now = DateTime.now();
      if (_lastExtractionTime != null &&
          now.difference(_lastExtractionTime!) < _extractionCooldown) {
        _handleError('Please wait a few seconds before sending another image.');
        return;
      }
      final modelOk = await OllamaService.instance
          .isVisionModel(_imageSettings.imageProcessingModel);
      if (!modelOk) {
        _handleError(
          'Vision model "${_imageSettings.imageProcessingModel}" not available. '
          'Check Image Processing settings.',
        );
        return;
      }
      if (_selectedModel.isEmpty) {
        _handleError('No main model selected.');
        return;
      }
      _lastExtractionTime = now;
    }

    // ── Handle batch sync navigation commands ──────────────────────────────
    if (_batchSyncActive && BatchSyncManager.instance.hasActiveQueue) {
      if (_isSkipIntent(trimmed) || trimmed.toLowerCase() == 'no') {
        _addMessage(ChatMessage(
          role: ChatRole.user, text: trimmed, timestamp: DateTime.now(),
        ));
        BatchSyncManager.instance.skip();
        _presentNextBatchItem();
        return;
      }
      if (['yes', 'apply', 'confirm', 'ok', 'okay', 'do it', 'sure']
          .contains(trimmed.toLowerCase())) {
        _addMessage(ChatMessage(
          role: ChatRole.user, text: trimmed, timestamp: DateTime.now(),
        ));
        await _executeCurrentBatchItem();
        return;
      }
    }

    // ── “Continue last task” intent ────────────────────────────────────────
    if (_isContinueIntent(trimmed)) {
      if (BatchSyncManager.instance.hasActiveQueue) {
        _addMessage(ChatMessage(
          role: ChatRole.user, text: trimmed, timestamp: DateTime.now(),
        ));
        _batchSyncActive = true;
        _presentNextBatchItem();
        return;
      }
      if (_activeFileContext != null && _lastTaskDescription != null) {
        _addMessage(ChatMessage(
          role: ChatRole.user, text: trimmed, timestamp: DateTime.now(),
        ));
        _addMessage(ChatMessage(
          role: ChatRole.assistant,
          text: '📋 Last task: **$_lastTaskDescription**\n\n'
              'The file **$_activeFileName** is still loaded. '
              'What would you like to do with it?',
          timestamp: DateTime.now(),
        ));
        notifyListeners();
        return;
      }
    }

    // ── Build user message text ─────────────────────────────────────────────
    final userMessageText = imageBytes != null
        ? (trimmed.isEmpty ? '📎 Image uploaded' : trimmed)
        : fileBytes != null
            ? (trimmed.isEmpty
                ? '📎 ${fileName ?? fileType ?? 'File'} uploaded'
                : trimmed)
            : trimmed;

    final userMsg = ChatMessage(
      role: ChatRole.user, text: userMessageText, timestamp: DateTime.now(),
    );
    _addMessage(userMsg);

    _status = ChatStatus.loading;
    _errorMessage = null;
    _pendingStreamText = '';
    _chatPhase = ChatPhase.connecting;
    notifyListeners();

    try {
      final history = _buildValidHistory();

      // ─────────────────────────────────────────────────────────────────
      // FILE PROCESSING BRANCH
      // ─────────────────────────────────────────────────────────────────
      if (fileBytes != null && fileType != null) {
        _pendingStreamText = '📂 Reading ${fileName ?? fileType}…';
        _chatPhase = ChatPhase.thinking;
        notifyListeners();

        FileExtractionResult extraction;
        try {
          extraction = await FileExtractionService.extract(
            bytes: fileBytes,
            fileName: fileName ??
                (fileType == 'pdf' ? 'document.pdf' : 'spreadsheet.xlsx'),
            onProgress: (progress) {
              _pendingStreamText = '📂 $progress';
              notifyListeners();
            },
          );
        } on FileExtractionException catch (e) {
          _pendingStreamText = null;
          _chatPhase = ChatPhase.idle;
          _handleError('❌ ${e.message}');
          return;
        } catch (e) {
          _pendingStreamText = null;
          _chatPhase = ChatPhase.idle;
          _handleError('❌ Could not read file: $e');
          return;
        }

        // Persist file context
        _activeFileContext = extraction;
        _activeFileName = fileName ?? fileType;

        // Add collapsible bubble
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

        _lastTaskDescription = userQuestion;

        final isEmployeeVerification = _isEmployeeVerificationQuery(userQuestion);

        if (isEmployeeVerification) {
          final appEmployees = EmployeeNotifier.instance.employees;
          if (appEmployees.isNotEmpty) {
            final verification = EmployeeVerificationService.compare(
              extraction, appEmployees,
            );

            // *** NEW: autonomous sync detection ***
            final wantsAutoSync = _isAutonomousSyncQuery(userQuestion);
            if (wantsAutoSync) {
              final adds = verification.additions.length;
              final updates = verification.updates.length;
              final deletes = verification.deletions.length;

              _addMessage(ChatMessage(
                role: ChatRole.assistant,
                text: '🔄 **Found $adds additions, $updates updates, $deletes deletions.**\n\n'
                    'Starting autonomous sync… I will apply all changes now.\n'
                    '_Deletions are skipped by default for safety._',
                timestamp: DateTime.now(),
              ));
              notifyListeners();

              final syncService = AutonomousSyncService.instance;
              final summary = await syncService.runSync(
                result: verification,
                fileName: fileName ?? 'uploaded file',
                skipDeletes: true,
                onProgress: (progress) {
                  _pendingStreamText = '${progress.statusLine}…';
                  notifyListeners();
                },
              );

              _pendingStreamText = null;
              _chatPhase = ChatPhase.idle;
              _status = ChatStatus.idle;

              _addMessage(ChatMessage(
                role: ChatRole.assistant,
                text: summary.chatMessage,
                timestamp: DateTime.now(),
              ));
              notifyListeners();
              return;
            }

            // Normal interactive walk‑through
            BatchSyncManager.instance.buildFromVerification(
              verification,
              fileName ?? 'uploaded file',
            );

            _pendingStreamText = null;
            _chatPhase = ChatPhase.idle;
            _status = ChatStatus.idle;

            if (!BatchSyncManager.instance.hasActiveQueue) {
              _addMessage(ChatMessage(
                role: ChatRole.assistant,
                text: '✅ No differences found between the file and app employee records.',
                timestamp: DateTime.now(),
              ));
              notifyListeners();
              return;
            }

            final adds = verification.additions.length;
            final updates = verification.updates.length;
            final deletes = verification.deletions.length;
            final prog = BatchSyncManager.instance.progress;

            _addMessage(ChatMessage(
              role: ChatRole.assistant,
              text: '📊 **Employee Sync Summary** — *${fileName ?? 'file'}*\n'
                  '- ➕ Additions: $adds\n'
                  '- ✏️ Updates: $updates\n'
                  '- 🗑️ Deletions: $deletes\n\n'
                  'I will walk you through each change one by one.\n'
                  'Reply **Yes** to apply, **Skip** to skip, or **Stop** to cancel.\n\n'
                  '---\n\n'
                  '${BatchSyncManager.instance.currentChangeCard()}',
              timestamp: DateTime.now(),
            ));

            _batchSyncActive = true;
            _lastTaskDescription =
                'Employee sync from ${fileName ?? 'file'} (${prog.total} changes)';
            notifyListeners();
            return;
          }
        }

        // Regular file Q&A (non‑sync)
        String analysisPrompt = _buildFileContextBlock(extraction, fileName) +
            'Using the data above, please answer: $userQuestion';

        _pendingStreamText = '💬 Analysing with $_selectedModel…';
        _chatPhase = ChatPhase.connecting;
        notifyListeners();

        await _startStreamingAnswer(
          messages: [
            {'role': 'user', 'content': analysisPrompt}
          ],
          model: _selectedModel,
          skipVerification: true,
          systemPromptOverride: _buildFileAnalysisPrompt(extraction.fileType),
        );
        return;
      }

      // ─────────────────────────────────────────────────────────────────
      // IMAGE PROCESSING BRANCH
      // ─────────────────────────────────────────────────────────────────
      if (imageBytes != null) {
        _isExtracting = true;
        _pendingStreamText =
            '🔍 Reading image with ${_imageSettings.imageProcessingModel}…';
        _chatPhase = ChatPhase.thinking;
        notifyListeners();

        final extractionStream =
            OllamaService.instance.sendMultimodalExtractionStream(
          model: _imageSettings.imageProcessingModel,
          prompt:
              'Extract all readable text and data from this image. '
              'If the image contains a table, preserve the row and column '
              'structure by separating columns with " | " and each row on '
              'its own line. Include all numbers, names, codes, and headers '
              'exactly as they appear. Do not summarise or add commentary.',
          imageBytes: imageBytes,
          timeout:
              Duration(seconds: _imageSettings.extractionTimeoutSeconds),
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
          _handleError(
            '❌ Image processing failed: ${e.message}\n\n'
            'Configured model: ${_imageSettings.imageProcessingModel}',
          );
          return;
        } finally {
          extractionSub?.cancel();
        }

        _isExtracting = false;
        final rawText = extractedBuffer.toString().trim();

        if (rawText.isEmpty) {
          _handleError(
              'The vision model did not extract any text from the image.');
          return;
        }

        _addMessage(ChatMessage(
          role: ChatRole.assistant,
          text: '[EXTRACTED_TEXT]\n$rawText\n[/EXTRACTED_TEXT]',
          timestamp: DateTime.now(),
        ));

        // ── Check if user wants to create voucher from image ──────────────
        final wantsVoucher = _isVoucherCreationRequest(trimmed);

        if (wantsVoucher) {
          // ── VOUCHER CREATION PATH ────────────────────────────────────────
          _pendingStreamText = '🔨 Structuring data for voucher creation…';
          _chatPhase = ChatPhase.thinking;
          notifyListeners();

          // Step 1: Ask LLM to convert raw text → JSON
          final structuringPrompt =
              VoucherImageProcessingService.buildStructuringPrompt(rawText);

          final jsonBuffer = StringBuffer();
          try {
            await AiService.instance
                .sendMessagesStream(
                  provider: _selectedProvider,
                  messages: [{'role': 'user', 'content': structuringPrompt}],
                  model: _imageSettings.analysisModel ?? _selectedModel,
                  systemPrompt:
                      'You are a JSON extractor. Return ONLY valid JSON.',
                )
                .forEach((token) => jsonBuffer.write(token));
          } catch (e) {
            _pendingStreamText = null;
            _chatPhase = ChatPhase.idle;
            _handleError(
              'Failed to structure voucher data: ${_friendlyError(e)}',
            );
            return;
          }

          // Step 2: Process with Dart (no more AI — deterministic)
          final now = DateTime.now();
          final parseResult = VoucherImageProcessingService.process(
            llmJsonResponse: jsonBuffer.toString(),
            employees: EmployeeNotifier.instance.employees,
            inferYear: now.year,
            inferMonth: now.month,
          );

          // Step 3: Apply PO number if found
          if (parseResult.extractedPoNo != null) {
            VoucherNotifier.instance.update(
              (v) => v.copyWith(poNo: parseResult.extractedPoNo),
            );
          }

          // Step 4: Create actions for resolved rows
          final actionJsons = parseResult.resolvedRows.map((row) {
            return jsonEncode({
              'action': 'add_voucher_row',
              'employeeName': row.resolvedEmployee?.name ?? row.rawName,
              'employeeId': row.resolvedEmployee?.id,
              'amount': row.amount,
              'fromDate': row.fromDate,
              'toDate': row.toDate,
              // Auto-fill bank details from resolved employee
              'ifscCode': row.resolvedEmployee?.ifscCode ?? '',
              'accountNumber': row.resolvedEmployee?.accountNumber ?? '',
              'bankDetails': row.resolvedEmployee?.bankDetails ?? '',
              'branch': row.resolvedEmployee?.branch ?? '',
              'sbCode': row.resolvedEmployee?.sbCode ?? '',
            });
          }).toList();

          // Step 5: Build response message
          final sb = StringBuffer();
          sb.writeln(
              '✅ **${parseResult.resolvedRows.length} rows ready to add** '
              'to the current voucher.\n');

          if (parseResult.extractedPoNo != null) {
            sb.writeln(
                '📄 PO Number detected: **${parseResult.extractedPoNo}** '
                '(applied to voucher)\n');
          }

          // List what will be created
          for (final row in parseResult.resolvedRows) {
            final empName =
                row.resolvedEmployee?.name ?? row.rawName;
            final warning = row.issues.isNotEmpty ? ' ⚠️' : '';
            sb.writeln(
                '- **$empName** — ₹${row.amount?.toStringAsFixed(0)} '
                '(${row.fromDate} → ${row.toDate})$warning');
          }

          if (parseResult.hasIssues) {
            sb.writeln('\n${parseResult.buildIssueReport()}');
          }

          if (actionJsons.isNotEmpty) {
            sb.writeln(
                '\n**Shall I add these ${actionJsons.length} rows to the voucher?**');
          }

          _pendingStreamText = null;
          _chatPhase = ChatPhase.idle;
          _status = ChatStatus.idle;

          _addMessage(ChatMessage(
            role: ChatRole.assistant,
            text: sb.toString(),
            timestamp: DateTime.now(),
          ));

          // Trigger confirmation dialog for the batch
          if (actionJsons.isNotEmpty) {
            await _executeToolFromAssistantResponse(
              actionJsons.map((j) => '[ACTION]$j[/ACTION]').join('\n'),
            );
          }
          notifyListeners();
          return;
        }
        // else fall through to normal image analysis path

        final userQuestion = trimmed.isEmpty
            ? 'Please summarise the key data shown in this image.'
            : trimmed;
        final analysisModel =
            _imageSettings.analysisModel ?? _selectedModel;

        _pendingStreamText = '💬 Analysing with $analysisModel…';
        _chatPhase = ChatPhase.connecting;
        notifyListeners();

        final analysisPrompt =
            '[IMAGE DATA — text extracted from the uploaded image]\n'
            '$rawText\n'
            '[END IMAGE DATA]\n\n'
            'Using the image data above, please answer: $userQuestion';

        await _startStreamingAnswer(
          messages: [
            {'role': 'user', 'content': analysisPrompt}
          ],
          model: analysisModel,
          skipVerification: true,
          systemPromptOverride: _buildImageAnalysisPrompt(),
        );
      } else {
        // ── Normal text‑only path ────────────────────────────────────────
        List<Map<String, String>> effectiveHistory = history;
        if (_activeFileContext != null) {
          effectiveHistory = _injectFileContextIntoHistory(
              history, _activeFileContext!, _activeFileName);
        }
        await _startStreamingAnswer(
          messages: effectiveHistory,
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

  // ── Batch sync helpers ───────────────────────────────────────────────────
  Future<void> _executeCurrentBatchItem() async {
    final item = BatchSyncManager.instance.current;
    if (item == null) {
      _batchSyncActive = false;
      return;
    }

    _status = ChatStatus.loading;
    notifyListeners();

    final result = await AiToolExecutor.instance.executeBatch(
      [item.actionJson],
      employeeNotifier: EmployeeNotifier.instance,
      voucherNotifier: VoucherNotifier.instance,
    );

    BatchSyncManager.instance.markProcessed();

    if (result is AiToolSuccess) {
      _addMessage(ChatMessage(
        role: ChatRole.assistant,
        text: result.confirmation,
        timestamp: DateTime.now(),
      ));
    } else if (result is AiToolFailure) {
      _addMessage(ChatMessage(
        role: ChatRole.assistant,
        text: '⚠️ Failed: ${(result as AiToolFailure).reason}',
        timestamp: DateTime.now(),
        isError: true,
      ));
    }

    _status = ChatStatus.idle;
    _presentNextBatchItem();
  }

  void _presentNextBatchItem() {
    final mgr = BatchSyncManager.instance;
    if (!mgr.hasActiveQueue) {
      _batchSyncActive = false;
      _addMessage(ChatMessage(
        role: ChatRole.assistant,
        text: mgr.completionSummary(),
        timestamp: DateTime.now(),
      ));
      notifyListeners();
      return;
    }

    _addMessage(ChatMessage(
      role: ChatRole.assistant,
      text: mgr.currentChangeCard(),
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  // ── File context injection for history ───────────────────────────────────
  List<Map<String, String>> _injectFileContextIntoHistory(
    List<Map<String, String>> history,
    FileExtractionResult extraction,
    String? fileName,
  ) {
    final contextBlock = _buildFileContextBlock(extraction, fileName);
    return [
      {
        'role': 'user',
        'content': '[ACTIVE FILE CONTEXT — injected automatically]\n$contextBlock\n'
            '[END ACTIVE FILE CONTEXT]\n\n'
            'I may ask follow-up questions about this file. '
            'Use the data above to answer them.',
      },
      {
        'role': 'assistant',
        'content': 'Understood. I have the file **$fileName** loaded and can answer questions about it.',
      },
      ...history,
    ];
  }

  String _buildFileContextBlock(
      FileExtractionResult extraction, String? fileName) {
    return '[${extraction.fileType.label.toUpperCase()} DATA — '
        'extracted from "${fileName ?? 'uploaded file'}"]\n'
        '${extraction.summaryLine}\n\n'
        '${extraction.toPromptString()}\n'
        '[END ${extraction.fileType.label.toUpperCase()} DATA]\n\n';
  }

  // ── Helper to start the final streaming response ─────────────────────────
  Future<void> _startStreamingAnswer({
    required List<Map<String, String>> messages,
    required String model,
    bool skipVerification = false,
    String? systemPromptOverride,
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

  // ── Tool execution from assistant response ────────────────────────────────
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
            text: '⚠️ Actions failed: ${(result as AiToolFailure).reason}',
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

  // ── Regenerate / Edit / Delete ───────────────────────────────────────────
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
    clearFileContext();
    notifyListeners();
  }

  // ── Private helpers ──────────────────────────────────────────────────────
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
        .replaceAll(
            RegExp(r'\[ACTION\][\s\S]*?\[/ACTION\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'`{1,3}[^`]*$', multiLine: false), '')
        .replaceAll(
            RegExp(r'^[📂💬🔍📊⏳✅]\s*[^\n]{0,80}[…\.]{1,3}\s*',
                multiLine: false),
            '')
        .replaceAll(
            RegExp(
                r'^(?:(?:Analysing|Reading|Extracting|Processing|Thinking)[^\n]*\n)+',
                caseSensitive: false),
            '')
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
          'You are a strict fact-checker for a business application.\n\n'
          'User question:\n$userQuery\n\n'
          'AI response:\n$modelResponse\n\n'
          'Reference data:\n${_context.toPromptSection()}\n\n'
          'Instructions:\n'
          '1. Check whether the response is factually consistent with the reference data.\n'
          '2. If the response is correct → reply with exactly: OK\n'
          '3. If the response contains wrong data → reply with the corrected response ONLY.';

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

  // ── History building ─────────────────────────────────────────────────────
  List<Map<String, String>> _buildValidHistory() {
    if (_messages.isEmpty) return [];

    final history = _messages.sublist(0, _messages.length - 1);
    final valid = <ChatMessage>[];
    int i = 0;

    while (i < history.length) {
      final msg = history[i];

      if (msg.role == ChatRole.assistant &&
          (msg.text.contains('[EXTRACTED_FILE]') ||
              msg.text.contains('[EXTRACTED_TEXT]') ||
              msg.text.contains('[ACTIVE FILE CONTEXT'))) {
        i++;
        continue;
      }

      if (msg.role == ChatRole.user && i + 1 < history.length) {
        final next = history[i + 1];
        if (next.role == ChatRole.assistant && !next.isError &&
            !next.text.contains('[EXTRACTED_FILE]') &&
            !next.text.contains('[EXTRACTED_TEXT]')) {
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

  // ── System prompts ───────────────────────────────────────────────────────

  String _buildImageAnalysisPrompt() => '''
You are a professional data analyst embedded in Crusam, a business management app.
The user has uploaded an image. Raw text has been extracted and provided as [IMAGE DATA].

RESPONSE RULES (NON‑NEGOTIABLE)
▸ Begin DIRECTLY — no greetings, no “Let me analyse…” phrases.
▸ State the answer on the first line with the key entity in **bold**.
▸ Use bullet points for details; markdown tables only when explicitly requested.
▸ Use ₹ for Indian Rupee amounts.
▸ Do NOT mention “image data”, “extracted text”, or internal operations.
▸ If data is unclear, say so in one sentence.
▸ Keep responses concise — answer + relevant details + one follow‑up question.
▸ Never fabricate values not present in the data.
''';

  String _buildFileAnalysisPrompt(AttachedFileType type) {
    final typeName = type.label;
    return '''
You are a professional data analyst embedded in Crusam, a business management app.
The user has uploaded a $typeName file. The full extracted text is provided as [${typeName.toUpperCase()} DATA].

RESPONSE RULES (NON‑NEGOTIABLE)
▸ Begin DIRECTLY — no greetings, no preamble.
▸ State the answer on the first line with the key entity in **bold**.
▸ Use bullet points for details; markdown tables only when explicitly requested.
▸ Use ₹ for Indian Rupee amounts.
▸ Do NOT mention “extracted text”, “the file says”, internal operations.
▸ If data is missing or unclear, say so in one sentence.
▸ Keep responses concise — answer + relevant details + one follow‑up question.
▸ Never fabricate values not present in the data.
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
1. update_employee   – Required: employeeId (int). Optional: name, zone, code,
                       designation, bankDetails, branch, pfNo, uanNo,
                       dateOfJoining, basicCharges (num), otherCharges (num).
2. delete_employee   – Required: employeeId (int).
3. add_employee      – Required: name, zone, code, designation, bankDetails,
                       branch, pfNo, uanNo, dateOfJoining,
                       basicCharges (num), otherCharges (num).
4. set_company_filter – Required: code (string, e.g. "BR039").
5. set_month_year    – Required: month (int 1‑12 or name “March”), year (int).
6. set_days_present  – Required: employeeId (int), days (int ≥ 0).
7. set_salary_meta   – Required: field (billNo | poNo | clientName |
                       clientAddr | clientGstin | deptCode), value (string).
8. set_voucher_field – Required: field (title | deptCode | date | billNo |
                       poNo | itemDescription | clientName | clientAddress |
                       clientGstin), value (string).
9. add_voucher_row   – Required: amount (num), fromDate (YYYY‑MM‑DD),
                       toDate (YYYY‑MM‑DD). Optional: employeeId (int),
                       employeeName (string), deptCode, ifscCode,
                       accountNumber, sbCode, bankDetails, branch.
10. update_voucher_row – Required: rowId or rowIndex or employeeName/fromDate/amount.
11. delete_voucher_row – Required: rowId or rowIndex or employeeName/fromDate/amount.
12. save_voucher      – No extra parameters.
13. discard_voucher   – No extra parameters.
14. approve_voucher   – No extra parameters.
15. set_company_config – Required: field and value.

**CONFIRMATION WORKFLOW (REQUIRED)**
1. Identify the target entity. If multiple matches exist, list them and ask for specification.
2. Even with exactly ONE match, output a confirmation message then include the [ACTION] block.

**Rules**
- ONLY use a tool when the user explicitly intends a data change.
- NEVER expose the [ACTION] block or JSON to the user.
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
▸ Do NOT output any commentary, greetings, or summaries — ONLY the ACTION blocks.
──────────────────────────────────────── 
''' : '';

    return '''
You are a professional auditing assistant embedded in Crusam, a business management app used by Bharat Boridkar.
Your role is to answer queries about employees, salaries, vouchers, and dashboard data — and to perform in‑app actions when asked.

════════════════════════════════════════
STRICT BEHAVIOURAL RULES (NON‑NEGOTIABLE)
════════════════════════════════════════

CONTEXT & RESUMPTION
▸ You have access to the full conversation history. Use it to understand context.
▸ If the user says “continue”, “next”, “resume”, or similar, they want to pick up the last task.
▸ If a file was uploaded earlier, its data may be re‑injected as [ACTIVE FILE CONTEXT]. Use it.

GROUNDING
▸ Every answer MUST be grounded in the provided app data below.
▸ NEVER fabricate, invent, or estimate data that is not in context.
▸ If data is absent, say: “That information is not available in the current data.”

ENTITY MATCHING
▸ Match employee names and IDs EXACTLY (case‑insensitive string match).
▸ If a name matches multiple entries, ASK for clarification before proceeding.

RESPONSE STYLE
▸ Be concise, professional, and direct.
▸ Use ₹ for currency amounts.
▸ Avoid emojis, filler phrases, and conversational language.
▸ Do NOT explain your reasoning process unless explicitly asked.

$imageInstructions

$tools

${_context.toPromptSection()}
''';
  }

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
        lower.contains('update') ||
        lower.contains('sync') ||
        lower.contains('match') ||
        lower.contains('changes');
  }
}