import 'dart:async';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_provider.dart';
import 'ollama_service.dart';
import 'gemini_service.dart';

/// Provider‑agnostic AI facade that routes requests to the selected provider.
class AiService {
  AiService._();

  static final AiService instance = AiService._();

  static const String _providerKey = 'ai_provider';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<AiProvider> getSelectedProvider() async {
    final prefs = await _getPrefs();
    final id = prefs.getString(_providerKey);
    return AiProviderX.fromId(id);
  }

  Future<void> saveSelectedProvider(AiProvider provider) async {
    final prefs = await _getPrefs();
    await prefs.setString(_providerKey, provider.id);
  }

  Future<List<AiModelInfo>> getAvailableModels(AiProvider provider) async {
    switch (provider) {
      case AiProvider.ollama:
        return OllamaService.instance.fetchModels();
      case AiProvider.gemini:
        return GeminiService.instance.fetchModels();
    }
  }

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

  // ---------------------------------------------------------------------------
  // Multimodal streaming – NEW
  // ---------------------------------------------------------------------------

  /// Streams a Gemini multimodal response (image + prompt) token‑by‑token (simulated).
  /// Only supports Gemini; other providers will throw an [UnsupportedError].
  Stream<String> sendMultimodalMessageStream({
    required AiProvider provider,
    required String prompt,
    required Uint8List imageBytes,
    required String model,
    String? systemPrompt,
  }) async* {
    if (provider != AiProvider.gemini) {
      throw UnsupportedError('Image parsing is only available with Gemini.');
    }

    final fullText = await GeminiService.instance.sendMultimodalMessage(
      prompt: prompt,
      imageBytes: imageBytes,
      systemPrompt: systemPrompt,
      model: model,
    );

    const chunkSize = 4;
    const delayMs = 12;
    for (int i = 0; i < fullText.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, fullText.length);
      yield fullText.substring(i, end);
      await Future.delayed(const Duration(milliseconds: delayMs));
    }
  }

  /// Cancels any in‑flight request for the given [provider].
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