import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_provider.dart';

/// Low-level wrapper around the Gemini generateContent REST endpoint.
class GeminiService {
  GeminiService._();
  static final GeminiService instance = GeminiService._();

  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  static const _prefKey = 'gemini_api_key';

  // ---------------------------------------------------------------------------
  // Available models
  // ---------------------------------------------------------------------------
  static const String model15Flash = 'gemini-1.5-flash-latest';
  static const String model15Pro = 'gemini-1.5-pro-latest';
  static const String model20Flash = 'gemini-2.0-flash';
  static const String model25Flash = 'gemini-2.5-flash';
  static const String model25Pro = 'gemini-2.5-pro';

  Future<List<AiModelInfo>> fetchModels() async {
    return const [
      AiModelInfo(id: model15Flash, label: 'Gemini 1.5 Flash'),
      AiModelInfo(id: model15Pro, label: 'Gemini 1.5 Pro'),
      AiModelInfo(id: model20Flash, label: 'Gemini 2.0 Flash'),
      AiModelInfo(id: model25Flash, label: 'Gemini 2.5 Flash'),
      AiModelInfo(id: model25Pro, label: 'Gemini 2.5 Pro'),
    ];
  }

  // ---------------------------------------------------------------------------
  // API key management
  // ---------------------------------------------------------------------------

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, key.trim());
  }

  Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  // ---------------------------------------------------------------------------
  // Cancellation support
  // ---------------------------------------------------------------------------
  http.Client? _activeClient;
  bool _streamCancelled = false;

  /// Cancels any in‑flight request to Gemini.
  void cancelCurrentRequest() {
    _streamCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  // ---------------------------------------------------------------------------
  // Core request (fixed: reset _streamCancelled at start)
  // ---------------------------------------------------------------------------

  Future<String> sendMessages({
    required List<Map<String, dynamic>> messages,
    String? systemPrompt,
    String model = model15Flash,
  }) async {
    // ── FIX: reset cancellation flag before a new request ────────────
    _streamCancelled = false;

    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw GeminiException(
        code: 'NO_API_KEY',
        message: 'No Gemini API key configured.',
      );
    }

    final url = Uri.parse(
      '$_baseUrl/models/$model:generateContent?key=$apiKey',
    );

    final body = <String, dynamic>{
      'contents': messages,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 1024,
      },
    };

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemPrompt}
        ],
      };
    }

    final client = http.Client();
    _activeClient = client;

    try {
      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        final decoded = _tryDecode(response.body);
        final errMsg = decoded?['error']?['message'] as String? ??
            'HTTP ${response.statusCode}';
        throw GeminiException(
          code: 'API_ERROR_${response.statusCode}',
          message: errMsg,
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidatesRaw = decoded['candidates'];
      final candidates = (candidatesRaw is List)
          ? candidatesRaw.cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final firstCandidate = candidates.isNotEmpty ? candidates.first : null;
      final content = firstCandidate?['content'] as Map<String, dynamic>?;
      final partsRaw = content?['parts'];
      final parts = (partsRaw is List)
          ? partsRaw.cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final firstPart = parts.isNotEmpty ? parts.first : null;
      final text = firstPart?['text'] as String?;

      if (text == null || text.isEmpty) {
        throw GeminiException(
          code: 'EMPTY_RESPONSE',
          message: 'Gemini returned an empty response.',
        );
      }

      return text;
    } on http.ClientException {
      throw GeminiCancelledException();
    } finally {
      if (_activeClient == client) _activeClient = null;
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Pseudo-streaming for Gemini
  // ---------------------------------------------------------------------------

  /// Streams the Gemini response token-by-token (simulated).
  ///
  /// Fetches the full response first, then yields small character chunks
  /// with a short delay to produce a natural typewriter effect.
  Stream<String> sendMessagesStream({
    required List<Map<String, dynamic>> messages,
    String? systemPrompt,
    String model = model15Flash,
  }) async* {
    _streamCancelled = false;

    // Fetch the full response first.
    final fullText = await sendMessages(
      messages: messages,
      systemPrompt: systemPrompt,
      model: model,
    );

    // Yield in small chunks to create the typewriter effect.
    const chunkSize = 4;
    const delayMs = 12;

    for (int i = 0; i < fullText.length; i += chunkSize) {
      if (_streamCancelled) break;
      final end = (i + chunkSize).clamp(0, fullText.length);
      yield fullText.substring(i, end);
      await Future.delayed(const Duration(milliseconds: delayMs));
    }
  }

  Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

class GeminiException implements Exception {
  const GeminiException({required this.code, required this.message});
  final String code;
  final String message;
  @override
  String toString() => 'GeminiException($code): $message';
}

/// Thrown when a request is cancelled by the user.
class GeminiCancelledException implements Exception {
  const GeminiCancelledException();
  @override
  String toString() => 'GeminiCancelledException: Request cancelled by user';
}