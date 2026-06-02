# Hearty UI Design Guide

Reference for implementing the 7 shortlisted designs plus the expanded Radial Clock.

---

## Colour Systems

### Warm & Grounded
Earthy cream base with terracotta accent. Used in Home A, Home C (expanded), History C.

| Token | Value | Use |
|---|---|---|
| `surface` | `#FDFBF7` | Screen background, topbar fill |
| `border` | `#EDE8DF` | Card borders, dividers |
| `border-mid` | `#D9D0C4` | Clock outer ring |
| `text-primary` | `#1A1209` | Dark warm brown — headlines, "Heart" in logo |
| `text-muted` | `#9B8C78` | Captions, timestamps |
| `text-secondary` | `#7B6B5A` | Mood category |
| `accent` | `#C0392B` | CTA, minute hand, "y" in logo, symptom accent |
| `accent-bg` | `#FDF0EE` | Symptom dot background |
| `accent-border`| `#F5D0CB` | Symptom dot border |
| `card-bg` | `#FFFFFF` | List entry backgrounds |

### Aurora
Deep navy with emerald and violet aurora glows. Used in Home C, History B.

| Token | Value | Use |
|---|---|---|
| `bg` | `linear-gradient(160deg, #0F1F2E 0%, #112240 100%)` | Screen background |
| `glow-emerald` | `rgba(52,211,153,0.13–0.16)` | Top-right radial glow |
| `glow-violet` | `rgba(139,92,246,0.11–0.14)` | Bottom-left radial glow |
| `accent-green` | `#34D399` | "y" in logo, minute hand, meal dots, section labels |
| `accent-violet`| `#8B5CF6` / `#A78BFA` | Mood category |
| `accent-red` | `#F87171` | Symptom category |
| `text-primary` | `#FFFFFF` | "Heart" in logo, headlines |
| `text-muted` | `rgba(255,255,255,0.3)` | Timestamps, dates |
| `clock-num-minor` | `rgba(255,255,255,0.2)` | Minor clock numbers |
| `clock-num-major` | `rgba(52,211,153,0.5)` | Cardinal clock numbers (12/3/6/9) |
| `tick-minor` | `rgba(52,211,153,0.12)` | Minor tick marks |
| `tick-major` | `rgba(52,211,153,0.3)` | Cardinal tick marks |
| `ring` | `rgba(52,211,153,0.08–0.18)` | Clock rings |
| `nav-bg` | `rgba(10,20,40,0.85)` | Bottom nav, blurred |
| `card-bg` | `rgba(255,255,255,0.05)` | List entry backgrounds |
| `card-border`| `rgba(255,255,255,0.07–0.15)` | List entry borders |

### Cosmic Bloom
Deep indigo starfield with purple/cyan/pink nebula. Used in Home B, Home D, History A.

| Token | Value | Use |
|---|---|---|
| `bg` | `#07021A` | Screen background |
| `nebula-purple` | `rgba(183,0,255,0.15–0.28)` | Radial glow blobs |
| `nebula-cyan` | `rgba(0,200,255,0.18–0.20)` | Radial glow blobs |
| `nebula-pink` | `rgba(255,60,120,0.15–0.16)` | Radial glow blobs |
| `stars` | `radial-gradient(1px 1px at Xpx Ypx, rgba(255,255,255,0.25–0.6) ...)` | 5-point star field |
| `accent-purple` | `#B700FF` | Primary accent, logo gradient start |
| `accent-cyan` | `#00C8FF` | Secondary accent, logo gradient end |
| `accent-pink` | `#FF3C78` | Tertiary accent, symptom colour |
| `accent-gold` | `#FFC800` | Meal category |
| `logo` | `linear-gradient(135deg, #B700FF, #00C8FF, #FF3C78)` | Gradient text logo |
| `now-row-bg` | `rgba(183,0,255,0.08)` | Current-hour row highlight (Hour Grid) |
| `slide-bg` | `linear-gradient(160deg, #1A004A, #07021A, #001A2A)` | Story Mode slide background |

---

## Typography

| Family | Weight | Use |
|---|---|---|
| Fraunces (serif) | 700 | Logo (Warm & Grounded), time display in clock |
| Plus Jakarta Sans | 800/600 | Logo (Aurora), time display, body text |
| Syne | 800 | Logo (Cosmic Bloom), grid headers, card titles |
| DM Sans | 400/500/700 | Body text, captions, labels (Warm & Grounded) |
| Space Grotesk | 700 | Page-level headings |
| JetBrains Mono | 400/500 | Timestamps, metadata, eyebrow labels |

Logo sizing: `15–19px` in the phone topbar. All logos use `letter-spacing: -0.02em`.

---

## The Logo

The "Hearty" wordmark is split: **"Heart"** is one colour, **"y"** is another — a play on _heart_ and _hearty_.

```html
<!-- Warm & Grounded -->
<span style="color:#1A1209">Heart</span><span style="color:#C0392B">y</span>

<!-- Aurora -->
<span style="color:#fff">Heart</span><span style="color:#34D399">y</span>

<!-- Cosmic Bloom (gradient text on "Hearty") -->
<span style="background:linear-gradient(135deg,#B700FF,#00C8FF,#FF3C78);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent">Hearty</span>
```

---

## Home Screen Layouts

### Home A & C — Radial Clock

A clock dial dominates the upper half. Meals, symptoms, and mood entries are plotted as emoji dots around the dial at the time they occurred. A scrolling list of recent entries sits below.

**Structure:**
1. Topbar — logo left, date right
2. Clock zone — centred, `height: 192px` (shortlist) / `278px` (expanded)
3. Recent entries list — below the clock
4. FAB `+` button — `position: absolute; bottom: ~44–52px; right: ~13–16px`
5. Bottom nav — `position: absolute; bottom: 0`

**Clock zone layers (back to front):**
1. Outer ring — largest circle, thin border
2. Mid ring — for scale reference
3. Inner ring — innermost, slight fill
4. Tick marks at R=103px (see geometry below)
5. Clock numbers at R=88px (see geometry below)
6. Orbit entry dots at R=118px (outside outer ring)
7. Clock hands (pivot at center)
8. Center dot (covers hand pivot)
9. Digital time display (topmost, z-index 5)

### Home B — Hour Grid

A time × category matrix. Hours run down the left column; three columns (Meals / Symptoms / Mood) hold pill chips.

**Structure:**
1. Topbar — logo left, date right
2. Column headers — `Meals | Symptoms | Mood` with category colour tints
3. Grid body — one row per 2-hour block, `height: 27px` per row; current hour gets `rgba(183,0,255,0.08)` background
4. FAB `+` button — `position: absolute; bottom: 9px; right: 11px`

**Pill style:**
```css
.pill { border-radius: 7px; font-size: 8px; height: 15px; padding: 0 4px; }
.pill.meal    { background: rgba(255,200,0,0.15); border: 1px solid rgba(255,200,0,0.25); color: rgba(255,200,0,0.9); }
.pill.sym     { background: rgba(255,60,120,0.15); border: 1px solid rgba(255,60,120,0.25); }
.pill.mood-p  { background: rgba(0,200,255,0.12); border: 1px solid rgba(0,200,255,0.22); }
```

### Home D — Story Mode

The screen is a full-bleed "story" slide. A progress bar of segments at the top shows position in today's entries. The user swipes horizontally to step through meals and symptoms.

**Critical CSS:** The story slide uses `position: absolute; inset: 0`, so every ancestor from the phone container down **must** have an explicit `height` set, or the slide collapses to zero height.

```css
.phone       { height: 420px; }   /* or 580px expanded */
.phone-inner { height: 100%; }
.slide       { position: absolute; inset: 0; }
```

**Structure:**
1. Progress bar — `position: absolute; top: 24px; left/right: 11px` — flex row of segments
2. Full-bleed slide — fills entire phone; nebula overlay behind content
3. Slide content — tag chip, timestamp, headline (gradient text), body text, ingredient chips
4. Entry thumbnail — `position: absolute; bottom: 76px; right: 15px`
5. Bottom bar — nav dots + bottom nav row

---

## History Screen Layout — Calendar + Day

Used in History A (Cosmic Bloom), B (Aurora), C (Warm & Grounded).

**Structure:**
1. Header area — logo, month label, 7-column calendar grid
2. Day view — selected-day label + vertical timeline

**Calendar grid:**
```css
.cal-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 2px; }
```
Days with entries get a small dot indicator via `::after` pseudo-element:
```css
.has-entry::after {
  content: ''; display: block;
  width: 3px; height: 3px; border-radius: 50%;
  margin: 1px auto 0;
}
```
- Cosmic Bloom dot: `#B700FF` with `box-shadow: 0 0 4px rgba(183,0,255,0.5)`
- Aurora dot: `#34D399` with emerald glow
- Warm & Grounded dot: `#C0392B`, no glow

**Timeline entry structure:**
```
[time] [dot + connector] [card]
```
Each timeline entry is a flex row: a narrow time column (23px), a spine column (dot + vertical connector line), and a card that fills remaining width.

**Warm & Grounded variant** uses a dark charcoal header (`#1A1209`) with the cream day view below — the only design that splits the screen into a dark header + light body. Symptom cards get `border-left: 3px solid #C0392B` instead of a glowing dot.

---

## Radial Clock — Geometry

All positions use `top: 50%; left: 50%` as the anchor, then `transform: translate(...)` to offset from center.

### Clock Numbers (R = 88px)

Place a number at angle θ (where θ = 0° = 12 o'clock, increasing clockwise):

```
x = R · sin(θ)
y = -R · cos(θ)
```

```css
/* Applied as: */
transform: translate(calc(-50% + Xpx), calc(-50% + Ypx));
```

All 12 positions:

| Hour | θ | X | Y |
|---|---|---|---|
| 12 | 0° | 0 | −88 |
| 1 | 30° | +44 | −76.2 |
| 2 | 60° | +76.2 | −44 |
| 3 | 90° | +88 | 0 |
| 4 | 120° | +76.2 | +44 |
| 5 | 150° | +44 | +76.2 |
| 6 | 180° | 0 | +88 |
| 7 | 210° | −44 | +76.2 |
| 8 | 240° | −76.2 | +44 |
| 9 | 270° | −88 | 0 |
| 10 | 300° | −76.2 | −44 |
| 11 | 330° | −44 | −76.2 |

12, 3, 6, 9 are `.major` — slightly larger and more prominent.

### Tick Marks (R = 103px)

Each tick is a thin vertical bar. The trick: set `transform-origin` to a point R pixels below the bottom of the element, then rotate.

```css
/* minor tick */
position: absolute; top: 50%; left: 50%;
width: 1.5px; height: 6–7px;
transform-origin: 50% calc(100% + 103px);
transform: translate(-50%, -100%) translateY(-103px) rotate(Ndeg);
```

- Minor ticks: every 30° (`0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330`)
- Major ticks (at 0°/90°/180°/270°): wider (`2px`) and taller (`9–10px`)

### Clock Hands

Hands are absolutely positioned bars with `transform-origin: 50% 100%` (pivot at bottom = clock center). The container sits at `top: 50%; left: 50%; width: 0; height: 0` so the hands pivot exactly from center.

```css
.hand-hour {
  position: absolute; left: 50%; bottom: 0;
  transform-origin: 50% 100%;
  width: 3px; height: 38px;
  margin-left: -1.5px;
}
.hand-minute {
  position: absolute; left: 50%; bottom: 0;
  transform-origin: 50% 100%;
  width: 2px; height: 56px;
  margin-left: -1px;
}
```

**Angle from time:**
```
hour_angle   = (hour % 12 + minutes / 60) × 30
minute_angle = minutes × 6
```

Example — 2:34 PM:
- Hour: `(2 + 34/60) × 30 = 77°`
- Minute: `34 × 6 = 204°`

```html
<div style="transform:translateX(-50%) rotate(77deg)">  <!-- hour hand -->
<div style="transform:translateX(-50%) rotate(204deg)"> <!-- minute hand -->
```

A center dot sits on top of both hands: `position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); z-index: 10`.

### Orbit Entry Dots (R = 118px — outside the outer ring)

Same trig as clock numbers but at R = 118px. Convert entry time to angle:

```
angle = (hour % 12 + minutes / 60) × 30
x = 118 · sin(angle)
y = -118 · cos(angle)
```

Example entry times used in the mockups:

| Entry | Time | Angle | X | Y |
|---|---|---|---|---|
| Breakfast | 8:00 | 240° | −102 | +59 |
| Bloating | 10:30 | 315° | −83 | −83 |
| Lunch | 12:30 | 15° | +31 | −114 |
| Snack | 2:00 | 60° | +102 | −59 |
| Mood | 4:00 | 120° | +102 | +59 |
| Dinner | 7:00 | 210° | −59 | +102 |

Labels are placed ~30–40px further from center along the same radial.

**Entry dot types (Aurora):**
```css
.meal    { border-color: rgba(52,211,153,0.3);   background: rgba(52,211,153,0.08); }
.symptom { border-color: rgba(248,113,113,0.3);  background: rgba(248,113,113,0.08); }
.mood    { border-color: rgba(167,139,250,0.3);  background: rgba(167,139,250,0.08); }
.active  { box-shadow: 0 0 0 3px rgba(52,211,153,0.2), 0 0 14px rgba(52,211,153,0.25); }
```

**Entry dot types (Warm & Grounded):**
```css
/* default */ border: 2px solid #EDE8DF; background: #fff;
.symptom     { border-color: #F5D0CB; background: #FDF5F4; }
.active      { border-color: #C0392B; box-shadow: 0 0 0 3px rgba(192,57,43,0.12); }
```

---

## Background Effects

### Cosmic Bloom — Nebula Blobs

Three `radial-gradient` circles, absolutely positioned, no pointer events:

```css
.nebula {
  position: absolute; border-radius: 50%;
  background: radial-gradient(circle, <colour> 0%, transparent 65%);
}
/* typical sizes: 120–210px */
/* positions: top-left, top-right, bottom-left */
```

### Cosmic Bloom — Star Field

Inline `background-image` with multiple `radial-gradient(1px 1px at X Y, rgba(255,255,255,0.N) ...)` entries:

```css
background-image:
  radial-gradient(1px 1px at 25px 40px, rgba(255,255,255,0.5) 0%, transparent 100%),
  radial-gradient(1px 1px at 90px 110px, rgba(255,255,255,0.35) 0%, transparent 100%),
  /* ... 3–5 more points */;
```

### Aurora — Glow Blobs

Softer and fewer than Cosmic Bloom. Two blobs:
- Top-right: `rgba(52,211,153,0.13)` emerald, `260×260px`
- Bottom-left: `rgba(139,92,246,0.11)` violet, `200×200px`

---

## Navigation & FAB

Bottom nav is a flex row with 4 icon items. Active item is `opacity: 1`, others `opacity: 0.18–0.25`.

FAB is a `34–44px` circle, `position: absolute; bottom: 44–52px; right: 13–16px`. Always a `+` symbol. Colours:
- Warm & Grounded: `background: #C0392B`
- Aurora: `background: linear-gradient(135deg, #34D399, #059669)`
- Cosmic Bloom: `background: linear-gradient(135deg, #B700FF, #00C8FF)`

---

## Design Shortlist Index

| ID | Screen | Layout | Palette |
|---|---|---|---|
| Home A | Home | Radial Clock | Warm & Grounded |
| Home B | Home | Hour Grid | Cosmic Bloom |
| Home C | Home | Radial Clock | Aurora |
| Home D | Home | Story Mode | Cosmic Bloom |
| History A | History | Calendar + Day | Cosmic Bloom |
| History B | History | Calendar + Day | Aurora |
| History C | History | Calendar + Day | Warm & Grounded |

The expanded Radial Clock (designs8) shows Home A and Home C with the full clock face — numbers, tick marks, working hands, and colour-coded orbit entries. This is the intended production fidelity for both Radial Clock variants.
