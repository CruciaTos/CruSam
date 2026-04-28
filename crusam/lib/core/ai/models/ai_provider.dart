/// Shared provider and model types for the AI layer.
/// Used by services, notifiers, and UI to avoid coupling to a specific provider.
enum AiProvider {
  ollama,
  gemini,
}

/// Extension to expose display properties and parser helpers.
extension AiProviderX on AiProvider {
  /// Lowercase provider identifier.
  String get id {
    switch (this) {
      case AiProvider.ollama:
        return 'ollama';
      case AiProvider.gemini:
        return 'gemini';
    }
  }

  /// Human-readable label for the UI.
  String get label {
    switch (this) {
      case AiProvider.ollama:
        return 'Ollama';
      case AiProvider.gemini:
        return 'Gemini';
    }
  }

  /// Whether this provider requires an API key to operate.
  bool get requiresApiKey {
    switch (this) {
      case AiProvider.ollama:
        return false;
      case AiProvider.gemini:
        return true;
    }
  }

  /// Parse a provider from a raw ID string.
  /// Defaults to [AiProvider.ollama] if null or unknown.
  static AiProvider fromId(String? raw) {
    if (raw == null) return AiProvider.ollama;
    for (final provider in AiProvider.values) {
      if (provider.id == raw) return provider;
    }
    return AiProvider.ollama;
  }
}

/// Simple model info used to list available models from a provider.
class AiModelInfo {
  final String id;
  final String label;

  const AiModelInfo({required this.id, required this.label});
}