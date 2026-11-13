import 'classification.dart';

/// One factor of the simplified SHAP explanation: the backend already ranks
/// the model's XGBoost-member contributions by |SHAP| and returns the top 3
/// with a plain-language label and the direction the factor pushed the
/// estimate. Model attribution, not causation (see [PredictionReading.explanationNote]).
class ExplanationFactor {
  const ExplanationFactor({
    required this.feature,
    required this.label,
    required this.pushedHigher,
    this.shapLog,
  });

  final String feature;
  final String label;
  final bool pushedHigher;

  /// Signed SHAP value in the model's log1p output space (already part of
  /// the backend payload). Used only to size a relative magnitude bar
  /// against the other displayed factors; never shown as a number.
  final double? shapLog;

  double get magnitude => (shapLog ?? 0).abs();

  factory ExplanationFactor.fromJson(Map<String, dynamic> json) {
    return ExplanationFactor(
      feature: json['feature'] as String? ?? '',
      label: json['label'] as String? ?? (json['feature'] as String? ?? ''),
      pushedHigher: (json['direction'] as String? ?? 'higher') == 'higher',
      shapLog: (json['shap_log'] as num?)?.toDouble(),
    );
  }
}

/// The mobile reading returned by POST /api/mobile/prediction.
///
/// `asOfLocalLabel` is the timestamp the estimate is FOR (T*: the latest
/// hour with complete environmental data), in Philippine time -- the UI
/// always shows "Estimated PM2.5 as of that time", never "current".
class PredictionReading {
  const PredictionReading({
    required this.status,
    required this.cellId,
    required this.asOfUtc,
    required this.asOfLocalLabel,
    required this.stalenessHours,
    required this.pm25,
    required this.units,
    required this.classification,
    required this.dataNote,
    required this.nMissingFeatures,
    required this.nFeatures,
    required this.explanationAvailable,
    required this.topFactors,
    required this.explanationNote,
    required this.fromCache,
    required this.message,
  });

  final String status; // "ok" | "unavailable"
  final String cellId;
  final DateTime? asOfUtc;
  final String asOfLocalLabel;
  final double? stalenessHours;
  final double? pm25;
  final String units;
  final Classification? classification;
  final String dataNote;
  final int? nMissingFeatures;
  final int? nFeatures;
  final bool explanationAvailable;
  final List<ExplanationFactor> topFactors;
  final String explanationNote;
  final bool fromCache;
  final String? message;

  bool get hasValue => status == 'ok' && pm25 != null;

  /// Whole days between the estimate's timestamp and now, for the
  /// "N days behind real time" note.
  int? get stalenessDays => stalenessHours == null ? null : (stalenessHours! / 24).floor();

  factory PredictionReading.fromJson(Map<String, dynamic> json) {
    final explanation = json['explanation'] as Map<String, dynamic>? ?? const {};
    final factors = (explanation['top_factors'] as List<dynamic>? ?? const [])
        .map((f) => ExplanationFactor.fromJson(f as Map<String, dynamic>))
        .toList();
    final classificationJson = json['classification'] as Map<String, dynamic>?;
    return PredictionReading(
      status: json['status'] as String? ?? 'unavailable',
      cellId: json['cell_id'] as String? ?? '',
      asOfUtc: json['as_of_utc'] != null ? DateTime.tryParse(json['as_of_utc'] as String) : null,
      asOfLocalLabel: json['as_of_local_label'] as String? ?? '',
      stalenessHours: (json['staleness_hours'] as num?)?.toDouble(),
      pm25: (json['pm25_ugm3'] as num?)?.toDouble(),
      units: json['units'] as String? ?? 'µg/m³',
      classification: classificationJson == null ? null : Classification.fromJson(classificationJson),
      dataNote: json['data_note'] as String? ?? '',
      nMissingFeatures: (json['n_missing_features'] as num?)?.toInt(),
      nFeatures: (json['n_features'] as num?)?.toInt(),
      explanationAvailable: explanation['available'] as bool? ?? false,
      topFactors: factors,
      explanationNote: explanation['note'] as String? ?? '',
      fromCache: json['from_cache'] as bool? ?? false,
      message: json['message'] as String?,
    );
  }
}
