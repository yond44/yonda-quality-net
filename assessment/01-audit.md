# 01 — Platform Audit

**Scope:** every file in `api/` and `web/`, the deployment manifests, and the product PRDs (the product wiki's "First Principles: AI Interview Behavior" and "Real Simulation: End-to-End Interview").
**Method:** read the code against the PRDs, then **reproduced the major findings live** against a locally running stack (Rails API + Sidekiq + Postgres + Redis + web app) with a two-tenant fixture. Repro steps are listed per finding.
**Status:** every finding is `open`. The Status column gets updated as Task 3 fixes land.

---

## The 5-minute version

This is a multi-tenant hiring product. An assessor configures an interview. A candidate talks to an AI interviewer by voice. The system then rates each skill L1–L5 and compares the candidate to a vacancy. **Do not ship it to a client.** Three kinds of problem stack up:

1. **Customers are not isolated from each other.** Any assessor can log into *any* customer's workspace by adding one request header (F1). Even without that trick, any assessor can read and **overwrite** another customer's candidate ratings by ID (F2). I proved both live: Tenant A exported Tenant B's confidential candidate portfolio, then changed that candidate's rating from L4 to L1.
2. **Candidates can't reach the interview.** Every invite link points at the API server instead of the web app, so candidates get a 404 (F3).
3. **Hiring decisions rest on data that is silently wrong.** For example:
   - Removing a skill in the edit form doesn't remove it (F4).
   - An AI answer the code can't parse is stored as "L1" and shows up as a skill gap (F5).
   - Anyone holding an invite link can end an interview that never started, and it gets recorded as "all skills covered" (F6).

   Each time, the screen reports success.

There are **no tests and no CI** (M1), so nothing would have caught any of this, and nothing will stop it coming back.

---

## Severity language (from the brief)

Apply top to bottom and stop at the first match. **P0**: the objective can't be achieved at all and there's no workaround. **P1**: it looks like it works, but the data or logic underneath is wrong, or it only works with a manual workaround. *Any data-integrity issue is at least P1.* **P2**: it works and the data is correct, but there's a limited problem. **P3**: cosmetic only.

**Type:** `BUILT-WRONG` means the spec defines it and the build doesn't match. `MISSING-SPEC` means nobody defined it, so nobody can say whether it's correct. Missing-spec items are listed separately in [Missing or ambiguous inputs](#missing-or-ambiguous-inputs-first-class-findings).

**Evidence:**
- **LIVE**: reproduced against the running stack.
- **CODE**: the defect is certain from reading the code, but hasn't been exercised live.
- **RISK**: a plausible failure (usually a race or LLM-dependent) that still needs a test to confirm.

---

## Ranked risk list

| # | Finding | Sev | Type | Evidence | Status |
|---|---------|-----|------|----------|--------|
| F1 | Login lets any user pick any tenant via a request header. Users have no tenant membership. | **P1** | built-wrong | LIVE | open |
| F2 | Cross-tenant read **and write** of portfolios, ratings, and fit/gap reports (IDOR) | **P1** | built-wrong | LIVE | open |
| F3 | Invite links point at the API host, so the candidate gets a 404 | **P1** | built-wrong | LIVE | open |
| F4 | Removing a skill in the Assessment/Vacancy edit form doesn't delete it | **P1** | built-wrong | LIVE | open |
| F5 | An unparseable AI level (`"L3"`, `null`) is stored as **L1**, which produces a fake gap | **P1** | built-wrong | LIVE | open |
| F6 | An unauthenticated `audio_complete` ends any session as `all_covered`, even one that never started | **P1** | built-wrong | LIVE | open |
| F7 | Fit/gap skill matching depends on the LLM echoing labels exactly, and the taxonomy ID is discarded | **P1** | built-wrong | CODE | open |
| F8 | Fit/gap "Required" column is blank and the override marker never shows (web↔API key mismatch) | P2 | built-wrong | LIVE | open |
| F9 | `DELETE /assessments/:id` returns "deleted" but nothing is deleted when sessions exist | P2 | built-wrong | LIVE | open |
| F10 | Confidence is assigned by the LLM, although the PRD defines it deterministically | P2 | built-wrong | CODE | open |
| F11 | Coverage state machine: concurrent analyzer runs, a lost-update race, and an undocumented auto-promote rule | P2 | built-wrong | RISK | open |
| F12 | Transcript turns silently dropped on reconnect or a second tab (turn-number collision swallowed) | P2 | built-wrong | RISK | open |
| F13 | Live-monitor WebSocket authenticates the token but never checks the role | P2 | built-wrong | CODE | open |
| F14 | Taxonomy skill picker drops `scope_exclude`, so "WHAT DOES NOT COUNT" never reaches the AI | P2 | built-wrong | CODE | open |
| F15 | `priority_next` ignores discovered skills and drops a PRD priority tier | P2 | built-wrong | CODE | open |
| F16 | Deployment manifests: API and worker run in different Rails envs, no Secrets are wired, and images use `:latest` | P2 | built-wrong | CODE | open |
| F17 | Hardening: dev-token fallback in the auth path, tenant resolved from an unverified JWT, JWT in localStorage | P2 | built-wrong | CODE | open |
| F18 | Contract type drift: `ai_level` (int vs `"L3"`) and `skill_id` (string vs number). Renders a bare "4". | P3 | built-wrong | CODE | open |
| F19 | Orphaned Signup page posts to a route that doesn't exist, and lets the client choose `role: admin` | P3 | built-wrong | CODE | open |
| F20 | Small UI issues: no language field on the edit form, a misleading button label, the wrong narrative under the culture heading, and no error message when saving a vacancy fails | P3 | built-wrong | CODE | open |

---

## Findings in detail

### F1 — Login lets any user pick any tenant · P1 · LIVE
**Impact:** any admin user can get a valid token for **any customer's workspace** and read or modify all of its assessments, sessions, and candidates. This breaks the core promise of a multi-tenant hiring product. Treat it as a launch blocker whatever the label.

**Where:**
- [`authentication_controller.rb:16-28`](../api/app/controllers/api/v1/authentication_controller.rb#L16-L28): the JWT's `scheme` (tenant) comes from the caller-supplied `X-Tenant-Scheme` header. If the header is absent, it comes from `SELECT scheme FROM organizations LIMIT 1`, meaning an arbitrary first row with no `ORDER BY`.
- [`schema.rb:179-186`](../api/db/schema.rb#L179-L186): `users` has **no organization or tenant column**, so nothing records which tenant a user belongs to.
- [`LoginPage.tsx:24`](../web/src/pages/auth/LoginPage.tsx#L24) sends no tenant header, so every web login lands in "whichever org is first".

**Repro:** as `admin@example.com`, `POST /api/v1/auth/login` returns a token for `scheme: test-corp`. The same request with `X-Tenant-Scheme: other-corp` returns a token for `other-corp`. `GET /api/v1/assessments` with that token then lists Tenant B's "B Confidential Role".

---

### F2 — Cross-tenant read and write of candidate data (IDOR) · P1 · LIVE
**Impact:** using its own *legitimate* token, Tenant A can export Tenant B's candidate portfolio (evidence quotes and competency summaries), **overwrite Tenant B's skill ratings**, and generate fit/gap reports on B's candidates. This corrupts another customer's hiring decisions.

**Where:**
- Isolation depends on the opt-in `TenantScoped` mixin ([`tenant_scoped.rb`](../api/app/models/concerns/tenant_scoped.rb)). `portfolios`, `portfolio_skills` and `fit_gap_reports` have no `tenant_id` ([`schema.rb:85-131`](../api/db/schema.rb#L85-L131)), so they fall outside it.
- Lookups by bare ID:
  - [`portfolios_controller.rb:82`](../api/app/controllers/api/v1/portfolios_controller.rb#L82) (`regenerate_fitgap`)
  - [`:104`](../api/app/controllers/api/v1/portfolios_controller.rb#L104) (`fitgap`)
  - [`:130`](../api/app/controllers/api/v1/portfolios_controller.rb#L130) (`show_fitgap`)
  - [`:156`](../api/app/controllers/api/v1/portfolios_controller.rb#L156) (`export`)
  - **The write path:** [`portfolio_skills_controller.rb:51-52`](../api/app/controllers/api/v1/portfolio_skills_controller.rb#L51-L52) (`override`)

**Repro:** Tenant A's token gets **404** on `GET /sessions/1` (Tenant B's session). The control works. With the same token:
- `GET /portfolios/1/export?format=json` returns B's `"CONFIDENTIAL tenant-B competency summary"`.
- `POST /portfolio_skills/1/override {override_level: 1}` returns **201** and changes B's candidate from L4 to L1.
- `POST /portfolios/1/fitgap` creates a report for B's candidate. It now shows "gap −2", caused by A's override.

---

### F3 — Invite links send candidates to a 404 · P1 · LIVE
**Impact:** the candidate can't open the interview. The assessor has to notice and hand-edit the host. That makes the main flow reachable **only via a manual workaround**.

**Where:** [`session.rb:28-31`](../api/app/models/session.rb#L28-L31) builds `"#{APP_BASE_URL}/interview/#{token}"`. The API README, the sample config, and the production ConfigMap all define `APP_BASE_URL` as the **backend** URL. `/interview/:token` is a **web** route ([`App.tsx:57`](../web/src/App.tsx#L57)), and the API has no such route.

**Repro:** create a session, and `invite_url` = `http://localhost:3001/interview/<token>`. Opening it returns **HTTP 404**. The same token on the web host returns 200.

---

### F4 — "Removed" skills are not removed · P1 · LIVE
**Impact:** the assessor deletes a skill, saves, and sees no error. The candidate still gets interviewed on that skill, and it appears in the portfolio. For vacancies, the role keeps "requiring" a skill the assessor removed, which produces phantom gaps in fit/gap.

**Where:** nested attributes only delete rows marked `_destroy: true` ([`assessment.rb:16-18`](../api/app/models/assessment.rb#L16-L18), [`vacancy.rb:11-13`](../api/app/models/vacancy.rb#L11-L13)). The edit forms simply drop the item from the array:
- [`SkillCard.tsx:64`](../web/src/components/assessment/SkillCard.tsx#L64) → `remove(index)`
- [`AssessmentEditPage.tsx:80`](../web/src/pages/assessments/AssessmentEditPage.tsx#L80)
- [`VacancyEditPage.tsx:49`](../web/src/pages/vacancies/VacancyEditPage.tsx#L49)

**Repro:** create an assessment with skills "Keep Me" and "Remove Me". Send the exact payload the Edit page sends after removing "Remove Me". The server still holds `['Keep Me', 'Remove Me']`. (Vacancy uses the identical mechanism.)

---

### F5 — Unparseable AI levels are stored as L1 · P1 · LIVE
**Impact:** a skill the AI rated as "L3", or couldn't rate at all, is persisted as **L1**, the lowest level. Fit/gap then reports a gap against the role. The portfolio is marked `complete`, so nobody is warned. Notably, the web type itself documents `ai_level` as `"L1"…"L5"` strings ([`types/index.ts:93`](../web/src/types/index.ts#L93)), which suggests that format has been produced before.

**Where:** [`generator.rb:161`](../api/app/services/portfolios/generator.rb#L161) and [`:173`](../api/app/services/portfolios/generator.rb#L173): `skill_data['level'].to_i.clamp(1, 5)`. Both `"L3".to_i` and `nil.to_i` equal `0`, which clamps to `1`.

**Repro:** run `Portfolios::Generator` with a stubbed LLM response. `level: "L3"` is stored as `1`. `level: null` is stored as `1`. `level: 4` is stored as `4`. Portfolio status: `complete`.

---

### F6 — Anyone with the invite link can end the interview as "all covered" · P1 · LIVE
**Impact:** the stored outcome is false. A session that never started, or ended after one minute, is permanently recorded as `end_reason: all_covered`. Portfolio generation then runs on an empty or partial transcript. It also lets a candidate burn their own link, or anyone who sees the link burn it for them.

**Where:** [`sessions_controller.rb:118-129`](../api/app/controllers/api/v1/sessions_controller.rb#L118-L129). The endpoint requires no JWT, and the coverage check was deliberately removed (see the code comment). It also doesn't check that the session was ever `active`.

**Repro:** create a session, then with no auth call `POST /sessions/<token>/audio_complete`. The response is `{"ended":true}`. The stored record is `status=ended end_reason=all_covered started_at=null`, and the coverage map is empty.

---

### F7 — Fit/gap identity depends on the LLM repeating labels exactly · P1 · CODE
**Impact:** if the model paraphrases a skill name ("React / Frontend Development" instead of the taxonomy's "React / Frontend Development Core"), the skill shows as **not assessed** or matches the wrong row. If the model omits a configured skill, it silently disappears from the portfolio. The hiring comparison is wrong, and nothing on screen shows it.

**Where:**
- [`SkillPicker.tsx:41`](../web/src/components/assessment/SkillPicker.tsx#L41) sets `skill_id: undefined`, so taxonomy IDs never reach the assessment.
- [`generator.rb:129`](../api/app/services/portfolios/generator.rb#L129) prints `(custom)` as the ID for every such skill.
- [`generator.rb:156-165`](../api/app/services/portfolios/generator.rb#L156-L165) persists the **LLM-returned** `skill_id` and `skill_label` verbatim instead of mapping back to `assessment_skills`. There's no check that every configured skill came back.
- [`fit_gap/engine.rb:88-91`](../api/app/services/fit_gap/engine.rb#L88-L91) falls back to an exact label match.

*Next step:* a stubbed-LLM test in Task 2 turns this into a LIVE finding.

---

### F8 — Fit/gap "Required" column is blank · P2 · LIVE
**Impact:** on the culminating hiring artifact, the required level never displays, and the "human override applied" marker never appears. The data is correct (the PDF export shows it), so this is P2. But on a "match" row, the assessor can't see the required level at all.

**Where:** the API emits `expected_level` ([`fit_gap/engine.rb:58-66`](../api/app/services/fit_gap/engine.rb#L58-L66)). The web reads `required_level` and `is_override` ([`types/index.ts:130-137`](../web/src/types/index.ts#L130-L137), [`ComparisonTable.tsx:50,56`](../web/src/components/fitgap/ComparisonTable.tsx#L50)). The PDF generator reads `expected_level` ([`pdf_generator.rb:128`](../api/app/services/exports/pdf_generator.rb#L128)), which confirms the web is the side that's out of contract.

**Repro:** the `GET /portfolios/1/fitgap/1` payload contains `"expected_level":3` and neither `required_level` nor `is_override`.

---

### F9 — Delete says "deleted" but nothing is deleted · P2 · LIVE
**Impact:** the API lies about the outcome. An integration or future UI would show the assessment as gone, and it would reappear on refresh. There's no delete button in the current UI, so the exposure is limited to API consumers.

**Where:** [`assessments_controller.rb:51-54`](../api/app/controllers/api/v1/assessments_controller.rb#L51-L54) ignores the return value of `destroy`. `has_many :sessions, dependent: :restrict_with_error` ([`assessment.rb:7`](../api/app/models/assessment.rb#L7)) makes it return `false`.

**Repro:** `DELETE /assessments/2` (which has a session) returns **200** `"Assessment deleted"`. `GET /assessments/2` then returns **200**, so it still exists.

---

### F10 — Confidence is decided by the LLM, not by the rule · P2 · CODE
**Impact:** PRD-01 §5 defines confidence deterministically: high means `probe_count ≥ 3` and `covered`, and so on. The code asks the model to apply that rule ([`generator.rb:97-100`](../api/app/services/portfolios/generator.rb#L97-L100)) and stores whatever comes back ([`:162`](../api/app/services/portfolios/generator.rb#L162)). So stored confidence can contradict the stored coverage map. And a capitalised value ("High") fails validation and fails the whole portfolio. The web defensively lower-cases confidence ([`ConfidenceIndicator.tsx:6`](../web/src/components/portfolio/ConfidenceIndicator.tsx#L6)), which hints this has happened. **This is P1 if it's observed.**

---

### F11 — Coverage state machine races · P2 · RISK
**Impact:** coverage drives when the interview auto-ends and what confidence each skill gets. Nondeterministic coverage means interviews end early or late, and confidence gets skewed.

**Where:**
- A Sidekiq analyzer job is enqueued **per candidate transcription** ([`audio_websocket_middleware.rb:187`](../api/app/channels/audio_websocket_middleware.rb#L187)) with concurrency 10 ([`sidekiq.yml:1`](../api/config/sidekiq.yml#L1)). Jobs for the same session can overlap. Each computes `probe_count + 1` from the same base and writes it back with no lock ([`coverage_analyzer_worker.rb:39-49`](../api/app/workers/coverage_analyzer_worker.rb#L39-L49)), which is a lost update.
- Discovered-skill creation is check-then-insert ([`:53-63`](../api/app/workers/coverage_analyzer_worker.rb#L53-L63)). A race hits the unique index, and the generic rescue aborts the rest of the job.
- `advance_stale_partials` ([`:91-101`](../api/app/workers/coverage_analyzer_worker.rb#L91-L101)) promotes `partial → covered` on count alone, overriding the analyzer's evidence judgment. This rule isn't in the PRD.

---

### F12 — Transcript turns silently dropped · P2 · RISK
**Impact:** the transcript is the evidence base for the portfolio, and lost turns mean lost evidence. Turn numbers come from a per-connection counter seeded from `max(turn_number)` at connect time ([`audio_websocket_middleware.rb:116`](../api/app/channels/audio_websocket_middleware.rb#L116)). Writes happen in background threads. So on a page refresh (the old Gemini connection stays alive for 120s) or a second tab, two counters can hand out the same number. The unique index rejects the second write, and it's swallowed silently ([`:655-656`](../api/app/channels/audio_websocket_middleware.rb#L655-L656)).

---

### F13 — Live monitor doesn't check the role · P2 · CODE
[`coverage_websocket_middleware.rb:125-137`](../api/app/channels/coverage_websocket_middleware.rb#L125-L137) verifies the signature and the tenant, but **not** the role. Any valid token in the tenant (the seed instructions even show how to mint a `student`-role token) can subscribe to any session's live coverage. Unauthenticated sockets also stay open indefinitely, waiting for an `auth` message.

### F14 — "What does not count" never reaches the AI for taxonomy skills · P2 · CODE
PRD-01 §2 puts `WHAT DOES NOT COUNT: {{scope_exclude}}` in every skill block. [`SkillPicker.tsx:40-51`](../web/src/components/assessment/SkillPicker.tsx#L40-L51) copies `scope_include` and the anchors but not `scope_exclude`. So [`system_prompt_compiler.rb:59`](../api/app/services/assessments/system_prompt_compiler.rb#L59) never emits it, and the AI can credit out-of-scope experience.

### F15 — `priority_next` ignores discovered skills · P2 · CODE
PRD priority: `not_yet > initiated > partial > discovered > covered`. [`map_injector.rb:104-114`](../api/app/services/coverage/map_injector.rb#L104-L114) ranks only configured skills, and its order array has no `discovered` tier. The PRD-02 walkthrough expects `priority_next: "discovered"`.

### F16 — Deployment manifests would misconfigure production · P2 · CODE
- The API runs `RAILS_ENV=production` ([`configmap.yaml:11`](../api/k8s/configmap.yaml#L11)), but Sidekiq is started with `-e staging` ([`deploy-sidekiq.yaml:61`](../api/k8s/deploy-sidekiq.yaml#L61)), and no `staging.rb` exists.
- No Secret is referenced, so `SECRET_KEY_BASE`, the DB credentials, `GEMINI_API_KEY` and `REDIS_URL` are never provided. Redis silently falls back to `localhost:6379` inside the pod.
- Images are deployed as `:latest` with `imagePullPolicy: Always` ([`deployment.yaml:62-63`](../api/k8s/deployment.yaml#L62-L63)). No release is reproducible or rollback-able, which matters for Task 4.

### F17 — Auth hardening · P2 · CODE
- [`authAtom.ts:10`](../web/src/stores/authAtom.ts#L10) falls back to `VITE_DEV_TOKEN`. If that's set at build time, every visitor is logged in as that token, and logout can't clear it.
- The tenant is resolved from an **unverified** JWT, then from `Referer`, then from a default org (`id = 0`): see [`tenant_resolver_middleware.rb:33-51`](../api/app/middlewares/tenant_resolver_middleware.rb#L33-L51) and [`organization.rb:13-27`](../api/app/models/organization.rb#L13-L27).
- JWT claims are trusted without a user lookup ([`authorize_api_request.rb:8`](../api/app/auth/authorize_api_request.rb#L8)), so a deleted or demoted user keeps access for the token's 3-day lifetime.
- The interview's anti-injection token is a constant in public source ([`audio_websocket_middleware.rb:16`](../api/app/channels/audio_websocket_middleware.rb#L16)).

### F18–F20 — P3 items
- **F18:**
  - `ai_level` is typed as a string but sent as an int. It's masked by `parseLevel()`, but [`FitGapReportPage.tsx:196`](../web/src/pages/fitgap/FitGapReportPage.tsx#L196) renders a bare "4".
  - `skill_id` is typed `number` but is the string `"SK-ENG-001"` ([`types/index.ts:19`](../web/src/types/index.ts#L19)). [`SkillCard.tsx:57`](../web/src/components/assessment/SkillCard.tsx#L57) would render "SK-SK-ENG-001".
- **F19:** [`SignupPage.tsx`](../web/src/pages/auth/SignupPage.tsx) isn't routed, and it posts to `/signup`, which doesn't exist ([`auth.ts:16`](../web/src/services/auth.ts#L16)). It lets the client choose `role: "admin"`, which would be a privilege escalation the moment someone adds the endpoint. It should be deleted, not finished.
- **F20:**
  - The edit form has no language field, so the language can't be changed after creation ([`AssessmentEditPage.tsx`](../web/src/pages/assessments/AssessmentEditPage.tsx)).
  - The "Save & Create Session →" button doesn't create a session ([`AssessmentNewPage.tsx:251`](../web/src/pages/assessments/AssessmentNewPage.tsx#L251)).
  - The count-based fallback narrative is shown under "Culture & Competency Fit" ([`FitGapReportPage.tsx:173`](../web/src/pages/fitgap/FitGapReportPage.tsx#L173)).
  - A failed vacancy save shows no error ([`VacancyEditPage.tsx:42-55`](../web/src/pages/vacancies/VacancyEditPage.tsx#L42-L55)).

---

## Missing or ambiguous inputs (first-class findings)

Nobody can say whether these are "correct", because no spec defines them. Each one needs a decision before it can be built or tested.

| # | Missing input | Why it matters |
|---|---------------|----------------|
| M1 | **No tests and no CI anywhere** (no specs, no workflows) | Nothing in this list would have been caught, and nothing prevents regressions. *Process-level blocker for this engagement. Task 2 builds it.* |
| M2 | **No user ↔ tenant membership model, and no account provisioning spec** | This is the root cause of F1. There's no defined answer to "which tenants may this user enter?" The only way to create a user is the Rails console. |
| M3 | **The PRD and the code disagree on how interviews close** | PRD-01 §7 and the PRD-02 ending say the AI closes when skills are covered and invites the candidate's questions. The implementation forbids closing without a system signal and forbids asking questions ([`system_prompt_compiler.rb:108-129`](../api/app/services/assessments/system_prompt_compiler.rb#L108-L129)). One of them is stale, and nobody can say which. |
| M4 | **Behaviour that exists only in code:** auto-promotion at `probe_count ≥ 4`, pacing buckets, the discovered-skill cap of 10 | These rules decide when interviews end. They aren't specified, so they can't be reviewed or tested against intent. |
| M5 | **No versioning when an assessment is edited after sessions exist** | Editing skills or anchors retroactively changes what portfolio regeneration and fit/gap compare against for past candidates. |
| M6 | **No frontend URL in the config spec** | Only a backend `APP_BASE_URL` exists. This leads directly to F3. |
| M7 | **No retention rule for hiring evidence** | Deleting a vacancy cascade-deletes every fit/gap report against it ([`vacancy.rb:7`](../api/app/models/vacancy.rb#L7)). |
| M8 | **Confidentiality of the public repo** | The imported code mentions the originating company **50 times across 26 files**, plus internal cloud project, registry, node-pool and production hostnames (`api/k8s/*`, `web/vercel.json`, READMEs, code comments). In production this is an information-disclosure issue, and it conflicts with the brief's "don't name the company" rule. **This needs a scrub decision.** |

---

## Systemic patterns (why these recur)

1. **Isolation is a convention, not a structure.** Tenant safety depends on remembering to include a mixin and to use a scoped finder. Derived records fall outside it (F2), and the identity layer has no concept of tenant membership (F1, M2), nor does the WebSocket (F13). *Fix the class, not the instances:* reach derived records only through their tenant-owned parent, and put a cross-tenant test on every endpoint.
2. **Untested contracts at every boundary.** Web↔API (F8, F18) and **app↔LLM** (F5, F7, F10) are both hand-maintained JSON agreements. The LLM boundary is the more dangerous one: free text from the model is written straight into hiring data with only `to_i.clamp` as validation. *Fix:* contract tests on API payloads, and strict schema validation of LLM output that **fails loudly** instead of defaulting.
3. **Success is reported without checking the outcome.** A save that doesn't save (F4), a delete that doesn't delete (F9), and "all covered" when nothing was covered (F6) all look fine on screen while the data is wrong, which is exactly the class the brief's quality bar calls out.
4. **Concurrency hardened by anecdote.** The comments reference earlier race fixes ("H1", "H4", "H5", "C2"), yet the same patterns remain (F11, F12), with no tests pinning the invariants.
5. **Spec drift.** The code has evolved past the PRDs (M3, M4) and nobody updated the source of truth. That's the "ghost spec" problem the brief describes.

---

## Ship / do-not-ship

**Do not ship.** These are the blockers, each one on its own:
- **F1 and F2:** customer data isn't isolated, and one customer can alter another's hiring decisions.
- **F3:** candidates can't open their interview link.
- **F4, F5, F6:** hiring outcomes can be silently wrong while the UI reports success.

**What I would gate before any client sees it:**
1. Tenant membership on users, and every derived-record lookup scoped through its tenant parent. Regression tests that assert cross-tenant access returns **404** (read and write).
2. Invite URL built from a frontend base URL, with a test that the link resolves to the web route.
3. Edit forms send `_destroy`. LLM output is schema-validated so an invalid level **fails** generation instead of becoming L1. `audio_complete` checks auth or state and coverage before recording `all_covered`.
4. CI on every change, plus a contract check for web↔API payloads (this would have caught F8) and a stubbed-LLM suite for the generator (F5, F7).
5. A spec decision on M3 (how interviews close) and M8 (confidentiality scrub).

F8–F17 can follow in the next iteration, each with a regression check. F18–F20 are backlog.

---

## How this was verified

- **Stack:** Rails API, Sidekiq, PostgreSQL 18 and Redis 8, run natively; the web app via Vite. Gemini used a dummy key, so live AI calls fail by design, and LLM-dependent paths were exercised with stubbed responses.
- **Fixtures:** Tenant A (the seeded org) and Tenant B (a second org holding a confidential portfolio: an L4 "Negotiation" rating with evidence).
- All live repros used plain HTTP calls against the running API with a Tenant-A admin token, except F1 (which obtains a Tenant-B token) and F6 (which needs no token at all). The generator repro (F5) used `rails runner` with a stubbed LLM client.
