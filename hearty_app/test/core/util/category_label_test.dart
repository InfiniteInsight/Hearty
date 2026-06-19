import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/util/category_label.dart';

void main() {
  group('prettifyCategory', () {
    test('title-cases and de-underscores a slug', () {
      expect(prettifyCategory('dairy_casein'), 'Dairy Casein');
      expect(prettifyCategory('high_sugar_refined'), 'High Sugar Refined');
      expect(prettifyCategory('gluten'), 'Gluten');
    });

    test('empty slug is safe (no crash, empty result)', () {
      expect(prettifyCategory(''), '');
    });

    test('ignores empty segments from stray underscores', () {
      expect(prettifyCategory('_dairy__casein_'), 'Dairy Casein');
    });
  });

  group('resolveCategoryLabel', () {
    test('backend label wins when present', () {
      expect(resolveCategoryLabel('Dairy / Casein', 'dairy_casein'),
          'Dairy / Casein');
    });

    test('falls back to prettified slug when label is null', () {
      expect(resolveCategoryLabel(null, 'dairy_casein'), 'Dairy Casein');
    });

    test('falls back to prettified slug when label is empty', () {
      expect(resolveCategoryLabel('', 'dairy_casein'), 'Dairy Casein');
    });

    test('empty label and empty slug is safe', () {
      expect(resolveCategoryLabel(null, ''), '');
    });
  });
}
