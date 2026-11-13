/// The classification block of a mobile reading, exactly as the backend
/// serves it (config/pm25_classification.py -> backend/mobile.py). The app
/// never defines thresholds, labels or guidance itself: the backend applies
/// the fixed mobile scheme (US EPA 2024 PM2.5 AQI categories) and sends
/// the resulting category, interpretation, protective guidance and the
/// hourly-vs-24-hour basis caveat. Presentation only.
class Classification {
  const Classification({
    required this.schemeId,
    required this.schemeName,
    required this.category,
    required this.colorHex,
    required this.interpretation,
    required this.guidance,
    required this.basisNote,
  });

  final String schemeId;
  final String schemeName;
  final String category;
  final String colorHex;
  final String interpretation;
  final String guidance;
  final String basisNote;

  factory Classification.fromJson(Map<String, dynamic> json) {
    return Classification(
      schemeId: json['scheme_id'] as String? ?? '',
      schemeName: json['scheme_name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      colorHex: json['color'] as String? ?? '#9ca3af',
      interpretation: json['interpretation'] as String? ?? '',
      guidance: json['guidance'] as String? ?? '',
      basisNote: json['basis_note'] as String? ?? '',
    );
  }
}
