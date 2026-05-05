import 'dart:convert';

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

  // ── NEW PREFS KEYS ─────────────────────────────────────────────────────────
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

  // ── MODE-AWARE getBaseUrl ───────────────────────────────────────────────────
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
    return defaultBaseUrl; // 'http://127.0.0.1:11434'
  }

  // ── OLD saveBaseUrl (kept for backward compatibility) ────────────────────────
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
  // NEW: Real token-by-token streaming via Ollama's SSE / NDJSON endpoint.
  // ---------------------------------------------------------------------------

  /// Streams tokens from Ollama using `stream: true`.
  ///
  /// Yields each content chunk as it arrives so the UI can render
  /// a typewriter effect in real time.
  ///
  /// The stream can be cancelled by calling [cancelCurrentRequest].
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

      // Ollama streams newline-delimited JSON (NDJSON).
      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (_cancelled) break;
        if (line.trim().isEmpty) continue;

        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          if (data['done'] == true) break;
          final content = data['message']?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // Skip any malformed JSON lines.
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