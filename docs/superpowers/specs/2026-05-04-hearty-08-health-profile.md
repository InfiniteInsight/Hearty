# Hearty — Spec 08: Health Profile

**Version:** 1.0  
**Date:** 2026-05-04  
**Phase:** Phase 1  
**Status:** Active

---

## 1. Purpose

The health profile stores the user's known allergens, food intolerances, medical conditions, and dietary protocols. This context is injected into every AI analysis session so Claude can give smarter, more relevant pattern observations without the user having to re-explain their situation on every interaction.

The profile is entirely optional. Users can skip it, fill it in partially, and update it at any time. It is never required to log a meal.

> **Disclaimer:** Hearty is a personal tracking tool, not a medical device. Nothing in the health profile or AI output constitutes medical advice, diagnosis, or treatment. Pattern observations are for personal awareness only. Always consult a qualified healthcare provider for medical decisions.

---

## 2. Data Model

The `health_profile` table stores one row per user. All four data domains are JSONB arrays, allowing both well-known structured entries and free-form additions.

```sql
CREATE TABLE health_profile (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID REFERENCES auth.users NOT NULL UNIQUE,
  allergens          JSONB DEFAULT '[]'::jsonb,
  intolerances       JSONB DEFAULT '[]'::jsonb,
  conditions         JSONB DEFAULT '[]'::jsonb,
  dietary_protocols  JSONB DEFAULT '[]'::jsonb,
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now()
);
```

### 2.1 `allergens` JSONB Shape

Each allergen entry:
```json
{
  "name": "milk",
  "severity": "severe",
  "reaction": "hives, anaphylaxis",
  "confirmed_by_doctor": true,
  "notes": "carry EpiPen"
}
```

`severity` values: `"mild"`, `"moderate"`, `"severe"`

### 2.2 `intolerances` JSONB Shape

Each intolerance entry:
```json
{
  "name": "lactose",
  "severity": "moderate",
  "threshold": "small amounts OK",
  "notes": "symptoms within 1 hour"
}
```

### 2.3 `conditions` JSONB Shape

Each condition entry:
```json
{
  "name": "IBS-D",
  "diagnosed": true,
  "diagnosis_year": 2022,
  "notes": "flares with stress and high-fat meals"
}
```

### 2.4 `dietary_protocols` JSONB Shape

Each protocol entry:
```json
{
  "name": "low-FODMAP",
  "active": true,
  "started": "2026-01-01",
  "phase": "elimination",
  "notes": "working with dietitian"
}
```

---

## 3. Allergens

### 3.1 The Big 9 (FASTER Act, effective January 2023)

These are offered as toggle defaults during onboarding. The user can mark any as applicable with severity and notes:

| # | Allergen |
|---|---|
| 1 | Milk |
| 2 | Eggs |
| 3 | Fish |
| 4 | Shellfish |
| 5 | Tree nuts |
| 6 | Peanuts |
| 7 | Wheat |
| 8 | Soybeans |
| 9 | Sesame |

Users can also add any free-form allergen (e.g., "mustard", "lupin", "celery") as an additional entry.

### 3.2 How Allergens Affect AI Behavior

When allergens are set, Claude:
- Flags any logged meal containing a known allergen (even if no symptom logged)
- Watches for subtle symptom patterns that might indicate unrecognized allergen reactions
- Raises the confidence threshold for correlating that food with symptoms (assumes correlation; looks for disconfirmation)
- Adds a note in the trend analysis: "Note: milk is listed as a confirmed allergen — reactions may not follow typical onset patterns"

---

## 4. Food Intolerances

Common intolerances surfaced as quick-select options:

- Lactose
- Fructose (fructose malabsorption)
- Histamine
- Gluten (non-celiac sensitivity)
- Sorbitol / sugar alcohols
- Caffeine
- Alcohol
- Sulfites
- Nightshades
- Legumes
- Onion / garlic (fructans)
- High-fat foods

Users may add any free-form intolerance.

---

## 5. Known Conditions

Common conditions surfaced as quick-select options during onboarding:

| Condition | Notes |
|---|---|
| IBS-C | Irritable Bowel Syndrome, constipation-predominant |
| IBS-D | Irritable Bowel Syndrome, diarrhoea-predominant |
| IBS-M | Irritable Bowel Syndrome, mixed |
| GERD | Gastroesophageal reflux disease |
| Crohn's disease | Inflammatory bowel disease |
| Ulcerative colitis | Inflammatory bowel disease |
| Celiac disease | Autoimmune gluten condition |
| Lactose intolerance | Enzyme deficiency |
| Histamine intolerance | DAO enzyme deficiency or overload |
| Fructose malabsorption | Impaired fructose absorption |
| Gastroparesis | Delayed gastric emptying |
| SIBO | Small intestinal bacterial overgrowth |
| Eosinophilic esophagitis | Immune-mediated esophageal condition |
| Type 2 diabetes | Blood sugar management relevance |

Users may add any free-form condition.

### 5.1 How Conditions Affect AI Behavior

Examples:

- **IBS:** AI cross-references FODMAP content of logged foods with symptom timing; notes high-FODMAP meals proactively
- **GERD:** AI flags acidic foods, large portions, late-night meals, and lying down soon after eating
- **Celiac disease:** AI treats any gluten exposure as high-priority and flags ambiguous ingredients (sauces, marinades)
- **Histamine intolerance:** AI flags aged cheeses, fermented foods, alcohol, and leftovers that have been reheated

---

## 6. Dietary Protocols

Common protocols surfaced as quick-select options:

| Protocol | Description |
|---|---|
| Low-FODMAP | Fermentable carbohydrate restriction; phases: elimination → reintroduction |
| Elimination diet | Broad removal of common triggers; phased reintroduction |
| Gluten-free | Complete gluten avoidance |
| Dairy-free | Complete dairy avoidance |
| AIP (Autoimmune Protocol) | Elimination diet for autoimmune conditions |
| Specific Carbohydrate Diet (SCD) | Grain/sugar restriction for IBD |
| GAPS diet | Gut and Psychology Syndrome protocol |
| Low-histamine diet | Avoidance of histamine-rich and DAO-blocking foods |
| Low-residue diet | Low fiber for bowel rest |
| Mediterranean diet | General anti-inflammatory eating pattern |
| Plant-based / vegan | No animal products |
| Intermittent fasting | Time-restricted eating windows |

Users may add any free-form protocol.

### 6.1 How Protocols Affect AI Behavior

- **Low-FODMAP elimination phase:** AI flags any logged food that is high-FODMAP and notes it as a potential protocol violation; notes whether symptom occurred after compliant vs. non-compliant meals
- **Elimination diet:** AI tracks reintroduced foods and watches for symptom spikes after reintroduction events
- **Gluten-free:** AI treats wheat/barley/rye as allergen-level flags, watches for cross-contamination scenarios (e.g., shared fryer at a restaurant)
- **General:** AI includes protocol context in trend summaries: "Of your 12 IBS flares this month, 9 occurred on days when FODMAP load was high"

---

## 7. Onboarding Flow

The health profile setup appears once, during first launch, after account creation.

### Screen sequence:

1. **Welcome screen:** Brief explanation of what Hearty does and that the profile is optional
2. **Allergens:** "Do you have any food allergies?" — Big 9 toggle grid + "Add another" free text
3. **Intolerances:** "Any foods you react to but aren't allergic to?" — quick-select chips + free text
4. **Conditions:** "Are you managing any digestive or health conditions?" — checkbox list + free text
5. **Dietary protocols:** "Following any eating protocol?" — quick-select + free text
6. **Confirmation:** Summary of what was entered, "Looks right?" → Save
7. **Skip option:** Visible on every screen; user lands on the main log screen

After skipping or completing, the profile is always editable from Settings → Health Profile.

### Rules:
- No field is required
- Skip on any screen = that section remains empty, others are saved
- Skipping the entire flow = empty profile row is still created (for future use)
- Profile is not required to log meals or symptoms

---

## 8. Privacy and Data Handling

- All health profile data is stored in Supabase PostgreSQL under the user's `user_id`
- RLS policy ensures no other user or service can read the data without the service role key
- The service role key is only used server-side by FastAPI and MCP Server — never exposed to client code
- Health profile data is **never shared** with third parties, never used for advertising, never sent to any external service except as context to Claude API for the user's own analysis session
- Users can delete their entire health profile at any time from Settings → Health Profile → Delete Profile
- Users can export their profile as part of the full JSON data export
- Profile data is included in doctor-sharing PDF export only if the user explicitly enables that option

---

## 9. AI Context Injection

### 9.1 MCP Server

When the MCP Server handles a Claude session, it fetches the user's health profile and includes it in the system prompt context:

```
User health profile:
- Allergens: milk (severe, confirmed), peanuts (moderate)
- Intolerances: lactose, histamine
- Conditions: IBS-D (diagnosed 2022), GERD
- Dietary protocols: low-FODMAP elimination phase (started 2026-01-01)

When analyzing meals and symptoms:
- Flag any meal containing milk or peanuts regardless of symptom presence
- Cross-reference logged foods against FODMAP content
- Note acid-triggering foods for GERD relevance
- Use IBS-D context when interpreting bathroom urgency and stool consistency patterns
```

### 9.2 FastAPI REST API

The `/api/trends` and `/api/summary` endpoints automatically join `health_profile` for the authenticated user and pass it as context when calling the Claude API for analysis generation.

### 9.3 Example AI Interactions with Profile Active

**Allergen flagging:**
> User logs: "Pad Thai from that new place"
> AI: "Logged. Worth noting — pad Thai often contains peanuts, which you've listed as a moderate allergen. Keep an eye on how you feel in the next hour."

**Protocol-aware trend:**
> User asks: "Why do I keep feeling bad on Wednesdays?"
> AI: "Looking at your logs — Wednesdays tend to have higher FODMAP loads. You've logged onion-heavy dishes 4 of the last 5 Wednesdays, and you're in FODMAP elimination phase. That's a likely contributor."

**Condition-specific insight:**
> After logging a late dinner at 10pm:
> AI: "Logged. Since you have GERD, meals this close to bedtime can increase reflux risk. I'll check in about 90 minutes."

---

## 10. Integration Points

### 10.1 REST API Endpoints

```
GET    /api/health-profile          -- Fetch the user's health profile
PUT    /api/health-profile          -- Full replace (all four JSONB fields)
PATCH  /api/health-profile          -- Partial update (individual fields)
DELETE /api/health-profile          -- Delete entire profile (resets to empty defaults)

GET    /api/health-profile/allergens          -- Fetch allergens only
PUT    /api/health-profile/allergens          -- Replace allergens array
GET    /api/health-profile/intolerances       -- Fetch intolerances only
PUT    /api/health-profile/intolerances       -- Replace intolerances array
GET    /api/health-profile/conditions         -- Fetch conditions only
PUT    /api/health-profile/conditions         -- Replace conditions array
GET    /api/health-profile/dietary-protocols  -- Fetch protocols only
PUT    /api/health-profile/dietary-protocols  -- Replace protocols array
```

All endpoints require `Authorization: Bearer <supabase_jwt>` and enforce RLS via the authenticated user context.

### 10.2 MCP Context Injection

The MCP Server exposes a `get_health_profile` tool and automatically includes profile data in the session context (system prompt) at session start. See Spec 02 for MCP tool definitions.

### 10.3 Web Dashboard Settings Page

The React web dashboard includes a Settings → Health Profile page with:
- Grouped sections for each domain (allergens, intolerances, conditions, protocols)
- Inline add/remove/edit for each entry
- Severity dropdowns where applicable
- Free-text notes fields
- "Delete entire profile" danger zone with confirmation dialog
- Last-updated timestamp displayed at the top of the page
