/// Title shown for a meal on the home/history timeline.
///
/// Uses the (manually editable) extracted [foods] — capitalized and comma-joined
/// — so edits like removing a food are reflected on the card. Falls back to the
/// raw [description] when no foods were extracted/kept, so the card is never
/// blank. The verbatim description is still available on the detail/edit screens.
String mealTimelineTitle(List<String> foods, String description) {
  final names = foods.map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
  if (names.isEmpty) return description;
  return names
      .map((f) => f[0].toUpperCase() + f.substring(1))
      .join(', ');
}
