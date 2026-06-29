import 'package:flutter/material.dart';

import '../../../app/theme/aurora_colors.dart';

/// Shared Aurora chip styling for the Health Profile sections.
///
/// Selected/added chips read as emerald-tinted glass; unselected suggestions
/// and the "Add" action read as plain glass. Kept here so the allergen,
/// condition and dietary-protocol sections style identically.

/// Background fill for a chip: emerald-tinted when [selected], glass otherwise.
Color auroraChipBg(bool selected) =>
    selected ? Aurora.accentGreen.withValues(alpha: 0.18) : Aurora.glassFill;

/// Border for a chip: emerald when [selected], glass otherwise.
BorderSide auroraChipSide(bool selected) => BorderSide(
      color: selected ? Aurora.accentGreen : Aurora.glassBorder,
    );

/// Label style: white when [selected]/added, muted-secondary as a suggestion.
TextStyle auroraChipLabel(bool selected) => TextStyle(
      color: selected ? Aurora.textPrimary : Aurora.textSecondary,
    );

/// Muted tint for the "x" delete affordance on added chips.
const Color auroraChipDeleteIcon = Aurora.textMuted;

/// Muted tint for the leading "+" on the "Add" action chip.
const Color auroraChipAddIcon = Aurora.textSecondary;
