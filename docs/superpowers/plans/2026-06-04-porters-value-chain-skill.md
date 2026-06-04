# Porter's Value Chain Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The authoring sub-skill for the skill file itself is **superpowers:writing-skills**.

**Goal:** Create a user-level Claude Code skill that applies Porter's Value Chain framework to analyze external companies and the user's own software projects, producing a matrix, a value-chain diagram, and a prioritized strategic synthesis.

**Architecture:** A single `SKILL.md` at `~/.claude/skills/porters-value-chain/` with YAML frontmatter (name + trigger description) and a body that drives a 5-step workflow with two selectable modes (Classic / Software-adapted) and a teaching branch. A `references/translation-table.md` holds the software-adapted activity lens so the main file stays lean.

**Tech Stack:** Markdown + YAML frontmatter. No code, no build. Verification is structural (frontmatter validity) and behavioral (does following the skill produce the deliverables).

Spec: `docs/superpowers/specs/2026-06-04-porters-value-chain-skill-design.md`

---

### Task 1: Scaffold the skill directory and frontmatter

**Files:**
- Create: `~/.claude/skills/porters-value-chain/SKILL.md`

- [ ] **Step 1: Create the directory**

Run:
```bash
mkdir -p ~/.claude/skills/porters-value-chain
```
Expected: no output, exit 0.

- [ ] **Step 2: Write SKILL.md frontmatter + title**

Write this exact frontmatter as the top of the file. The `description` is the
trigger — it must name both target types (external company / own project) and
the intent verbs so the Skill tool surfaces it at the right time.

```markdown
---
name: porters-value-chain
description: Use when analyzing where competitive advantage or margin comes from — running a Porter's Value Chain breakdown of a company OR one of the user's own software/app projects. Triggers on "value chain", "competitive advantage", "where's the margin", "strategy breakdown", or mapping a product's activities to find strengths/threats.
---

# Porter's Value Chain Analysis
```

- [ ] **Step 3: Verify frontmatter is valid YAML and within length norms**

Run:
```bash
python3 -c "import sys,yaml; t=open('$HOME/.claude/skills/porters-value-chain/SKILL.md').read(); fm=t.split('---')[1]; d=yaml.safe_load(fm); assert d['name']=='porters-value-chain'; assert 0 < len(d['description']) <= 500; print('ok', len(d['description']))"
```
Expected: `ok <n>` where n ≤ 500.

- [ ] **Step 4: Commit**

```bash
cd ~/.claude && git add skills/porters-value-chain/SKILL.md 2>/dev/null; echo "frontmatter scaffolded"
```
(Note: `~/.claude` may not be a git repo. If `git add` errors, that is fine — the file is saved regardless. Do not initialize a repo there.)

---

### Task 2: Write the workflow body (the 5 steps + mode selection)

**Files:**
- Modify: `~/.claude/skills/porters-value-chain/SKILL.md`

- [ ] **Step 1: Append the "How to run" workflow section**

Append the following to `SKILL.md`. This is the operational core.

````markdown
## How to run an analysis

Follow these steps in order. Announce: "Using the Porter's Value Chain skill."

### Step 1 — Identify the target
Determine what is being analyzed.
- **User's own project:** gather context from the repo and conversation
  (README, product docs, recent commits, known collaborators). Do not ask the
  user for facts you can read yourself.
- **External company:** ask the user for what they know. Do NOT fetch financials
  or invent figures — work only from provided/known information, and flag
  assumptions explicitly.

### Step 2 — Pick the mode (ask up front)
Ask the user which lens to use:
- **Classic** — the literal nine Porter activities, force-fitting the target and
  marking any activity N/A where it does not apply.
- **Software-adapted** — Porter's structure translated for software/app/indie
  projects. Use the translation table in `references/translation-table.md`.

Do not assume — ask, even for an obviously-software target, because the user
wanted to choose each time.

### Step 3 — Map the activities into a matrix
Produce a Markdown table with one row per activity (primary first, then
support), columns:

| Activity | Cost drivers | Current state | Competitive-advantage potential |
|---|---|---|---|

Fill every cell. Use "N/A — <reason>" rather than leaving blanks.

### Step 4 — Render the value-chain diagram
Draw the classic shape inline as ASCII/Markdown: support activities as
horizontal bands across the top, primary activities as the left-to-right arrow
of boxes, and **Margin** on the right. Use this template, relabeling the primary
boxes for Software-adapted mode:

```
┌─────────────────────────────────────────────────────────────┐
│ Firm Infrastructure                                          │\
│ Human Resource Management                                    │ \
│ Technology Development                                       │  >  M
│ Procurement                                                  │ /   A
├──────────┬──────────┬──────────┬──────────────┬─────────────┤/    R
│ Inbound  │Operations│ Outbound │  Marketing   │  Service    │  >  G
│Logistics │          │ Logistics│   & Sales    │             │ /   I
└──────────┴──────────┴──────────┴──────────────┴─────────────┘     N
```

Offer an HTML/SVG version only if the user asks.

### Step 5 — Strategic synthesis
Identify the **2-3 activities** that are the real source of, or biggest threat
to, competitive advantage / margin. For each, give a one-line rationale and a
**concrete, prioritized next action**. This is the payoff — never skip it.

## Deliverable
By default, print matrix + diagram + synthesis in chat. Then offer to save a
Markdown artifact, suggesting a consistent path like
`docs/strategy/<target>-value-chain.md`. Save only if the user agrees.
````

- [ ] **Step 2: Verify the body contains each required section**

Run:
```bash
grep -c -E "Step 1 — Identify|Step 2 — Pick the mode|Step 3 — Map|Step 4 — Render|Step 5 — Strategic synthesis|## Deliverable" "$HOME/.claude/skills/porters-value-chain/SKILL.md"
```
Expected: `6`

- [ ] **Step 3: Save (commit if repo, else noop — see Task 1 Step 4)**

---

### Task 3: Add the teaching branch

**Files:**
- Modify: `~/.claude/skills/porters-value-chain/SKILL.md`

- [ ] **Step 1: Append the teaching-mode section**

````markdown
## Teaching mode

If the user is asking to *learn* the framework rather than analyze a specific
target (e.g. "explain Porter's value chain", "what is the value chain"), skip
the workflow above. Instead:

1. Explain primary vs. support activities and the concept of margin.
2. Walk one short worked example (pick a familiar company or, if the user has an
   active project, theirs) through 2-3 activities.
3. Offer to run a full analysis next.

Keep it concise — this is an explainer, not a full mapping.
````

- [ ] **Step 2: Verify**

Run:
```bash
grep -c "## Teaching mode" "$HOME/.claude/skills/porters-value-chain/SKILL.md"
```
Expected: `1`

---

### Task 4: Add the software-adapted translation table reference

**Files:**
- Create: `~/.claude/skills/porters-value-chain/references/translation-table.md`

- [ ] **Step 1: Create the references file**

Run:
```bash
mkdir -p ~/.claude/skills/porters-value-chain/references
```

- [ ] **Step 2: Write the translation table**

```markdown
# Software-Adapted Value Chain — Activity Translation

Use these lenses when running the skill in **Software-adapted** mode. Keep
Porter's structure; reinterpret each activity for a software/app/indie product.

## Primary activities
| Porter activity | Software-adapted lens |
|---|---|
| Inbound logistics | Data/content ingestion & API / 3rd-party pipelines |
| Operations | Development, build, infra/hosting, model/runtime ops |
| Outbound logistics | Distribution — app stores, web delivery, releases |
| Marketing & sales | Growth, ASO, positioning, conversion |
| Service | Support, onboarding, retention, community |

## Support activities
| Porter activity | Software-adapted lens |
|---|---|
| Firm infrastructure | Tooling, CI/CD, finance/legal/ops scaffolding |
| HR management | Team & collaborators (incl. co-launch partners) |
| Technology development | R&D, novel tech/IP (e.g. on-device voice, wake word) |
| Procurement | Vendor/tooling/service purchasing, model/API sourcing |

When a project has no meaningful activity in a row, mark it "N/A — <reason>"
rather than inventing one.
```

- [ ] **Step 3: Verify the SKILL.md references this file**

Run:
```bash
grep -c "references/translation-table.md" "$HOME/.claude/skills/porters-value-chain/SKILL.md"
```
Expected: `1` (from Task 2, Step 2 — the mode-selection text).

---

### Task 5: End-to-end verification

- [ ] **Step 1: Confirm file tree**

Run:
```bash
find ~/.claude/skills/porters-value-chain -type f | sort
```
Expected:
```
/home/evan/.claude/skills/porters-value-chain/SKILL.md
/home/evan/.claude/skills/porters-value-chain/references/translation-table.md
```

- [ ] **Step 2: Apply the writing-skills review**

Use `superpowers:writing-skills` to review the finished skill: check that the
description triggers on the intended phrases without over-triggering, that the
body has no placeholders, and that following it as written produces matrix +
diagram + synthesis. Fix anything it flags inline.

- [ ] **Step 3: Live trigger test (manual)**

In a fresh session (or `/skills` listing), confirm `porters-value-chain` appears
in the available skills list. Then prompt: "Run a Porter's value chain on
Hearty." Confirm the skill is invoked, asks Classic vs Software-adapted, and
yields the three deliverables.

- [ ] **Step 4: Update memory**

Add a one-line pointer in
`/home/evan/.claude/projects/-home-evan-projects-food-journal-assistant/memory/MEMORY.md`
and a `project`-type memory file noting the skill exists, its location, and the
two modes — so future sessions know it is available.

---

## Self-Review

**Spec coverage:**
- Location/form (user-level single SKILL.md + references) → Task 1, Task 4. ✓
- Trigger description naming both target types → Task 1 Step 2. ✓
- Classic vs Software-adapted, asked up front → Task 2 Step 1 (Step 2 of workflow). ✓
- Translation table → Task 4. ✓
- Matrix output → Task 2 (workflow Step 3). ✓
- Diagram → Task 2 (workflow Step 4). ✓
- Strategic synthesis, 2-3 activities + actions → Task 2 (workflow Step 5). ✓
- Deliverable: print by default, offer to save → Task 2 (## Deliverable). ✓
- Teaching branch → Task 3. ✓
- Out of scope (no financial auto-fetch, no scoring rubric, no benchmarking) → enforced in Task 2 workflow Step 1 text. ✓

**Placeholder scan:** No "TBD"/"handle edge cases"/"write tests for the above".
The diagram and tables are fully written, not described. ✓

**Type/name consistency:** Skill name `porters-value-chain`, path
`~/.claude/skills/porters-value-chain/`, and reference
`references/translation-table.md` are used identically across all tasks. ✓
