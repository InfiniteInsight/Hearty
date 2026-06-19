/// Turns a category slug into a friendly fallback label, e.g. 'dairy_casein' -> 'Dairy Casein'.
/// Prefer the backend-provided category_label; use this only when it's missing/empty.
String prettifyCategory(String slug) => slug
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// Resolve a display label: backend label if present, else prettified slug.
String resolveCategoryLabel(String? label, String slug) =>
    (label != null && label.isNotEmpty) ? label : prettifyCategory(slug);
