import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_provider.dart';
import 'ollama_service.dart';
import 'gemini_service.dart';

/// Provider-agnostic AI facade that routes requests to the selected provider.
class AiService {
  AiService._();

  /// The single instance of [AiService].
  static final AiService instance = AiService._();

  static const String _providerKey = 'ai_provider';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Returns the currently saved AI provider, defaulting to [AiProvider.ollama].
  Future<AiProvider> getSelectedProvider() async {
    final prefs = await _getPrefs();
    final id = prefs.getString(_providerKey);
    return AiProviderX.fromId(id);
  }

  /// Saves the given [provider] to preferences.
  Future<void> saveSelectedProvider(AiProvider provider) async {
    final prefs = await _getPrefs();
    await prefs.setString(_providerKey, provider.id);
  }

  /// Fetches available models for the given [provider].
  Future<List<AiModelInfo>> getAvailableModels(AiProvider provider) async {
    switch (provider) {
      case AiProvider.ollama:
        return OllamaService.instance.fetchModels();
      case AiProvider.gemini:
        return GeminiService.instance.fetchModels();
    }
  }

  /// Sends a list of [messages] to the AI [provider] and returns the full
  /// response as a single string (non-streaming).
  Future<String> sendMessages({
    required AiProvider provider,
    required List<Map<String, String>> messages,
    required String model,
    String? systemPrompt,
  }) async {
    switch (provider) {
      case AiProvider.ollama:
        return OllamaService.instance.sendMessages(
          messages: messages,
          model: model,
          systemPrompt: systemPrompt,
        );
      case AiProvider.gemini:
        final contents = _toGeminiContents(messages);
        return GeminiService.instance.sendMessages(
          model: model,
          messages: contents,
          systemPrompt: systemPrompt,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // NEW: Streaming facade — routes to the appropriate stream implementation.
  // ---------------------------------------------------------------------------

  /// Streams response tokens from the AI [provider] one chunk at a time.
  ///
  /// For Ollama this is true server-side streaming (NDJSON).
  /// For Gemini this is pseudo-streaming (full response fetched, then yielded
  /// in small chunks) because the Gemini REST API requires a different setup
  /// for real SSE.
  ///
  /// The returned [Stream<String>] yields successive text chunks that should
  /// be appended together to form the complete reply.
  Stream<String> sendMessagesStream({
    required AiProvider provider,
    required List<Map<String, String>> messages,
    required String model,
    String? systemPrompt,
  }) {
    switch (provider) {
      case AiProvider.ollama:
        return OllamaService.instance.sendMessagesStream(
          messages: messages,
          model: model,
          systemPrompt: systemPrompt,
        );
      case AiProvider.gemini:
        final contents = _toGeminiContents(messages);
        return GeminiService.instance.sendMessagesStream(
          model: model,
          messages: contents,
          systemPrompt: systemPrompt,
        );
    }
  }

  /// Cancels any in-flight request for the given [provider].
  void cancelCurrentRequest(AiProvider provider) {
    switch (provider) {
      case AiProvider.ollama:
        OllamaService.instance.cancelCurrentRequest();
        break;
      case AiProvider.gemini:
        GeminiService.instance.cancelCurrentRequest();
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Converts the generic `{role, content}` message format to Gemini's
  /// `contents` format (`role` with `parts[{text}]`), swapping `assistant`
  /// to `model` as required by the Gemini API.
  List<Map<String, dynamic>> _toGeminiContents(
    List<Map<String, String>> messages,
  ) {
    return messages.map((msg) {
      final role = msg['role']!;
      final geminiRole = role == 'assistant' ? 'model' : role;
      return {
        'role': geminiRole,
        'parts': [
          {'text': msg['content']},
        ],
      };
    }).toList();
  }
}