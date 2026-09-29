# 01 — Platform Audit

**Author:** [candidate]
**Date:** 2026-09-29
**Scope:** Full read of `api/` (Rails) and `web/` (React) against the product PRDs (product wiki: "First Principles" and "End‑to‑End Interview"). This is the first pass of the assess → build‑net → fix → release loop. It is a **living document**: each finding carries a status (`open` / `fixed` / `remaining`) that I update as Tasks 2–3 progress.

> **Confidentiality note:** the product wiki PRDs contain the client/company/product names and a production hostname. Per the brief's one hard rule, I have **not** copied them into this repo. I keep working references generic ("the product", "the assessor app"). My local copies of the PRDs live outside the repo.

---

## What the platform is (one paragraph)

An **AI‑conducted skills‑interview platform**, multi‑tenant. An *assessor* configures an assessment (role, time limit, a set of skills each with L1–L5 behavioural anchors). A *candidate* opens an invite link and does a live **audio** interview driven by Gemini Live; the AI probes each skill like a human interviewer. A background analyzer ("N7", Gemini Flash) watches the transcript and advances a per‑skill **coverage map** (`not_yet → initiated → partial → covered`, gated by `probe_count`). When every skill is `covered` (or time runs out), the session ends, a **portfolio** is generated ("N10", Gemini Pro) assigning each skill an L1–L5 level + confidence + evidence quotes, and the assessor can run a **fit/gap** report ("N13") comparing the candidate against a vacancy's required levels, and export a PDF/JSON.

The moving parts that matter for risk: the **web↔API contract** (two independently‑typed codebases), the **coverage state machine** (concurrent: EM websocket thread + Sidekiq worker + LLM), and **tenant isolation** (candidate data is sensitive).

---

## How to read the severity column

Per the brief's language, top‑to‑bottom, stop at first match:

| Sev | Meaning |
|-----|---------|
| **P0** | Objective cannot be achieved at all; main function broken; no workaround. |
| **P1** | Looks like it works but data/logic wrong underneath, or reachable only via manual workaround. **Any data‑integrity/confidentiality issue is ≥ P1.** |
| **P2** | Works, data correct, limited non‑blocking issue. |
| **P3** | Purely visual/copy. |

I also separate **[BUILT‑WRONG]** (spec exists, build doesn't match) from **[MISSING‑SPEC]** (never defined, so nobody can say if it's correct).

---

## Ranked findings

### F1 — Cross‑tenant IDOR on portfolios, portfolio‑skills, and fit/gap reports · **P1** · [BUILT‑WRONG]

**Impact:** An authenticated assessor in tenant A can read and mutate another tenant's candidate data (evidence quotes, competency summaries, ratings, fit/gap narratives) by guessing sequential integer IDs. Confidentiality breach of candidate PII across customers — the one promise a multi‑tenant hiring product cannot break. Trends toward **P0** for a client launch.

**Root cause / evidence:**
- Tenant isolation is enforced by `TenantScoped` (a `default_scope where(tenant_id: Current.tenant_id)`), included only in models that have a `tenant_id` column — `Session`, `Assessment`, `Vacancy`.
- `portfolios`, `portfolio_skills`, `fit_gap_reports` have **no `tenant_id` column** ([`db/schema.rb`](api/db/schema.rb#L110-L131)) and do **not** include `TenantScoped`. They are reachable only through a bare primary‑key lookup:
  - [`portfolios_controller.rb`](api/app/controllers/api/v1/portfolios_controller.rb#L103) `Portfolio.find(params[:id])` — also `fitgap`, `show_fitgap`, `regenerate_fitgap`, and `export`'s `set_portfolio`.
  - [`portfolio_skills_controller.rb`](api/app/controllers/api/v1/portfolio_skills_controller.rb#L51-L52) `PortfolioSkill.joins(:portfolio).find(params[:id])` — the **override write path**, so it's read *and* write.
- `require_tenant!` and `authorize_auth_token! :assessor` both pass for *any* valid assessor of *any* tenant; nothing ties the requested record back to `Current.tenant_id`.

**Repro (once running):** as assessor of tenant A, `GET /api/v1/portfolios/<id-belonging-to-B>/fitgap/<vac>` returns B's data; `POST /portfolio_skills/<B-skill-id>/override` mutates B's rating.

**Fix direction (Task 3):** scope every portfolio/fit‑gap lookup through the owning session's tenant (`Portfolio.joins(session: …).where(sessions: { tenant_id: Current.tenant_id })`), or add a validated `tenant_id`. Regression test: assessor of tenant A gets 404 on tenant B's portfolio id.

**Status:** open

---

### F2 — No tests and no CI anywhere in the repo · **P0 (for the engagement)** · [MISSING‑SPEC]

**Impact:** The entire "quality net" this role exists to build is absent. There is **zero** automated coverage (`find` for `*_spec.rb`, `*.test.ts`, `.github/workflows` → nothing) despite a product whose correctness lives in concurrent state machines and LLM‑shaped data. Every finding in this document could regress silently on the next commit. Nothing makes a missing spec, a dropped requirement, or a bad merge visible.

**Evidence:** no `api/spec/` or web test dir; `api/.rspec` exists but no specs; no CI config; `package.json`/`Gemfile` carry no test script wired to a pipeline.

**Note on severity:** this is not a *runtime* P0 (the app can function), so I flag it as a **process/engagement P0** — the top thing I'd gate before a client, and precisely what Task 2 builds. Being explicit rather than inflating a product severity.

**Status:** open — addressed by Task 2 (the net) + Task 4 (release gate).

---

### F3 — Fit/Gap "Required" column renders blank (web↔API key mismatch) · **P2 (high)** · [BUILT‑WRONG]

**Impact:** On the fit/gap report — the culminating hiring artifact — the **Required** level column is always empty. Data is stored correctly; only the screen is wrong (the inverse of the classic P1, so it stays P2 per the rubric: data is intact, issue is limited). But it degrades the primary decision surface: on a `match` row (delta 0) the assessor cannot see the required level at all.

**Root cause / evidence:**
- API emits comparison objects keyed `expected_level` ([`fit_gap/engine.rb`](api/app/services/fit_gap/engine.rb#L58-L67)) and passes the JSONB through verbatim ([`portfolios_controller.rb`](api/app/controllers/api/v1/portfolios_controller.rb#L200-L210)).
- Web type and table read `required_level` ([`types/index.ts`](web/src/types/index.ts#L130-L137), [`ComparisonTable.tsx`](web/src/components/fitgap/ComparisonTable.tsx#L50) → `LEVEL_LABELS[c.required_level]` = `LEVEL_LABELS[undefined]` = blank). No client‑side remap (confirmed in [`FitGapReportPage.tsx`](web/src/pages/fitgap/FitGapReportPage.tsx) and [`portfolios.ts`](web/src/services/portfolios.ts)).

**Same seam, sub‑issue (P3):** the engine never emits `is_override`, and emits `confidence` which the web type doesn't consume — so the ✏ "human override applied" marker in the table [`ComparisonTable.tsx`](web/src/components/fitgap/ComparisonTable.tsx#L56) can never appear even when an override changed the candidate level.

**Fix direction:** align on one contract key (rename in the engine to `required_level`, or map in the controller) and add `is_override`. A contract test asserting the API payload shape matches the TS type would have caught this before a human looked.

**Status:** open

---

### F4 — Coverage `priority_next` ignores discovered skills and drops a priority tier · **P2** · [BUILT‑WRONG]

**Impact:** The AI's "what to probe next" nudge can misprioritise. PRD‑01 defines priority `not_yet > initiated > partial > discovered > covered`, and the injected map is meant to nudge the AI back to a discovered skill (`priority_next: "discovered"` in the PRD‑02 walkthrough). The implementation never surfaces discovered skills in `priority_next` and its order array omits the `discovered` tier.

**Evidence:** [`map_injector.rb`](api/app/services/coverage/map_injector.rb#L104-L114) — `priority_order = %w[not_yet initiated partial covered]`; `priority_next` is computed only over `configured_maps`, `discovered` is never considered. Compare PRD‑01 §"COVERAGE GUIDANCE" and PRD‑02 Exchange 3.

**Fix direction:** include discovered maps in the ranking and represent the `discovered` tier. Not data‑corrupting (affects probing guidance quality), hence P2.

**Status:** open

---

### F5 — Portfolio `ai_level` contract drift (integer vs. "L3" string) · **P2** · [BUILT‑WRONG]

**Impact:** Latent, currently mostly masked. The web type declares `ai_level: string` meaning `"L3"` ([`types/index.ts`](web/src/types/index.ts#L93)), but the API sends the integer `3` ([`portfolios_controller.rb`](api/app/controllers/api/v1/portfolios_controller.rb#L182), column is `integer`). The portfolio card survives only because it defensively runs `parseLevel()` ([`SkillPortfolioCard.tsx`](web/src/components/portfolio/SkillPortfolioCard.tsx#L20)). Any consumer that trusts the type and renders `ai_level` **raw** breaks:
- **Sub‑issue (P3):** the fit/gap page's discovered‑skills list renders `{s.ai_level}` directly ([`FitGapReportPage.tsx`](web/src/pages/fitgap/FitGapReportPage.tsx#L196)) → shows bare "`3`" instead of "L3".

**Why it matters as a class:** two independently‑typed services with a hand‑maintained contract and no contract test — F3 and F5 are the same disease. See systemic pattern below.

**Status:** open

---

### F6 — "What would worry me before a client" (hardening, not individually ranked)

Things I would want on the record and gated, but which I can't confirm as exploitable data loss from static read alone:

- **Tenant resolved from an *unverified* JWT.** `TenantResolverMiddleware` picks the tenant from `JsonWebToken.decode_without_verification(token)`'s `scheme` claim ([`tenant_resolver_middleware.rb`](api/app/middlewares/tenant_resolver_middleware.rb#L42-L51)). Authenticated endpoints still require a validly‑signed token, so this isn't obviously a theft primitive on its own, but tenant selection should never trust unverified input. Worth a focused test + threat review.
- **Concurrency around the coverage state machine.** Coverage rows are written by a Sidekiq worker ([`coverage_analyzer_worker.rb`](api/app/workers/coverage_analyzer_worker.rb)) while the EM websocket thread reads/caches them ([`audio_websocket_middleware.rb`](api/app/channels/audio_websocket_middleware.rb)). The code shows scars of prior race fixes ("H1", "H5", "C2"), which tells me this seam is fragile and under‑tested. The `probe_count` de‑duplication (`safe_probe`, cap +1/run, [`analyzer.rb`](api/app/services/coverage/analyzer.rb#L138)) and `advance_stale_partials` heuristics are exactly the kind of logic that needs deterministic tests around the `StateEngine`.
- **LLM output trusted into the DB.** N7/N10/N13 parse model JSON and `create!` records; `ai_confidence` is a non‑null enum — a malformed confidence value from the model raises and (for N10) marks the portfolio `failed`. Data‑integrity depends on the model behaving. These are the risk‑carrying paths coverage should target (Task 2), not trivial code.

---

## Systemic patterns (the "why this recurs")

1. **Hand‑maintained contract across two type systems, with no contract test.** F3 and F5 are not one‑off typos — they're the predictable result of a Ruby service and a TS client agreeing on JSON shapes by convention only. The fix isn't just renaming a key; it's a **contract check in CI** (assert the serialized API payload matches the TS interface) so the *next* drift goes red automatically.
2. **Isolation added by opt‑in mixin, not by construction.** Tenant safety depends on a developer remembering to `include TenantScoped` and every controller using a scoped finder. Models without a `tenant_id` (derived records) silently fall outside the net → F1. Systemic fix: never look up a derived record except through its tenant‑scoped parent, and test it.
3. **Concurrent state machine hardened by anecdote.** The websocket/worker/`StateEngine` interaction has been patched reactively (the H*/C* comments) with no tests pinning the invariants. Each patch could reintroduce the last bug.

---

## Ship / do‑not‑ship line

**Do not ship to a client in this state.** The blocking reason is **F1 (cross‑tenant data exposure)** — that alone is a launch stopper for a multi‑tenant hiring product. Behind it, **F2 (no quality net)** means we have no way to prove F1 is fixed or that it stays fixed. F3 quietly degrades the core hiring artifact.

**What I would gate before a client:** (1) tenant‑scope every derived‑record lookup with a regression test proving cross‑tenant 404; (2) a CI pipeline that runs on every change; (3) a contract check on the web↔API payloads; (4) the fit/gap Required column fixed. F4/F5 can follow.

---

## Finding index (for traceability)

| ID | Title | Sev | Type | Status |
|----|-------|-----|------|--------|
| F1 | Cross‑tenant IDOR (portfolio/skills/fitgap) | P1 | built‑wrong | open |
| F2 | No tests / no CI | P0 (engagement) | missing‑spec | open |
| F3 | Fit/Gap Required column blank (`expected_level` vs `required_level`) | P2 | built‑wrong | open |
| F4 | `priority_next` ignores discovered skills | P2 | built‑wrong | open |
| F5 | `ai_level` integer vs "L3" contract drift | P2 | built‑wrong | open |
| F3b | Fit/gap `is_override` marker never emitted | P3 | built‑wrong | open |
| F5b | Discovered skill renders bare "3" | P3 | built‑wrong | open |

*Coverage note: this pass prioritised the web↔API seam, tenant isolation, and the coverage/portfolio/fit‑gap data paths. Still to sweep before I call the audit complete: `system_prompt_compiler` + `language` handling, the auth/JWT verification path, the PDF export generator, and the interview‑page audio/reconnect frontend. I'll append findings as I go.*
