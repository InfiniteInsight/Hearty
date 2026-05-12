enum WellbeingPeriod {
  morning,
  midday,
  evening;

  static WellbeingPeriod inferFromLocalHour([int? hour]) {
    final h = hour ?? DateTime.now().hour;
    if (h >= 5 && h < 11) return morning;
    if (h >= 11 && h < 17) return midday;
    return evening;
  }

  String get label => switch (this) {
        morning => 'Morning',
        midday => 'Midday',
        evening => 'Evening',
      };
}
