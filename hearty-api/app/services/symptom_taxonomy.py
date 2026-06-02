"""
Combination symptom types and their clinical components.

Colloquial terms like "indigestion" are logged as-is so the user's intent is
preserved. At report-generation time, expand_for_report() splits them into
their component clinical types so doctors see structured, actionable data.
"""

COMBINATION_SYMPTOM_TYPES: dict[str, list[str]] = {
    "indigestion":   ["stomach_pain", "bloating"],
    "upset_stomach": ["nausea", "stomach_pain"],
    "sour_stomach":  ["acid_reflux", "nausea"],
    "gut_rot":       ["nausea", "cramping"],
}


def expand_for_report(symptom) -> list:
    """Return a list of one (unchanged) or more (expanded) SymptomResponse objects.

    Combination types are replaced with their clinical components, each
    carrying the same severity, timestamps, and metadata as the original.
    """
    components = COMBINATION_SYMPTOM_TYPES.get(symptom.symptom_type)
    if not components:
        return [symptom]
    return [symptom.model_copy(update={"symptom_type": c}) for c in components]


def expand_symptom_list(symptoms: list) -> list:
    """Expand all combination types in a symptom list."""
    result = []
    for s in symptoms:
        result.extend(expand_for_report(s))
    return result
