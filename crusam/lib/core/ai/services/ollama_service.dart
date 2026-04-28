import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_provider.dart';

/// Singleton service for interacting with a local Ollama instance.
class OllamaService {
  // Private constructor
  OllamaService._();

  /// The single instance of [OllamaService].
  static final OllamaService instance = OllamaService._();

  /// Preference key for the Ollama base URL.
  static const String _baseUrlKey = 'ollama_base_url';

  /// The default base URL for Ollama.
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

  /// Returns the saved base URL or the default.
  Future<String> getBaseUrl() async {
    final prefs = await _getPrefs();
    final url = prefs.getString(_baseUrlKey);
    if (url == null || url.trim().isEmpty) {
      return defaultBaseUrl;
    }
    return url.trim().replaceAll(RegExp(r'/+$'), '');
  }

  /// Persists a new base URL for Ollama.
  Future<void> saveBaseUrl(String url) async {
    final prefs = await _getPrefs();
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_baseUrlKey, trimmed);
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