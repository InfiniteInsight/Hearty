/// A verdict the assistant proposes during the monthly trends conversation —
/// e.g. "dairy seems to trigger your bloating, confirm?". Nullable on a turn;
/// only present when the assistant has a concrete signal to put to the user.
///
/// Mirrors the `proposed_verdict` object from `POST /api/trends/conversation`.
class ProposedVerdict {
  final String category;
  final String outcomeType; // 'symptom' | 'wellbeing'
  final String outcomeName;
  final String verdict; // 'confirmed' | 'disputed' | 'snoozed'

  const ProposedVerdict({
    required this.category,
    required this.outcomeType,
    required this.outcomeName,
    required this.verdict,
  });

  factory ProposedVerdict.fromJson(Map<String, dynamic> json) {
    return ProposedVerdict(
      category: json['category'] as String? ?? '',
      outcomeType: json['outcome_type'] as String? ?? '',
      outcomeName: json['outcome_name'] as String? ?? '',
      verdict: json['verdict'] as String? ?? '',
    );
  }
}

/// One turn of the monthly trends conversation from
/// `POST /api/trends/conversation` — the assistant [reply], an optional
/// [proposedVerdict] to put to the user, and [isClosing] when the assistant
/// considers the conversation wrapped up.
class TrendsTurn {
  final String reply;
  final ProposedVerdict? proposedVerdict;
  final bool isClosing;

  const TrendsTurn({
    required this.reply,
    this.proposedVerdict,
    this.isClosing = false,
  });

  factory TrendsTurn.fromJson(Map<String, dynamic> json) {
    final rawVerdict = json['proposed_verdict'];
    return TrendsTurn(
      reply: json['reply'] as String? ?? '',
      proposedVerdict: rawVerdict is Map<String, dynamic>
          ? ProposedVerdict.fromJson(rawVerdict)
          : null,
      isClosing: json['is_closing'] as bool? ?? false,
    );
  }
}
