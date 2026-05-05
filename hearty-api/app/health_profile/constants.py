"""Health profile constants for the Hearty food journal application.

This module defines canonical lists of health-related items that users can select
during onboarding and in settings. These are the quick-select defaults surfaced to
the user, not seed rows in the database.
"""

# The Big 9 FASTER Act allergens (spec §3.1)
# Normalized to lowercase strings
BIG_9_ALLERGENS: list[str] = [
    "milk",
    "eggs",
    "fish",
    "shellfish",
    "tree nuts",
    "peanuts",
    "wheat",
    "soybeans",
    "sesame",
]

# Common food intolerances (spec §4)
# 12 items using exact name strings from spec
COMMON_INTOLERANCES: list[str] = [
    "Lactose",
    "Fructose (fructose malabsorption)",
    "Histamine",
    "Gluten (non-celiac sensitivity)",
    "Sorbitol / sugar alcohols",
    "Caffeine",
    "Alcohol",
    "Sulfites",
    "Nightshades",
    "Legumes",
    "Onion / garlic (fructans)",
    "High-fat foods",
]

# Known medical conditions (spec §5)
# 14 items using exact condition-name strings from spec
COMMON_CONDITIONS: list[str] = [
    "IBS-C",
    "IBS-D",
    "IBS-M",
    "GERD",
    "Crohn's disease",
    "Ulcerative colitis",
    "Celiac disease",
    "Lactose intolerance",
    "Histamine intolerance",
    "Fructose malabsorption",
    "Gastroparesis",
    "SIBO",
    "Eosinophilic esophagitis",
    "Type 2 diabetes",
]

# Common dietary protocols and approaches (spec §6)
# 12 items using exact protocol-name strings from spec
COMMON_DIETARY_PROTOCOLS: list[str] = [
    "Low-FODMAP",
    "Elimination diet",
    "Gluten-free",
    "Dairy-free",
    "AIP (Autoimmune Protocol)",
    "Specific Carbohydrate Diet (SCD)",
    "GAPS diet",
    "Low-histamine diet",
    "Low-residue diet",
    "Mediterranean diet",
    "Plant-based / vegan",
    "Intermittent fasting",
]
