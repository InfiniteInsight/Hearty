# Radial Clock — Arc Labels & Tap Menu

Companion spec to the [UI Design Guide](2026-05-28-hearty-ui-design-guide.md).  
Covers three additions: the AM/PM zone split, arc text labels on orbit dots, and the tap-to-detail interaction.

Reference mockup: `designs9.html`

---

## 1. AM/PM Zone System

### Concept

The clock face is divided into two radial zones keyed to time of day:

- **AM zone** — the inner ring area. Morning entries orbit here, close to center.
- **PM zone** — the outer ring area. Afternoon/evening entries orbit here, around the edge.

The hands and digital time display remain unchanged in the center regardless of zone.

### Zone Background Gradients

The zone tinting is built from two stacked `radial-gradient` layers on the clock-zone container. The key technique is using an explicit pixel radius (`circle Rpx`) rather than a percentage, so the zone size is independent of container dimensions.

```css
/* Layer 1: fills inner circle (R=45px) with AM tint */
radial-gradient(circle 45px at 50% 50%, <am-color> 0%, <am-color> 100%)

/* Layer 2: creates an annular band at the outer ring (R≈108–133px) with PM tint */
radial-gradient(circle 140px at 50% 50%,
  transparent 77%,
  <pm-color> 82%,
  <pm-color> 92%,
  transparent 97%)
```

The annular band uses the 77%–97% stop range of a 140px circle, which resolves to roughly px108–px136 — matching the outer ring (R=108px) and the PM orbit path (R=118px).

**Warm & Grounded values:**

```css
.clock-zone {
  background:
    radial-gradient(circle 45px at 50% 50%,
      rgba(185,210,235,0.22) 0%, rgba(185,210,235,0.22) 100%),
    radial-gradient(circle 140px at 50% 50%,
      transparent 77%, rgba(222,170,110,0.09) 82%,
      rgba(222,170,110,0.09) 92%, transparent 97%),
    #FDFBF7;
}
```

**Aurora values:**

```css
.clock-zone {
  background:
    radial-gradient(circle 45px at 50% 50%,
      rgba(139,92,246,0.14) 0%, rgba(139,92,246,0.14) 100%),
    radial-gradient(circle 140px at 50% 50%,
      transparent 77%, rgba(52,211,153,0.07) 82%,
      rgba(52,211,153,0.07) 92%, transparent 97%);
  /* no base color — clock zone is transparent over the screen background */
}
```

### Ring Color Coding

The inner ring border is tinted to match the AM zone color; the outer ring matches the PM zone.

| Ring | Radius | Warm & Grounded | Aurora |
|---|---|---|---|
| Outer (PM) | R=108px / 216px diameter | `1.5px solid #C8B89A` | `1px solid rgba(52,211,153,0.22)` |
| Mid (reference) | R=80px / 160px diameter | `1px solid #EDE8DF` | `1px solid rgba(52,211,153,0.07)` |
| Inner (AM) | R=45px / 90px diameter | `1.5px solid rgba(155,190,220,0.6)` + `background: rgba(185,210,235,0.14)` | `1.5px solid rgba(139,92,246,0.35)` + `background: rgba(139,92,246,0.1)` |

### Zone Legend Strip

A narrow strip between the clock zone and the entry list labels the two zones. Sits in its own `div` with a bottom border divider.

```html
<div class="zone-legend">
  <span class="zone-tag am">
    <span class="zone-dot" style="background: <am-dot-color>"></span>
    AM · inner orbit
  </span>
  <span class="zone-tag pm">
    <span class="zone-dot" style="background: <pm-dot-color>"></span>
    PM · outer orbit
  </span>
</div>
```

```css
.zone-legend {
  display: flex;
  justify-content: center;
  gap: 20px;
  padding: 5px 0;
}
.zone-tag {
  font-size: 7px;
  font-weight: 700;
  letter-spacing: 0.07em;
  display: flex;
  align-items: center;
  gap: 5px;
}
.zone-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  flex-shrink: 0;
}
```

| | Warm & Grounded | Aurora |
|---|---|---|
| AM tag color | `rgba(120,170,210,0.9)` | `rgba(167,139,250,0.85)` |
| PM tag color | `#C0392B` | `rgba(52,211,153,0.75)` |
| AM dot fill | `rgba(140,185,220,0.75)` | `rgba(139,92,246,0.6)` |
| PM dot fill | `#C0392B` | `#34D399` |
| Strip border | `1px solid #EDE8DF` | `1px solid rgba(255,255,255,0.06)` |

---

## 2. Orbit Dot Zones

This section supersedes the single-radius orbit table in the base design guide. Entries now split between two radii based on AM vs PM.

### AM Orbit — R = 60px (inner zone)

Sits between the inner ring (R=45) and the mid ring (R=80). Smaller dots (26×26px) with a cool-toned border.

```css
/* Shared AM dot */
.am-dot {
  position: absolute;
  top: 50%; left: 50%;
  width: 26px; height: 26px;
  border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 12px;
  z-index: 4;
  box-shadow: 0 1px 5px rgba(0,0,0,0.07);
}
```

| State | Warm & Grounded | Aurora |
|---|---|---|
| Meal dot | `background: rgba(185,210,235,0.35)` + `border: 2px solid rgba(140,185,220,0.55)` | `background: rgba(139,92,246,0.14)` + `border: 1.5px solid rgba(139,92,246,0.38)` |
| Symptom dot | `background: rgba(235,205,200,0.4)` + `border-color: rgba(200,120,110,0.45)` | `background: rgba(248,113,113,0.12)` + `border: 1.5px solid rgba(248,113,113,0.35)` |

### PM Orbit — R = 118px (outer zone)

Sits outside the outer ring (R=108). Full-size dots (34×34px).

```css
.pm-dot {
  position: absolute;
  top: 50%; left: 50%;
  width: 34px; height: 34px;
  border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 15px;
  z-index: 4;
}
```

| State | Warm & Grounded | Aurora |
|---|---|---|
| Meal dot | `background: #fff` + `border: 2px solid #EDE8DF` + shadow | `background: rgba(52,211,153,0.08)` + `border: 1.5px solid rgba(52,211,153,0.3)` |
| Symptom dot | `background: #FDF5F4` + `border-color: #F5D0CB` | `background: rgba(248,113,113,0.08)` + `border: 1.5px solid rgba(248,113,113,0.3)` |
| Mood dot | (same as meal) | `background: rgba(167,139,250,0.08)` + `border: 1.5px solid rgba(167,139,250,0.3)` |

### Coordinate Formula

Same trig as clock numbers; just substitute the orbit radius R:

```
angle = (hour % 12 + minutes / 60) × 30    [degrees, clockwise from 12]
x = R · sin(angle)
y = −R · cos(angle)

CSS: transform: translate(calc(-50% + Xpx), calc(-50% + Ypx))
```

**Entry positions used in the mockups:**

| Entry | Time | Angle | AM/PM | R | X | Y |
|---|---|---|---|---|---|---|
| Breakfast | 8:00 | 240° | AM | 60 | −52 | +30 |
| Coffee | 9:00 | 270° | AM | 60 | −60 | 0 |
| Bloating | 10:30 | 315° | AM | 60 | −42 | −42 |
| Lunch | 12:30 | 15° | PM | 118 | +31 | −114 |
| Snack | 2:00 | 60° | PM | 118 | +102 | −59 |
| Mood | 4:00 | 120° | PM | 118 | +102 | +59 |
| Dinner | 7:00 | 210° | PM | 118 | −59 | +102 |

---

## 3. Arc Labels

### Approach

Labels are rendered using SVG `<textPath>` flowing along a circular arc centered on each dot. This produces genuinely curved text without JavaScript.

A single `<svg>` overlay covers the entire clock zone. It is `pointer-events: none` and `overflow: visible` (so labels near the edge don't clip). The `viewBox` matches the clock zone dimensions.

```html
<svg
  style="position:absolute; top:0; left:0; width:100%; height:278px;
         pointer-events:none; z-index:8; overflow:visible"
  viewBox="0 0 278 278">
  <defs>
    <!-- define one path per dot -->
    <path id="arc-lunch" d="M 150,25 a 20,20 0 0,1 40,0" />
  </defs>
  <text font-size="7" fill="<label-color>" font-family="DM Sans,sans-serif" font-weight="700">
    <textPath href="#arc-lunch" startOffset="50%" text-anchor="middle">Lunch</textPath>
  </text>
</svg>
```

### SVG Coordinate Space

With `viewBox="0 0 278 278"` and a 278px-wide clock zone, the clock center is at **(139, 139)** in SVG coordinates.

Entry dot centers in SVG space:

```
svg_x = 139 + x_offset
svg_y = 139 + y_offset
```

Using the offsets from the coordinate table above:

| Entry | SVG X | SVG Y |
|---|---|---|
| Breakfast | 87 | 169 |
| Coffee | 79 | 139 |
| Bloating | 97 | 97 |
| Lunch | 170 | 25 |
| Snack | 241 | 80 |
| Mood | 241 | 198 |
| Dinner | 80 | 241 |

### Arc Path Formula

Each arc is a semicircle of radius `r` centered on the dot. The path starts at the leftmost point and sweeps to the rightmost point.

```
Top arc (text curves above dot):
  M (cx − r), cy   a r,r 0 0,0  (2r),0

Bottom arc (text curves below dot — use for dots near the top edge):
  M (cx − r), cy   a r,r 0 0,1  (2r),0
```

**`0,0` (counterclockwise)** = top arc — text reads left-to-right along the top of the dot.  
**`0,1` (clockwise)** = bottom arc — text reads left-to-right along the bottom of the dot.

**Arc radius rule of thumb:**
- AM dots (26px / r=13px): use arc radius **r=18**
- PM dots (34px / r=17px): use arc radius **r=20–22**

**Which arc direction per dot:**

| Entry | Direction | Reason |
|---|---|---|
| Breakfast, Coffee, Bloating | Top arc | Dots in lower half — label above is readable and away from center |
| Lunch | Bottom arc | Dot near top edge — top arc would exit the clock zone |
| Snack | Top arc | Upper-right — enough room above |
| Mood | Bottom arc | Lower-right — label below curves away from center |
| Dinner | Top arc | Lower-left — label above sits between dot and edge |

**All arc `<path>` definitions:**

```html
<!-- AM dots, r=18 -->
<path id="arc-breakfast" d="M 69,169  a 18,18 0 0,0 36,0"/>  <!-- top arc -->
<path id="arc-coffee"    d="M 61,139  a 18,18 0 0,0 36,0"/>  <!-- top arc -->
<path id="arc-bloating"  d="M 79,97   a 18,18 0 0,0 36,0"/>  <!-- top arc -->

<!-- PM dots, r=20–22 -->
<path id="arc-lunch"     d="M 150,25  a 20,20 0 0,1 40,0"/>  <!-- bottom arc -->
<path id="arc-snack"     d="M 219,80  a 22,22 0 0,0 44,0"/>  <!-- top arc -->
<path id="arc-mood"      d="M 219,198 a 22,22 0 0,1 44,0"/>  <!-- bottom arc -->
<path id="arc-dinner"    d="M 58,241  a 22,22 0 0,0 44,0"/>  <!-- top arc -->
```

### Label Content Strategy

| Dot type | Label | Reasoning |
|---|---|---|
| AM (small, inner zone) | Time — `"8:00"`, `"10:30"` | Small arc radius can't fit long food names |
| PM meal (outer zone) | Short food name — `"Lunch"`, `"Snack"`, `"Dinner"` | Larger arc has room; name is more useful at a glance |
| PM mood/symptom | Time — `"4pm"`, `"10:30"` | Category already conveyed by emoji and dot color |

For PM food names longer than ~7 characters, fall back to time (e.g. `"Caesar Salad"` → `"12:30"`).

### Label Colors

**Warm & Grounded:**

| Entry type | Fill |
|---|---|
| AM meal label | `rgba(110,165,210,0.9)` — cool blue matching the AM zone |
| AM symptom label | `rgba(185,100,90,0.85)` — muted salmon |
| PM meal label (default) | `rgba(90,78,66,0.75)` — warm brown |
| PM meal label (selected) | `rgba(192,57,43,0.85)` — accent red |

**Aurora:**

| Entry type | Fill |
|---|---|
| AM meal label | `rgba(139,92,246,0.85)` — violet matching the AM zone |
| AM symptom label | `rgba(248,113,113,0.8)` — red |
| PM meal label | `rgba(52,211,153,0.65)` — emerald |
| PM mood label | `rgba(167,139,250,0.65)` — violet |
| PM meal label (selected) | `rgba(52,211,153,0.9)` — brighter emerald |

### Typography for Arc Labels

| | Warm & Grounded | Aurora |
|---|---|---|
| Font family | `DM Sans, sans-serif` | `Plus Jakarta Sans, sans-serif` |
| Font weight | 700 | 700–800 |
| Font size | AM: 6–6.5px · PM: 7px | AM: 6–6.5px · PM: 7px |
| Letter spacing | 0.3–0.5 | 0.3–0.5 |

---

## 4. Tap Interaction

Tapping an orbit dot does three things simultaneously:

1. **Glow ring** — a multi-layer `box-shadow` rings the selected dot
2. **Popup card** — a floating card appears near the dot with the entry's name and time
3. **List row highlight** — the corresponding entry in the list below is visually emphasized

### Selected Dot State

Add these styles to the dot when it is the active selection:

**Warm & Grounded:**
```css
.pm-dot.selected {
  border-color: #C0392B;
  box-shadow:
    0 0 0 5px rgba(192,57,43,0.14),
    0 0 0 9px rgba(192,57,43,0.06),
    0 2px 10px rgba(0,0,0,0.09);
}
```

**Aurora:**
```css
.pm-dot.selected {
  border-color: rgba(52,211,153,0.7);
  box-shadow:
    0 0 0 5px rgba(52,211,153,0.18),
    0 0 0 9px rgba(52,211,153,0.07),
    0 0 18px rgba(52,211,153,0.3);
}
```

The arc label for the selected dot remains visible — it acts as a persistent name tag even while the popup is showing.

### Popup Card

The popup is a `position: absolute` element inside the clock zone. It stacks: an upward-pointing arrow triangle on top, then the card body below it.

```html
<div class="tap-popup" style="top: <Y>px; left: <X>px; transform: translateX(-50%);">
  <div class="tap-arrow"></div>
  <div class="tap-card">
    <span class="tap-icon">🥗</span>
    <div>
      <div class="tap-name">Caesar Salad</div>
      <div class="tap-time">12:30 PM</div>
    </div>
    <span class="tap-dismiss">×</span>
  </div>
</div>
```

**Popup positioning:**
- `left` = the dot's X offset from clock center + 139px (clock center from left edge of clock zone)
- `transform: translateX(-50%)` centers the popup horizontally over the dot
- `top` = dot's Y position in the clock zone + dot radius + 8px gap (so it appears just below the dot)

For the Lunch dot at (170, 25) in SVG space, the popup sits at `top: 52px; left: 170px`.

**Arrow — upward pointing triangle:**

The arrow sits above the card body and points toward the dot. Built with CSS borders:

```css
.tap-arrow {
  width: 0; height: 0;
  border-left: 7px solid transparent;
  border-right: 7px solid transparent;
  border-bottom: 8px solid <border-color>;
  position: relative;
}
.tap-arrow::after {
  content: '';
  position: absolute;
  top: 2px; left: -6px;
  width: 0; height: 0;
  border-left: 6px solid transparent;
  border-right: 6px solid transparent;
  border-bottom: 7px solid <card-bg-color>;
}
```

The outer triangle uses the card's border color; the inner `::after` triangle uses the card's background — this creates the two-tone bordered arrow effect.

**Card body:**

```css
.tap-card {
  display: flex;
  align-items: center;
  gap: 9px;
  border-radius: 13px;
  padding: 9px 13px 9px 10px;
  white-space: nowrap;
}
.tap-icon { font-size: 20px; }
.tap-name { font-size: 12px; font-weight: 700; line-height: 1.2; }
.tap-time { font-size: 9px; margin-top: 2px; font-family: 'JetBrains Mono', monospace; }
.tap-dismiss { margin-left: 4px; font-size: 14px; align-self: flex-start; }
```

**Per-palette card styles:**

| Token | Warm & Grounded | Aurora |
|---|---|---|
| `card-bg` | `#ffffff` | `#0D2235` (or `rgba(13,27,50,0.95)`) |
| `card-border` | `1.5px solid #D9D0C4` | `1.5px solid rgba(52,211,153,0.35)` |
| `card-shadow` | `0 6px 24px rgba(0,0,0,0.11), 0 1px 4px rgba(0,0,0,0.06)` | `0 6px 24px rgba(0,0,0,0.4), 0 0 18px rgba(52,211,153,0.1)` |
| `card-backdrop-filter` | — | `blur(10px)` |
| `name-color` | `#1A1209` | `#ffffff` |
| `time-color` | `#9B8C78` | `rgba(52,211,153,0.7)` |
| `dismiss-color` | `#C8B89A` | `rgba(255,255,255,0.2)` |
| Arrow border color | `#D9D0C4` | `rgba(52,211,153,0.4)` |
| Arrow fill color | `#ffffff` | `#0D2235` |

### List Row Highlight

The entry list row corresponding to the tapped dot receives a distinct visual treatment. The highlight uses an inset left-border accent as the strongest signal, plus a subtle background tint.

```css
/* Warm & Grounded */
.list-entry.selected {
  border-color: #C0392B;
  background: rgba(192,57,43,0.03);
  box-shadow: inset 3px 0 0 #C0392B;
}
.list-entry.selected .entry-title {
  font-weight: 800;
  color: #C0392B;
}

/* Aurora */
.list-entry.selected {
  border-color: rgba(52,211,153,0.55);
  background: rgba(52,211,153,0.07);
  box-shadow: inset 3px 0 0 rgba(52,211,153,0.6);
}
.list-entry.selected .entry-title {
  font-weight: 800;
  color: #34D399;
}
```

The `inset 3px 0 0` box-shadow draws the left accent without affecting layout — it works even with `border-radius` and avoids a `border-left` override fight with the existing border shorthand.

---

## 5. Layer Order (z-index reference)

All layers sit within the clock-zone container (`position: relative`):

| z-index | Layer |
|---|---|
| 1 | Ring circles (inner, mid, outer) |
| 2 | Tick marks |
| 3 | Clock number labels |
| 4 | AM orbit dots |
| 4 | PM orbit dots |
| 5 | Clock hands container |
| 5 | Center time display |
| 6 | Center dot (covers hand pivot) |
| 8 | SVG arc label overlay |
| 10 | Hand center dot (`box-shadow: 0 0 0 2px <bg>` cuts through labels) |
| 20 | Tap popup card |

---

## 6. Clock Zone Dimensions

The mockup uses `height: 278px` for the expanded clock zone. The SVG label overlay must match this height exactly in its inline `style` and `viewBox`.

If the clock zone height changes, update both:
```html
<svg style="height: <NEW_HEIGHT>px" viewBox="0 0 278 <NEW_HEIGHT>">
```

And recalculate `svg_y = (NEW_HEIGHT / 2) + y_offset` for all dot positions.
