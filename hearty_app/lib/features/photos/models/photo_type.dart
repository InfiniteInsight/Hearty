enum PhotoType {
  foodPlate,
  barcode,
  nutritionLabel,
  foodLabel;

  String get apiValue => switch (this) {
        PhotoType.foodPlate => 'food_plate',
        PhotoType.barcode => 'barcode',
        PhotoType.nutritionLabel => 'nutrition_label',
        PhotoType.foodLabel => 'food_label',
      };

  String get displayLabel => switch (this) {
        PhotoType.foodPlate => 'Food / Meal',
        PhotoType.barcode => 'Barcode',
        PhotoType.nutritionLabel => 'Nutrition Label',
        PhotoType.foodLabel => 'Food Label / Package',
      };

  String get processingLabel => switch (this) {
        PhotoType.foodPlate => 'Analyzing food...',
        PhotoType.barcode => 'Looking up barcode...',
        PhotoType.nutritionLabel => 'Reading nutrition label...',
        PhotoType.foodLabel => 'Reading food label...',
      };
}
