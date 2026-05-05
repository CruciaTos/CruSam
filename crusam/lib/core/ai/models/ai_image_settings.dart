/// Settings model for multimodal image processing configuration.
class AiImageSettings {
  final String imageProcessingModel;  // e.g., 'minicpm-v:8b', 'llava', 'internvl'
  final String? analysisModel;        // optional; if null, uses user's selected model
  final int maxExtractionRetries;     // max attempts if extraction fails (default: 2)
  final int extractionTimeoutSeconds; // timeout for extraction (default: 30s)
  final bool enableImageProcessing;   // master toggle for image feature

  const AiImageSettings({
    this.imageProcessingModel = 'minicpm-v:8b',
    this.analysisModel,
    this.maxExtractionRetries = 2,
    this.extractionTimeoutSeconds = 30,
    this.enableImageProcessing = true,
  });

  /// Copy with method for updates
  AiImageSettings copyWith({
    String? imageProcessingModel,
    String? analysisModel,
    int? maxExtractionRetries,
    int? extractionTimeoutSeconds,
    bool? enableImageProcessing,
  }) =>
      AiImageSettings(
        imageProcessingModel:
            imageProcessingModel ?? this.imageProcessingModel,
        analysisModel: analysisModel ?? this.analysisModel,
        maxExtractionRetries:
            maxExtractionRetries ?? this.maxExtractionRetries,
        extractionTimeoutSeconds:
            extractionTimeoutSeconds ?? this.extractionTimeoutSeconds,
        enableImageProcessing: enableImageProcessing ?? this.enableImageProcessing,
      );

  /// Convert to map for storage
  Map<String, dynamic> toMap() => {
    'imageProcessingModel': imageProcessingModel,
    'analysisModel': analysisModel,
    'maxExtractionRetries': maxExtractionRetries,
    'extractionTimeoutSeconds': extractionTimeoutSeconds,
    'enableImageProcessing': enableImageProcessing,
  };

  /// Create from map (e.g., from SharedPreferences)
  factory AiImageSettings.fromMap(Map<String, dynamic> map) =>
      AiImageSettings(
        imageProcessingModel:
            (map['imageProcessingModel'] as String?) ?? 'minicpm-v:8b',
        analysisModel: map['analysisModel'] as String?,
        maxExtractionRetries: (map['maxExtractionRetries'] as int?) ?? 2,
        extractionTimeoutSeconds:
            (map['extractionTimeoutSeconds'] as int?) ?? 30,
        enableImageProcessing:
            (map['enableImageProcessing'] as bool?) ?? true,
      );

  /// Default instance
  static const AiImageSettings defaults = AiImageSettings();

  @override
  String toString() =>
      'AiImageSettings(model=$imageProcessingModel, retries=$maxExtractionRetries, '
      'timeout=${extractionTimeoutSeconds}s, enabled=$enableImageProcessing)';
}
