# Prism Waveform — Voice Visualizer

Reference for the dictation/voice-overlay waveform visual.
Companion to the [UI Design Guide](2026-05-28-hearty-ui-design-guide.md).

**Reference implementation:** `.superpowers/brainstorm/651807-1779833963/content/voice_shader_live.html`
(self-contained HTML/Canvas prototype with a synthetic-idle + live-mic mode)

---

## 1. Concept

A single luminous waveform line that behaves like white light passing through a
prism:

- **Silence** → the three colour channels coincide → a calm, near-flat **single
  white beam**.
- **Speaking** → the channels diverge in the **middle** of the screen, splitting
  into a red/green/blue chromatic spread. The wave grows taller, snakier, and
  flows faster the louder the user speaks.
- The **left and right edges always stay white** — the split is pinned to the
  centre.

The effect is a Canvas-2D port of a WebGL fragment shader (three sine waves, one
per RGB channel, offset by a chromatic-aberration term). Canvas 2D was chosen so
it renders identically in screenshots and ports cleanly to Flutter `CustomPainter`.

---

## 2. How the split works

Three line paths are drawn, one per colour channel, with `globalCompositeOperation
= 'screen'` (additive-toward-white blending on a black background). Where the
three paths overlap, screen-blending R+G+B reconstructs **white**. Where they
separate, each shows its own colour.

Each channel's vertical position is a sine wave whose **phase** is offset per
channel:

```
phase = nx * WAVE_FREQ + time + sign * spread * distortion * CHROMA
```

| Term | Meaning |
|---|---|
| `nx` | normalised x: `(px*2 - W) / min(W,H)`, spans roughly −1 … +1 |
| `WAVE_FREQ` | spatial frequency — how many humps fit across the screen |
| `time` | horizontal scroll (radians); increments per frame |
| `sign` | `+1` red, `0` green, `−1` blue — the channel's split direction |
| `spread` | centre-weight `sin²(πx/W)` — **0 at edges, 1 at centre** |
| `distortion` | audio-driven split amount, `0` (silent) → ~0.36 (loud) |
| `CHROMA` | fixed gain controlling max phase separation between channels |

The critical pieces:

- **`spread = sin²(πx/W)`** is what pins white to the edges. It's exactly 0 at
  `px=0` and `px=W`, so the chromatic term vanishes there → all channels share
  the same phase → overlap → white. It peaks at the centre, so the split is
  strongest mid-screen.
- **`CHROMA` is decoupled from `WAVE_FREQ`.** Earlier versions multiplied the
  offset by the wave frequency, so raising the frequency made the split chaotic.
  Keeping it separate lets the wave be snaky while the colour fringe stays clean.
- The earlier **multiplicative** offset (`p.x * (1 ± d)` from the original
  shader) made the split grow toward the *edges* on a portrait screen. The
  **additive + `spread`-gated** form fixes that.

### Amplitude & shape

```
wave = sin(phase) * yScale
     + sin(phase*2.1 + 1.3) * yScale * 0.38 * (norm*norm)
py   = centreY + wave * (min(W,H) / 2)
```

- `yScale` (audio-driven) sets the wave height: ~0.05 at silence (calm), ~0.50
  at peak (tall).
- The second harmonic only emerges with loudness (`norm²`), so quiet = clean
  single sine, loud = richer, organic snake.

---

## 3. Final tuned constants

These are the values that produced the approved look. All are at the top of the
relevant section in the reference file.

### Geometry / colour

| Constant | Value | Role |
|---|---|---|
| `WAVE_FREQ` | `13` | ~4 humps across the screen. Higher = tighter/more humps. Was the fix for the "single arc" look on portrait. |
| `CHROMA` | `2.6` | Max phase separation between channels. Higher = wider colour fringe. |
| channel signs | `+1 / 0 / −1` | red / green / blue |
| channel colours | `rgb(255,28,28)` `rgb(28,255,28)` `rgb(28,28,255)` | near-pure RGB so screen-blend sums to clean white |
| blend mode | `screen` | additive-toward-white on black |

### Glow stack

Each channel is stroked once per glow layer, widest+faintest first, narrowest+
brightest last. `wf` = lineWidth as a fraction of canvas width (resolution-
independent); `a` = `globalAlpha`.

```
wf      a
0.120   0.016   ← wide soft aura
0.050   0.040
0.018   0.110
0.006   0.360
0.0025  0.780
0.001   1.000   ← bright thin core
```

### Audio → visual mapping

| Constant | Value | Role |
|---|---|---|
| `fftSize` | `512` | time-domain buffer size for RMS |
| `smoothingTimeConstant` | `0.0` | no analyser-side blur; we smooth ourselves |
| attack / release | `0.45` / `0.12` | RMS smoothing: fast attack, slower release |
| `GATE_MARGIN` | `0.012` | RMS must exceed `noiseFloor + margin` before any split |
| `SPEECH_SPAN` | `0.16` | RMS range above the gate mapped to full prism |
| norm curve | `pow(above/SPEECH_SPAN, 0.75)` | slight low-end boost so normal speech reaches a good split |
| `DIST_LERP` | `0.35` | visual smoothing of the split amount |
| `SCALE_LERP` | `0.30` | visual smoothing of amplitude |
| `NORM_LERP` | `0.30` | visual smoothing of the harmonic/speed driver |
| distortion target | `norm * 0.36` | peak split |
| yScale target | `0.05 + norm * 0.50` | calm → tall |
| time increment | `0.01 + visNorm * 0.10` | scroll speed: calm drift → lively flow |

---

## 4. The noise gate (critical)

The biggest correctness pitfall: **do not normalise RMS relative to a recent
peak.** That is an auto-gain that stretches the mic's idle hiss to full scale,
producing a visible prism in silence.

Use an **absolute gate** with an adaptive floor instead:

```js
// Adaptive noise floor — drops instantly to any new quiet minimum,
// rises only very slowly. Learns the device's mic hiss.
if (smoothRms < noiseFloor) noiseFloor = smoothRms;
else noiseFloor += (smoothRms - noiseFloor) * 0.002;
noiseFloor = clamp(noiseFloor, 0.002, 0.06);

const gate  = noiseFloor + GATE_MARGIN;
const above = smoothRms - gate;
const norm  = above <= 0 ? 0 : min(pow(above / SPEECH_SPAN, 0.75), 1.0);
```

`norm` is hard-zero below the gate → silence shows the calm white beam with **no
split**. Only real speech crosses the gate and opens the prism.

The adaptive floor needs ~1s of silence at startup to calibrate. Two dials if
sensitivity is off: raise `GATE_MARGIN` (needs louder speech to start), lower
`SPEECH_SPAN` (reaches full split at lower volume).

---

## 5. Two-stage smoothing

1. **Audio stage** — exponential smoothing on raw RMS (`0.45` attack / `0.12`
   release). Fast enough to catch speech onset, slow enough not to flicker
   between syllables.
2. **Visual stage** — each shader parameter (`visDistort`, `visYScale`,
   `visNorm`) lerps toward its audio-derived target at the `*_LERP` rate. This
   prevents loud spikes from snapping; they ease in over ~3 frames at `0.30–0.35`.

The two stages together were the fix for both "jerky/fast" and "lethargic" —
tune the audio stage for *latency* and the visual stage for *smoothness*
independently.

---

## 6. Rendering notes

- **Black background required.** The `screen` blend and the white-at-overlap
  effect only work on black. The voice UI sits above the canvas with a
  bottom-anchored dark gradient so transcript/buttons stay legible while the
  waveform glows behind the upper half.
- **Resolution independence.** Canvas is sized `innerWidth*DPR × innerHeight*DPR`;
  all widths use `wf * W` and positions use `min(W,H)`, so it scales across
  devices and pixel ratios.
- **Per-frame cost.** 3 channels × 6 glow strokes = 18 strokes/frame, each over a
  full-width `Path2D` built once per channel (3 builds/frame). Cheap enough for
  60fps on mobile.

---

## 7. Flutter port plan

- `CustomPainter` with `BlendMode.screen` paints; one `Path` per channel built
  from the same `phase` formula.
- Glow stack = stroke each path repeatedly with decreasing `strokeWidth` and
  `Paint.color` alpha. Optionally one `MaskFilter.blur` pass for the widest aura
  layer instead of a very wide stroke.
- Audio level from the mic: reuse the wake-word `AudioRecord` RMS, or a
  `record`/stream plugin, feeding the same gate + two-stage smoothing.
- Wrap the canvas in a `RepaintBoundary`; drive repaints from a `Ticker`
  (`vsync`) so only the visualizer repaints each frame.
- Keep all constants from §3 as named fields so they stay tunable.
