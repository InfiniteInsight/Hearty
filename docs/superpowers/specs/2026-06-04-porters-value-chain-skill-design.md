# Porter's Value Chain Skill — Design Spec

**Date:** 2026-06-04
**Status:** Approved (design), pending implementation
**Type:** User-level Claude Code skill

## Purpose

A reusable strategy skill that applies Michael Porter's Value Chain framework
to analyze where competitive advantage and margin are created. It works on two
kinds of targets:

- **External companies** — a named business the user wants to analyze.
- **The user's own projects** — software/app projects (e.g. Hearty), pulling
  context from the repo where possible.

It serves three uses that the user confirmed:

1. **Analyze** a target activity-by-activity.
2. **Teach/explain** the framework when the user is learning rather than analyzing.
3. **Produce a repeatable deliverable** (matrix + diagram + synthesis).

## Location & Form

- **Path:** `~/.claude/skills/porters-value-chain/SKILL.md` (user-level —
  available in every project, not scoped to one repo).
- **Form:** Single `SKILL.md`. Add a `references/` file only if the
  activity-translation tables grow long enough to clutter the main file.

## Trigger (frontmatter `description`)

The skill should fire when the user asks to:

- analyze a company's or product's value chain,
- find sources of competitive advantage or margin,
- run a Porter's value-chain / strategy breakdown,

for either an external company **or** one of the user's own projects.

## The Two Modes

The skill asks up front which mode to run (the user explicitly wanted to choose
each time):

### Classic mode
The literal nine Porter activities. Force-fit the target into them and note
where an activity is N/A.

- **Primary:** Inbound logistics, Operations, Outbound logistics,
  Marketing & sales, Service.
- **Support:** Firm infrastructure, HR management, Technology development,
  Procurement.

### Software-adapted mode
Porter's structure, translated for software/app/indie projects. Translation
table the skill carries:

| Porter activity | Software-adapted lens |
|---|---|
| Inbound logistics | Data/content ingestion & API/3rd-party pipelines |
| Operations | Development, build, infra/hosting, model/runtime ops |
| Outbound logistics | Distribution — app stores, web delivery, releases |
| Marketing & sales | Growth, ASO, positioning, conversion |
| Service | Support, onboarding, retention, community |
| Firm infrastructure | Tooling, CI/CD, finance/legal/ops scaffolding |
| HR management | Team & collaborators (incl. co-launch partners) |
| Technology development | R&D, novel tech/IP (e.g. on-device voice, wake word) |
| Procurement | Vendor/tooling/service purchasing, model/API sourcing |

## Workflow the Skill Drives

1. **Identify the target.** For the user's own projects, gather context from the
   repo and conversation. For external companies, ask the user for what's known
   (no auto-fetching financials — see out of scope).
2. **Pick the mode** (Classic vs Software-adapted) — ask up front.
3. **Map the activities** → output a **matrix**:
   `activity × cost drivers × current state × competitive-advantage potential`.
4. **Render the diagram** — the classic value-chain shape: support activities as
   horizontal bands across the top, primary activities as the arrow of boxes,
   **Margin** on the right. Default to a clean ASCII/Markdown rendering inline;
   offer an HTML/SVG version on request.
5. **Strategic synthesis** — identify the **2-3 activities** that are the real
   source of, or biggest threat to, advantage/margin, with **concrete
   prioritized next actions**.

## Deliverable

- By default, print **matrix + diagram + synthesis** in chat.
- Offer to save a Markdown artifact. For repeat use, suggest a consistent path
  such as `docs/strategy/<target>-value-chain.md`.

## Teaching Branch (Use #2)

If the user is clearly asking to *learn* the framework rather than analyze a
target, the skill explains the framework with a worked example instead of
running the full workflow. This is a lightweight branch inside the skill, not a
separate prompted mode.

## Out of Scope (YAGNI)

- No scoring/weighting rubric.
- No competitor benchmarking.
- No auto-fetching of external company financials — the skill works from what
  the user provides or what's in the repo.

## Success Criteria

- Skill loads via the Skill tool and announces itself.
- Asks Classic vs Software-adapted up front.
- Produces a matrix, a value-chain diagram, and a prioritized synthesis.
- Handles both an external company and one of the user's own projects.
- Offers (but does not force) a saved Markdown artifact.
