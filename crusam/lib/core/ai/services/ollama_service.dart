import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_provider.dart';

/// Singleton service for interacting with a local or remote Ollama instance.
class OllamaService {
  // Private constructor
  OllamaService._();

  /// The single instance of [OllamaService].
  static final OllamaService instance = OllamaService._();

  /// Preference key for the Ollama base URL (legacy, used for backward compatibility).
  static const String _baseUrlKey = 'ollama_base_url';

  // ── PREFS KEYS ─────────────────────────────────────────────────────────────
  static const String _serverModeKey = 'ollama_server_mode'; // 'local' | 'remote'
  static const String _remoteUrlKey  = 'ollama_remote_url';  // e.g. http://192.168.1.5:11434

  /// The default base URL for Ollama when running locally.
  static const String defaultBaseUrl = 'http://127.0.0.1:11434';

  SharedPreferences? _prefs;

  /// The client used for the current chat completion request.
  http.Client? _currentClient;

  /// Indicates whether the current request has been cancelled.
  bool _cancelled = false;

  /// Lazily load and return [SharedPreferences].
  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── MODE-AWARE getBaseUrl ─────────────────────────────────────────────────
  /// Returns the active Ollama base URL based on the current server mode.
  ///
  /// In 'remote' mode the saved remote URL is used; in 'local' mode (default)
  /// `http://127.0.0.1:11434` is returned.
  Future<String> getBaseUrl() async {
    final mode = await getServerMode();
    if (mode == 'remote') {
      final remote = await getRemoteUrl();
      if (remote.isNotEmpty) return remote;
    }
    // local mode (default)
    return defaultBaseUrl;
  }

  // ── OLD saveBaseUrl (kept for backward compatibility) ──────────────────────
  /// Persists a legacy base URL. New code should prefer `saveRemoteUrl`.
  Future<void> saveBaseUrl(String url) async {
    final prefs = await _getPrefs();
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_baseUrlKey, trimmed);
  }

  // ── NEW: Server mode ───────────────────────────────────────────────────────
  /// Returns the current server mode: 'local' or 'remote'.
  Future<String> getServerMode() async {
    final prefs = await _getPrefs();
    return prefs.getString(_serverModeKey) ?? 'local';
  }

  /// Sets the server mode to [mode] (expected: 'local' or 'remote').
  Future<void> saveServerMode(String mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_serverModeKey, mode);
  }

  // ── NEW: Remote URL ────────────────────────────────────────────────────────
  /// Returns the saved remote Ollama URL, or an empty string if none is set.
  Future<String> getRemoteUrl() async {
    final prefs = await _getPrefs();
    return prefs.getString(_remoteUrlKey) ?? '';
  }

  /// Persists a new remote Ollama URL. Trailing slashes are stripped.
  Future<void> saveRemoteUrl(String url) async {
    final prefs = await _getPrefs();
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_remoteUrlKey, trimmed);
  }

  // ── NEW: Connection test ───────────────────────────────────────────────────
  /// Tests whether an Ollama instance is reachable at [url].
  ///
  /// Hits `/api/tags` with a 5-second timeout. Returns `true` on success.
  Future<bool> testConnection(String url) async {
    try {
      final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
      final uri   = Uri.parse('$clean/api/tags');
      final resp  = await http.get(uri).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the list of locally installed models via `GET /api/tags`.
  Future<List<AiModelInfo>> fetchModels() async {
    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/tags');

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw OllamaException(
          'Failed to fetch models. Status code: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final modelsList = data['models'] as List<dynamic>?;
      if (modelsList == null) {
        return <AiModelInfo>[];
      }

      return modelsList.map((m) {
        final name = (m as Map<String, dynamic>)['name'] as String? ?? '';
        return AiModelInfo(id: name, label: name);
      }).toList();
    } catch (e) {
      if (e is OllamaException) rethrow;
      throw OllamaException(
        'Could not connect to Ollama. '
        'Make sure Ollama is running and the base URL is correct.',
      );
    }
  }

  /// Known vision-capable model keywords.
  /// Add more if needed (e.g., 'internvl', 'yi-vl').
  static const List<String> visionModelKeywords = [
    'minicpm',
    'llava',
    'internvl',
    'yi-vl',
    'qwen-vl',
    'vision',
  ];

  /// Checks if a model name suggests it's vision-capable.
  /// Compares against known vision model keywords (case-insensitive).
  bool _isLikelyVisionModel(String modelName) {
    final lower = modelName.toLowerCase();
    return visionModelKeywords.any((keyword) => lower.contains(keyword));
  }

  /// Fetches and filters for vision-capable (image-processing) models.
  /// Returns models that match known vision model patterns.
  Future<List<AiModelInfo>> getAvailableImageModels() async {
    try {
      final allModels = await fetchModels();
      final visionModels = allModels
          .where((model) => _isLikelyVisionModel(model.id))
          .toList();
      return visionModels;
    } catch (_) {
      // If fetch fails, return an empty list (caller should handle)
      return <AiModelInfo>[];
    }
  }

  /// Checks if a specific model is vision-capable (for validation).
  Future<bool> isVisionModel(String modelName) async {
    final allModels = await fetchModels();
    final exists =
        allModels.any((m) => m.id == modelName);
    if (!exists) return false; // model not found at all
    return _isLikelyVisionModel(modelName);
  }

  /// Sends a multimodal message with fallback logic.
  /// If [model] fails or is not available, tries fallback models.
  ///
  /// Returns the extracted/processed text.
  /// Throws [OllamaException] if all attempts fail.
  /// 
  /// **NEW**: Accepts an optional [timeout] duration. Each attempt will be
  /// aborted after this duration. Defaults to 30 seconds.
  Future<String> sendMultimodalMessageWithFallback({
    required String prompt,
    required Uint8List imageBytes,
    required String model,
    String? systemPrompt,
    List<String>? fallbackModels,
    Duration? timeout,                 // NEW
  }) async {
    final modelsToTry = [
      model,
      ...?fallbackModels,
      'minicpm-v:8b', // ultimate fallback
    ];

    OllamaException? lastError;

    for (final currentModel in modelsToTry) {
      try {
        return await sendMultimodalMessage(
          prompt: prompt,
          imageBytes: imageBytes,
          model: currentModel,
          systemPrompt: systemPrompt,
          timeout: timeout,            // pass through
        );
      } on OllamaCancelledException {
        rethrow; // don't catch user cancellations
      } on OllamaException catch (e) {
        lastError = e;
        // Log and continue to next fallback model
        debugPrint(
          'Image extraction failed with model "$currentModel": ${e.message}. '
          'Trying next model...',
        );
        continue;
      }
    }

    // All models failed
    throw OllamaException(
      'Image extraction failed with all available models. '
      'Last error: ${lastError?.message ?? "Unknown"}. '
      'Ensure a vision model (minicpm-v, llava, etc.) is installed and running.',
    );
  }

  /// Sends a chat request to Ollama via `POST /api/chat`.
  /// Returns the complete response as a single string.
  Future<String> sendMessages({
    required List<Map<String, String>> messages,
    required String model,
    String? systemPrompt,
  }) async {
    cancelCurrentRequest();
    _currentClient = http.Client();
    _cancelled = false;

    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/chat');

    final List<Map<String, String>> payload = [];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      payload.add({'role': 'system', 'content': systemPrompt.trim()});
    }
    payload.addAll(messages);

    try {
      final response = await _currentClient!.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'stream': false,
          'messages': payload,
        }),
      );

      if (_cancelled) {
        throw OllamaCancelledException('Request was cancelled.');
      }

      if (response.statusCode != 200) {
        throw OllamaException(
          'Ollama returned an error (${response.statusCode}): '
          '${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['message']?['content'] as String?;

      if (content == null || content.trim().isEmpty) {
        throw OllamaException('Ollama returned an empty response.');
      }

      return content;
    } catch (e) {
      if (_cancelled) {
        throw OllamaCancelledException('Request was cancelled.');
      }
      if (e is OllamaException || e is OllamaCancelledException) {
        rethrow;
      }
      throw OllamaException(
        'Could not connect to Ollama. '
        'Make sure Ollama is running and the base URL is correct.',
      );
    } finally {
      _currentClient?.close();
      _currentClient = null;
      _cancelled = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Multimodal message (image + prompt) – for minicpm-v and similar VLMs
  // ---------------------------------------------------------------------------

  /// Sends a text prompt together with an image to a vision-capable Ollama model
  /// (e.g. `minicpm-v:8b`) and returns the full response as a single string.
  ///
  /// The image is passed via the `images` field of the Ollama chat message, which
  /// accepts a list of base-64 encoded strings (no data-URI prefix required).
  ///
  /// This call is **not** streamed; it blocks until Ollama returns the complete
  /// response.  Use [sendMultimodalExtractionStream] for real-time feedback.
  ///
  /// The call honours [cancelCurrentRequest]: if cancelled while awaiting the
  /// response, an [OllamaCancelledException] is thrown.
  ///
  /// **NEW**: The [timeout] parameter limits the HTTP request duration.
  /// Defaults to 30 seconds if not supplied.
  Future<String> sendMultimodalMessage({
    required String prompt,
    required Uint8List imageBytes,
    required String model,
    String? systemPrompt,
    Duration? timeout,               // NEW
  }) async {
    cancelCurrentRequest();
    _currentClient = http.Client();
    _cancelled = false;

    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/chat');

    // Ollama expects a plain base-64 string inside the `images` array —
    // no "data:image/jpeg;base64," prefix.
    final base64Image = base64Encode(imageBytes);

    final List<Map<String, dynamic>> payload = [];

    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      payload.add({
        'role': 'system',
        'content': systemPrompt.trim(),
      });
    }

    payload.add({
      'role': 'user',
      'content': prompt,
      'images': [base64Image],
    });

    try {
      final response = await _currentClient!.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'stream': false,
          'messages': payload,
        }),
      ).timeout(timeout ?? const Duration(seconds: 30));   // timeout applied

      if (_cancelled) {
        throw OllamaCancelledException('Request was cancelled.');
      }

      if (response.statusCode != 200) {
        throw OllamaException(
          'Ollama returned an error (${response.statusCode}): '
          '${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['message']?['content'] as String?;

      if (content == null || content.trim().isEmpty) {
        throw OllamaException('Ollama returned an empty response.');
      }

      return content;
    } on http.ClientException catch (e) {
      // Timeout errors manifest as ClientException with "Closed" or similar
      throw OllamaException('Image extraction timed out: $e');
    } catch (e) {
      if (_cancelled) throw OllamaCancelledException('Request was cancelled.');
      if (e is OllamaException || e is OllamaCancelledException) rethrow;
      throw OllamaException(
        'Could not connect to Ollama. '
        'Make sure Ollama is running and the base URL is correct.',
      );
    } finally {
      _currentClient?.close();
      _currentClient = null;
      _cancelled = false;
    }
  }

  // ---------------------------------------------------------------------------
  // STREAMING MULTIMODAL EXTRACTION (real‑time token streaming)
  // ---------------------------------------------------------------------------

  /// Streams raw text tokens from a vision model (image + prompt) in real time.
  ///
  /// This method uses `stream: true` and emits each token as it arrives from the
  /// SSE/NDJSON endpoint, providing immediate feedback to the caller.
  ///
  /// Callers can use this to display a live preview of the extracted text.
  Stream<String> sendMultimodalExtractionStream({
    required String prompt,
    required Uint8List imageBytes,
    required String model,
    String? systemPrompt,
    Duration? timeout,
  }) async* {
    cancelCurrentRequest();
    final client = http.Client();
    _currentClient = client;
    _cancelled = false;

    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/chat');

    final base64Image = base64Encode(imageBytes);

    final List<Map<String, dynamic>> payload = [];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      payload.add({'role': 'system', 'content': systemPrompt.trim()});
    }
    payload.add({
      'role': 'user',
      'content': prompt,
      'images': [base64Image],
    });

    final effectiveTimeout = timeout ?? const Duration(seconds: 60);

    try {
      final request = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': model,
          'stream': true,
          'messages': payload,
        });

      // ── FIX: apply timeout to client.send() ──────────────────────────
      // Without this, if Ollama is loading minicpm-v into VRAM (cold start)
      // the app hangs on this line indefinitely.
      final streamedResponse = await client
          .send(request)
          .timeout(
            effectiveTimeout,
            onTimeout: () {
              client.close();
              throw OllamaException(
                'Image extraction timed out after ${effectiveTimeout.inSeconds}s. '
                'Ollama may still be loading the vision model into memory. '
                'Try again in a few seconds.',
              );
            },
          );
      // ─────────────────────────────────────────────────────────────────

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw OllamaException(
          'Ollama returned ${streamedResponse.statusCode}: $errorBody',
        );
      }

      final lines = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (_cancelled) break;
        if (line.isEmpty) continue;

        // Handle both plain NDJSON and SSE-formatted lines
        String jsonLine = line;
        if (jsonLine.startsWith('data: ')) {
          jsonLine = jsonLine.substring(6);
        }
        if (jsonLine.trim() == '[DONE]') break;

        try {
          final data = jsonDecode(jsonLine) as Map<String, dynamic>;
          if (data['done'] == true) break;
          final content = data['message']?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // Skip unparseable lines (e.g. empty, comments)
        }
      }
    } catch (e) {
      if (_cancelled) throw OllamaCancelledException('Extraction cancelled.');
      if (e is OllamaException || e is OllamaCancelledException) rethrow;
      throw OllamaException('Image extraction stream failed: $e');
    } finally {
      if (_currentClient == client) _currentClient = null;
      client.close();
      _cancelled = false;
    }
  }

  /// Simulated token-by-token streaming wrapper around [sendMultimodalMessage].
  /// (kept for backward compatibility)
  Stream<String> sendMultimodalMessageStream({
    required String prompt,
    required Uint8List imageBytes,
    required String model,
    String? systemPrompt,
    Duration? timeout,               // NEW
  }) async* {
    final fullText = await sendMultimodalMessage(
      prompt: prompt,
      imageBytes: imageBytes,
      model: model,
      systemPrompt: systemPrompt,
      timeout: timeout,
    );

    const chunkSize = 4;
    const delayMs = 12;

    for (int i = 0; i < fullText.length; i += chunkSize) {
      if (_cancelled) break;
      final end = (i + chunkSize).clamp(0, fullText.length);
      yield fullText.substring(i, end);
      await Future.delayed(const Duration(milliseconds: delayMs));
    }
  }

  // ---------------------------------------------------------------------------
  // Real token-by-token streaming via Ollama's SSE / NDJSON endpoint.
  // ---------------------------------------------------------------------------

  /// Streams tokens from Ollama using `stream: true`.
  ///
  /// Now correctly handles SSE lines that start with `data: ` and
  /// the `[DONE]` sentinel.
  Stream<String> sendMessagesStream({
    required List<Map<String, String>> messages,
    required String model,
    String? systemPrompt,
  }) async* {
    cancelCurrentRequest();
    final client = http.Client();
    _currentClient = client;
    _cancelled = false;

    final baseUrl = await getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/chat');

    final List<Map<String, String>> payload = [];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      payload.add({'role': 'system', 'content': systemPrompt.trim()});
    }
    payload.addAll(messages);

    try {
      final request = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': model,
          'stream': true,
          'messages': payload,
        });

      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw OllamaException(
          'Ollama returned an error (${streamedResponse.statusCode})',
        );
      }

      final lines = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (_cancelled) break;
        if (line.isEmpty) continue;

        // ---------- SSE fix ----------
        String jsonLine = line;
        if (jsonLine.startsWith('data: ')) {
          jsonLine = jsonLine.substring(6);
        }
        if (jsonLine.trim() == '[DONE]') break;
        // -----------------------------

        try {
          final data = jsonDecode(jsonLine) as Map<String, dynamic>;
          if (data['done'] == true) break;
          final content = data['message']?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // Skip any line that cannot be parsed (e.g. comment lines).
        }
      }
    } catch (e) {
      if (_cancelled) throw OllamaCancelledException('Request was cancelled.');
      if (e is OllamaException || e is OllamaCancelledException) rethrow;
      throw OllamaException(
        'Could not connect to Ollama. '
        'Make sure Ollama is running and the base URL is correct.',
      );
    } finally {
      if (_currentClient == client) _currentClient = null;
      client.close();
      _cancelled = false;
    }
  }

  /// Cancels the in-flight chat request, if any.
  void cancelCurrentRequest() {
    if (_currentClient != null) {
      _cancelled = true;
      _currentClient!.close();
      _currentClient = null;
    }
  }
}

/// Exception thrown when an Ollama API call fails.
class OllamaException implements Exception {
  final String message;
  const OllamaException(this.message);

  @override
  String toString() => 'OllamaException: $message';
}

/// Exception thrown when an Ollama request is cancelled by the user.
class OllamaCancelledException implements Exception {
  final String message;
  const OllamaCancelledException(this.message);

  @override
  String toString() => 'OllamaCancelledException: $message';
}