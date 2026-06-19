import '../../util/category_label.dart';

/// A tracked experiment — a time-boxed test of whether changing one [category]
/// of food shifts an outcome. Mirrors `ExperimentResponse` from the backend
/// experiments endpoints (`POST /api/experiments`, `GET /api/experiments/active`,
/// `POST /api/experiments/{id}/evaluate`, etc.).
///
/// [result] is null until the experiment is evaluated, at which point it carries
/// keys like `verdict`, `reason`, `adherence`, `baseline_rate`,
/// `experiment_rate`, `logged_days`.
class Experiment {
  final String id;
  final String category;
  final String categoryLabel;
  final String direction;
  final String outcomeType;
  final String outcomeName;
  final String experimentStart;
  final String experimentEnd;
  final String status;
  final Map<String, dynamic>? result;
  final String? nudgedAt;
  final double? adherence;
  final int? loggedDays;
  final bool nudgeSuggested;

  const Experiment({
    required this.id,
    required this.category,
    required this.categoryLabel,
    required this.direction,
    required this.outcomeType,
    required this.outcomeName,
    required this.experimentStart,
    required this.experimentEnd,
    required this.status,
    this.result,
    this.nudgedAt,
    this.adherence,
    this.loggedDays,
    this.nudgeSuggested = false,
  });

  factory Experiment.fromJson(Map<String, dynamic> json) {
    final rawResult = json['result'];
    return Experiment(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? '',
      categoryLabel: resolveCategoryLabel(
          json['category_label'] as String?, json['category'] as String? ?? ''),
      direction: json['direction'] as String? ?? '',
      outcomeType: json['outcome_type'] as String? ?? '',
      outcomeName: json['outcome_name'] as String? ?? '',
      experimentStart: json['experiment_start'] as String? ?? '',
      experimentEnd: json['experiment_end'] as String? ?? '',
      status: json['status'] as String? ?? '',
      result: rawResult is Map<String, dynamic> ? rawResult : null,
      nudgedAt: json['nudged_at'] as String?,
      adherence: (json['adherence'] as num?)?.toDouble(),
      loggedDays: (json['logged_days'] as num?)?.toInt(),
      nudgeSuggested: json['nudge_suggested'] as bool? ?? false,
    );
  }
}

/// An experiment the assistant proposes during the monthly trends conversation —
/// e.g. "want to test cutting out dairy for two weeks?". Nullable on a turn;
/// only present when the assistant has a concrete experiment to suggest.
///
/// Mirrors the `proposed_experiment` object from `POST /api/trends/conversation`.
class ProposedExperiment {
  final String category;
  final String categoryLabel;
  final String outcomeType;
  final String outcomeName;

  const ProposedExperiment({
    required this.category,
    required this.categoryLabel,
    required this.outcomeType,
    required this.outcomeName,
  });

  factory ProposedExperiment.fromJson(Map<String, dynamic> json) {
    return ProposedExperiment(
      category: json['category'] as String? ?? '',
      categoryLabel: resolveCategoryLabel(
          json['category_label'] as String?, json['category'] as String? ?? ''),
      outcomeType: json['outcome_type'] as String? ?? '',
      outcomeName: json['outcome_name'] as String? ?? '',
    );
  }
}
