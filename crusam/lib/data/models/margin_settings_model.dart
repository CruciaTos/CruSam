class MarginSettings {
  final double top;
  final double bottom;
  final double left;
  final double right;

  const MarginSettings({
    this.top = 24,
    this.bottom = 24,
    this.left = 24,
    this.right = 24,
  });

  MarginSettings copyWith({
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) => MarginSettings(
    top: top ?? this.top,
    bottom: bottom ?? this.bottom,
    left: left ?? this.left,
    right: right ?? this.right,
  );

  factory MarginSettings.fromMap(Map<String, dynamic> m) => MarginSettings(
    top: (m['margin_top'] as num?)?.toDouble() ?? 24,
    bottom: (m['margin_bottom'] as num?)?.toDouble() ?? 24,
    left: (m['margin_left'] as num?)?.toDouble() ?? 24,
    right: (m['margin_right'] as num?)?.toDouble() ?? 24,
  );

  Map<String, dynamic> toMap() => {
    'margin_top': top,
    'margin_bottom': bottom,
    'margin_left': left,
    'margin_right': right,
  };
}
