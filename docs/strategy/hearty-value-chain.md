# Hearty — Porter's Value Chain (Software-Adapted)

*Date: 2026-06-05*

*Target: Hearty / GutLog — a food & symptom journal with hands-free, on-device
voice logging. Flutter + Supabase. Pre-launch, co-launching with a small
collective. Assumptions are flagged where inferred beyond what's in the repo.*

## Activity Matrix

| Activity | Cost drivers | Current state | Competitive-advantage potential |
|---|---|---|---|
| **Inbound logistics** (data/content & API pipelines) | Food database licensing/ingestion, symptom taxonomy curation, audio capture pipeline | Voice → transcription pipeline built; food/symptom data model exists. *Assumption: food reference data not yet a licensed corpus.* | **Medium** — a clean, structured symptom↔food dataset compounds over time; the audio→entry pipeline is hard to copy well. |
| **Operations** (dev, build, infra, model/runtime ops) | Flutter dev time, Supabase costs, on-device model runtime (ORT), wake-word/TTS maintenance | Core app + Supabase live; "Hey Hearty" wake word deployed (opset12, ~0.62); non-binary TTS chosen, export pending | **High** — on-device inference = low marginal cost + privacy story. The runtime ops *are* the product's moat. |
| **Outbound logistics** (distribution) | App store fees, release/signing, build pipeline, review cycles | Android-focused; Pixel 4a test path; not yet published. *Assumption: no iOS build yet.* | **Low** — distribution channels are commodity; nobody wins here, but stalling here blocks everything. |
| **Marketing & sales** (growth, ASO, positioning, conversion) | Content creation, ASO, co-launch coordination, no paid budget assumed | Co-launch collective (Feygon/Sammie/Effy) is the primary channel; positioning around accessibility/hands-free | **High** — the accessibility + voice-first angle is a sharp, underserved wedge vs. generic food trackers. |
| **Service** (support, onboarding, retention) | Support time, onboarding flow build, retention loops (check-ins) | Daily check-in + trends conversation features specced/planned; onboarding heroes in progress | **High** — symptom journals live or die on retention; voice + gentle check-ins directly attack the #1 churn cause (logging friction). |
| **Firm infrastructure** (tooling, CI/CD, ops scaffolding) | CI/CD setup, secrets/creds mgmt (`make run`), legal/privacy for health data | `make run` workflow, Supabase creds managed; **health-data privacy posture not yet formalized** *(assumption)* | **Low-Medium** — table stakes, but a credible privacy stance becomes marketing fuel given on-device processing. |
| **HR / team & collaborators** | Founder time; coordination with co-launch partners | Solo dev + co-launch collective with adjacent disabled-focused products | **Medium** — the collective is a genuine distribution & credibility asset most solo apps lack. |
| **Technology development** (R&D, novel tech/IP) | Voice model training (pkix workstation), wake-word tuning, TTS recipe, custom UI | Custom non-binary TTS recipe locked; wake-word pipeline; Prism waveform + radial clock designs | **Very High** — this is the real IP. On-device gender-neutral voice + wake word is differentiated and defensible. |
| **Procurement** (vendor/model/API sourcing) | GPU/training compute, Supabase tier, model licenses, any food-data API | pkix RTX workstation for training; Supabase; open model lineage for voice | **Low** — well-sourced and cheap; not a differentiator, but the low-cost base protects margin. |

## Value-Chain Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Firm Infrastructure   — CI/CD, make run, health-data privacy │\
│ Team & Collaborators  — solo dev + co-launch collective      │ \
│ Technology Dev        — on-device voice / wake word / TTS ◀IP │  >  M
│ Procurement           — pkix GPU, Supabase, open models      │ /   A
├──────────┬──────────┬──────────┬──────────────┬─────────────┤/    R
│ Data &   │ Dev +    │ App      │  Growth /    │  Support /  │  >  G
│ Voice    │ Infra +  │ Store    │  Co-launch / │  Check-ins /│ /   I
│ Pipeline │ Model Ops│ Releases │  Access angle│  Retention  │     N
└──────────┴──────────┴──────────┴──────────────┴─────────────┘
   inbound   operations  outbound   marketing       service
```

## Strategic Synthesis — where the margin actually is

**1. Technology Development → Operations (on-device voice) is the real moat.
Defend and ship it.**
The custom wake word + non-binary TTS + on-device inference is the one thing
competitors can't quickly clone, and it doubles as both a privacy story and an
accessibility story. It's also the biggest *risk*: the wake word is still
scoring ~0.62 and unproven in a quiet-room test, and TTS export is pending.
→ **Next action:** Close the wake-word quiet-room validation and finish the TTS
export *before* polishing UI — this activity gates the entire differentiation
thesis.

**2. Service (retention via low-friction logging) is where the value compounds —
and where journals usually die.**
Every food/symptom tracker bleeds users because manual logging is tedious. Voice
+ daily check-ins is a direct structural answer, but it only counts if it's in
users' hands.
→ **Next action:** Wire the voice-logging + daily check-in loop end-to-end into
the shippable build and instrument retention from day one — make "logged
hands-free in <10s" the activation metric.

**3. Marketing & Sales (accessibility/voice-first wedge + the collective) is the
cheapest leverage.**
There's a sharp, underserved positioning *and* a built-in co-launch channel with
adjacent disability-focused products — most solo apps have neither.
→ **Next action:** Lock the positioning to "the hands-free, private symptom
journal" and pre-coordinate a synchronized launch beat with Feygon/Sammie/Effy
so the collective amplifies one clear message.

**The trap to avoid:** Outbound logistics (getting it published) is *low*
advantage but currently *blocking* — don't let an unpublished, Android-only
build sit while perfecting the voice. Margin only exists once it ships.
