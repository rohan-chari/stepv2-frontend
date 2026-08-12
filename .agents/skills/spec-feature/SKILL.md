---
name: spec-feature
description: >-
  Use this skill AUTOMATICALLY for ANY request to add, build, create, or
  implement a new feature or new functionality (not bug fixes or one-line
  tweaks). Triggers include "add a feature", "build X", "I want the app to do
  Y", "implement Z", "new screen/endpoint/system". Runs the PM/BA spec-first
  pipeline: explore → written spec → gap passes → interview → architect review
  → approval gate → two implementation agents. Never jump straight to code for
  a new feature.
---

# New feature workflow: spec first, code later

When the user asks for a **new feature**, do NOT jump to code. Put on a PM/BA
hat and produce a written spec first; code only after explicit approval.

Subagents referenced here are defined in `.codex/agents/*.toml` — spawn them by
name (`architect`, `game-analyst`, `ui-test-planner`, `backend-developer`,
`frontend-developer`, `code-reviewer`).

## Phase 1 — Explore & draft the spec
1. Explore the codebase for everything this feature touches (models, endpoints,
   screens, existing similar features, DB shape). Cite real files/lines.
2. Write a spec to `docs/<feature-kebab>-requirements.md` using the template
   below. It must describe both **what** the feature is and **the exact path a
   developer takes to implement it** (files, endpoints, migrations, order of ops).

## Phase 2 — Two fresh-eyes gap passes
3. Re-read the spec from scratch as if you didn't write it. Find gaps,
   ambiguity, unhandled edge cases, and violations of AGENTS.md's hard rules.
   Fix them.
4. Do it **again** — a second independent pass. Log what each pass changed in a
   "Revision log" section at the bottom.

## Phase 3 — Interview the user on anything unresolved
5. Any requirement still ambiguous → **interview the user**. Batch related
   questions into one message; don't dribble them one at a time. Fold answers
   back into the spec. Repeat Phase 2→3 until zero open questions.

## Phase 4 — Architect review + UI test plan, then approval gate
6. Run the **`architect` subagent** on the finished spec. It reviews the design
   against the compat rules, API contract quality, migration safety, and
   rollout plan, and returns REQUIRED changes vs. suggestions. Fold REQUIRED
   changes into the spec (re-running Phase 2 if the changes are substantial).
6b. If the spec touches **odds, drop rates, spin weights, prices, payout
   curves, coin sources/sinks, multipliers, or scoring rules**, also run the
   **`game-analyst` subagent** on it (in parallel with the architect). Fold its
   REQUIRED changes (an `UNSOUND` or `SOUND WITH CHANGES` verdict) into the
   spec the same way.
6c. If the spec **adds, moves, or removes anything a user sees on a screen**,
   also run the **`ui-test-planner` subagent** (in parallel with the architect —
   they're independent). It returns a manual UI-placement checklist covering
   every mirrored surface (demo race tutorial, tab tutorial previews,
   onboarding, hand-forked copies like the races-tab effect plates). Its
   "risks found while planning" (missing demo/tutorial fixture fields,
   spotlight keys on moved widgets, forked copies needing manual mirroring)
   become explicit spec steps for the implementation agents.
7. Present the finished spec **and the ui-test-planner's manual checklist
   verbatim** (also add it to the spec under a "Manual UI-placement test
   plan" section), and **wait for explicit user approval.** Do not spawn
   implementation agents before the user says go.

## Phase 5 — Two implementation agents
Spawn exactly two subagents (`backend-developer`, `frontend-developer` —
defined in `.codex/agents/`), told to follow the spec's steps **in order**.

**Sequencing: contract first, then parallel.** The backend agent pins and lands
the API contract first; once the contract is locked, both implement in parallel
against it. The frontend agent never codes against a moving contract.

Both agents, without exception:
- **Write tests FIRST**, then the business logic. (Backend:
  `npm run test:unit` / `npm run test:integration`, never bare `npm test`.
  Never point tests at the prod DB.)
- **Never weaken or delete existing assertions** to make things pass;
  mechanical updates (imports, renames) are fine. Surface suspicious tests.
- Implement business logic only after the new tests exist and fail for the
  right reason.

After both agents finish, run the **`code-reviewer` subagent** on the combined
diff before presenting the work as done.

## The spec document MUST contain
- **Summary & user story** — what, for whom, why.
- **Scope / non-goals** — explicitly what's out.
- **API contract** — every new/changed endpoint with exact request & response
  JSON, error cases, and how the *backend* stays compatible with **older app
  versions still in the wild** (AGENTS.md rule #1).
- **Data model / migrations** — tables/columns, backfill, default-safe reads.
- **Frontend plan** — screens/widgets, states (loading/empty/error), and how
  the UI **degrades safely when a field is missing**. iOS + Android both.
- **Backward-compat & rollout** — deploy order (backend first, then app), what
  a frozen old client does against the new backend, any `testOnly`/feature
  gating until the App Store build rolls out (~a week, phased).
- **Test plan** — the tests-first list each agent writes before coding.
- **Acceptance criteria / definition of done.**
- **Revision log** — what Phase 2's gap passes and the architect review changed.
