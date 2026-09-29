# 01 — Platform Audit

**What I checked:** all the code in `api/` (backend) and `web/` (frontend), the deployment files, and the two product specs from the product wiki ("First Principles: AI Interview Behavior" and "Real Simulation: End-to-End Interview").

**How I checked:**
1. I read the code and compared it to the specs.
2. I ran the whole app on my machine and **reproduced the main problems for real**. Each finding below says how to reproduce it.

**Status:** every finding is `open`. I will update the Status column as fixes land in Task 3.

---

## What the platform is

It is an **AI interview platform** used by several customer companies at once. In the code, each customer company is called a **tenant**.

1. An **assessor** (a recruiter at a customer company) creates an assessment: a role, a time limit, and the skills to test. Each skill has a description of what level 1 to level 5 looks like.
2. The assessor sends an **invite link** to a **candidate**.
3. The candidate opens the link and has a **voice interview with an AI**. The AI asks follow-up questions, like a human interviewer would.
4. While they talk, a second AI keeps a **coverage map**: for each skill, has it been discussed enough yet? When every skill is covered, the interview ends.
5. After the interview, a third AI writes a **portfolio**: a level (L1–L5) for each skill, a confidence rating, and quotes from the candidate as evidence.
6. The assessor can compare the portfolio to a **vacancy** (what the role requires). This is the **fit/gap report**: for each skill, "match", "gap", or "exceeds".

The riskiest parts are:
- **The frontend and backend agree on data shapes by convention only.** They are two separate codebases, and nothing checks that they match.
- **AI output is saved straight into hiring data.**
- **One customer's data must never be visible to another customer.**

---

## Summary (5-minute read)

**Do not ship this to a client.** There are three groups of problems:

1. **Customers are not separated from each other.**
   - Any assessor can log into *another company's* workspace just by adding one header to the login request (F1).
   - Even without that trick, any assessor can read *and change* another company's candidate ratings by guessing an ID number (F2).
   - I proved both on the running app: from Company A's account, I downloaded Company B's confidential candidate report, then changed that candidate's rating from L4 to L1.
2. **Candidates can't start their interview.** The invite link points to the backend server instead of the website, so the candidate sees a "404 Not Found" page (F3).
3. **Hiring results can be silently wrong, while the screen says everything worked.**
   - Removing a skill in the edit form doesn't actually remove it (F4).
   - If the AI answers in a format the code doesn't expect, the skill is saved as the lowest level, L1 (F5).
   - Anyone with the invite link can end an interview that never started, and it is recorded as "all skills covered" (F6).

On top of that, **there are no automated tests and no CI** (M1). Nothing would have caught these problems, and nothing will stop them from coming back.

---

## How to read this document

**Severity** (from the brief; go top to bottom and stop at the first match):

| Level | Meaning |
|-------|---------|
| **P0** | It can't be done at all, and there's no workaround. The main function is broken. |
| **P1** | It *looks* like it works, but the data or logic underneath is wrong, or it only works with a manual workaround. **Any data-integrity problem is at least P1.** |
| **P2** | It works and the data is correct, but there is a limited problem. |
| **P3** | Only looks or wording. No effect on function or data. |

**Type:**
- `BUILT-WRONG`: the spec says what should happen, and the code doesn't do it.
- `MISSING-SPEC`: nobody ever defined it, so nobody can say what is correct. These are listed separately in [Missing or unclear specs](#missing-or-unclear-specs).

**Evidence:**
- **LIVE**: I reproduced it on the running app.
- **CODE**: the code clearly does this, but I haven't triggered it live yet.
- **RISK**: it can plausibly happen (usually timing- or AI-dependent), but it needs a test to confirm.

---

## Ranked list

| # | Problem | Sev | Type | Evidence | Status |
|---|---------|-----|------|----------|--------|
| F1 | Login lets any user pick any company's workspace | **P1** | built-wrong | LIVE | open |
| F2 | One company can read **and change** another company's candidate data | **P1** | built-wrong | LIVE | open |
| F3 | Invite links lead candidates to a 404 page | **P1** | built-wrong | LIVE | open |
| F4 | Removing a skill in an edit form doesn't remove it | **P1** | built-wrong | LIVE | open |
| F5 | AI levels in an unexpected format are saved as **L1** | **P1** | built-wrong | LIVE | open |
| F6 | Anyone with the invite link can end the interview as "all covered" | **P1** | built-wrong | LIVE | open |
| F7 | Candidate-vs-vacancy comparison depends on the AI repeating skill names exactly | **P1** | built-wrong | CODE | open |
| F8 | "Required" column in the fit/gap table is always empty | P2 | built-wrong | LIVE | open |
| F9 | Delete says "deleted" but nothing is deleted | P2 | built-wrong | LIVE | open |
| F10 | The AI decides "confidence", although the spec gives a fixed rule | P2 | built-wrong | CODE | open |
| F11 | Coverage updates that run at the same time can overwrite each other | P2 | built-wrong | RISK | open |
| F12 | Transcript lines can be silently lost when the page is refreshed | P2 | built-wrong | RISK | open |
| F13 | The live-monitor connection doesn't check the user's role | P2 | built-wrong | CODE | open |
| F14 | "What does not count" is never sent to the AI for skills picked from the list | P2 | built-wrong | CODE | open |
| F15 | The "what to ask next" hint ignores skills the candidate brought up | P2 | built-wrong | CODE | open |
| F16 | Deployment files would set production up wrong | P2 | built-wrong | CODE | open |
| F17 | Login security gaps | P2 | built-wrong | CODE | open |
| F18 | Frontend and backend disagree on field types (shows "4" instead of "L4") | P3 | built-wrong | CODE | open |
| F19 | A leftover sign-up page lets users choose to be "admin" | P3 | built-wrong | CODE | open |
| F20 | Small UI issues | P3 | built-wrong | CODE | open |

---

## Findings in detail

### F1 — Login lets any user pick any company's workspace · P1 · LIVE

**Impact:** any admin user can get into **any customer company's workspace**, and read or change all of its assessments and candidates. For a product that many companies share, this is a launch blocker.

**What goes wrong:**
- The login endpoint decides which company you belong to from a header *you* send (`X-Tenant-Scheme`). If you send no header, it picks **whichever company happens to be first in the database** (`SELECT scheme FROM organizations LIMIT 1`, with no `ORDER BY`, so the order isn't even guaranteed). See [`authentication_controller.rb:16-28`](../api/app/controllers/api/v1/authentication_controller.rb#L16-L28).
- The `users` table has **no company column at all** ([`schema.rb:179-186`](../api/db/schema.rb#L179-L186)). So the system can't know which company a user really belongs to.
- The website's login page sends no header ([`LoginPage.tsx:24`](../web/src/pages/auth/LoginPage.tsx#L24)), so every web login lands in "the first company".

**How I reproduced it:**
1. Log in as `admin@example.com`. The token says company = `test-corp`.
2. Log in again with the same password, plus the header `X-Tenant-Scheme: other-corp`. The token now says company = `other-corp`.
3. Use that token to list assessments. I get the other company's "B Confidential Role".

> **In plain words:** it's like a hotel where the key card machine asks you which room you want, and gives you that key without checking your booking. The guest list doesn't even record which room belongs to whom.

---

### F2 — One company can read and change another company's candidate data · P1 · LIVE

**Impact:** with its own normal login, Company A can:
- download Company B's candidate reports (quotes and summaries),
- **change Company B's candidate ratings**, and
- create reports about Company B's candidates.

This corrupts another company's hiring decisions.

**What goes wrong:**
- The code keeps companies apart with an add-on (`TenantScoped`, [`tenant_scoped.rb`](../api/app/models/concerns/tenant_scoped.rb)). It only works on tables that have a company column.
- Portfolios, portfolio skills and fit/gap reports **don't have that column** ([`schema.rb:85-131`](../api/db/schema.rb#L85-L131)).
- The code loads those records **by ID number alone**, without checking the company. This kind of bug is called an *IDOR (insecure direct object reference)*. It happens here:
  - [`portfolios_controller.rb:82`](../api/app/controllers/api/v1/portfolios_controller.rb#L82)
  - [`:104`](../api/app/controllers/api/v1/portfolios_controller.rb#L104)
  - [`:130`](../api/app/controllers/api/v1/portfolios_controller.rb#L130)
  - [`:156`](../api/app/controllers/api/v1/portfolios_controller.rb#L156)
  - **The rating change:** [`portfolio_skills_controller.rb:51-52`](../api/app/controllers/api/v1/portfolio_skills_controller.rb#L51-L52)

**How I reproduced it** (using Company A's normal token):
1. Company B's *session* returns **404**. Sessions are protected correctly.
2. `GET /portfolios/1/export` returns Company B's `"CONFIDENTIAL tenant-B competency summary"`. **Portfolios are not protected.**
3. `POST /portfolio_skills/1/override` with level 1 returns **201 Created**. Company B's candidate changed from L4 to L1.
4. A fit/gap report for Company B's candidate is created, and now shows "gap −2" because of my change.

> **In plain words:** the building checks your badge at the front door (sessions), but inside, every office opens with just the room number. The records that "belong to" a session were never given their own lock.

---

### F3 — Invite links lead candidates to a 404 page · P1 · LIVE

**Impact:** the candidate clicks the link and gets "Not Found". The interview only works if the assessor notices and fixes the link by hand. That's a manual workaround, which makes this P1.

**What goes wrong:**
- The link is built as `APP_BASE_URL + /interview/<token>` ([`session.rb:28-31`](../api/app/models/session.rb#L28-L31)).
- Every config file defines `APP_BASE_URL` as the **backend** server address.
- But `/interview/...` is a page on the **website** ([`App.tsx:57`](../web/src/App.tsx#L57)). The backend has no such page.

**How I reproduced it:**
1. Create a session. The link is `http://localhost:3001/interview/<token>` (the backend).
2. Open it: **404**.
3. The same token on the website address: 200, it works.

> **In plain words:** the invitation has the right room number but the wrong building address.

---

### F4 — Removing a skill in an edit form doesn't remove it · P1 · LIVE

**Impact:**
- The assessor removes a skill, clicks Save, and sees no error. But the candidate is **still interviewed on that skill**, and it still shows up in the results.
- For vacancies, the role keeps "requiring" a skill the assessor removed, which creates fake gaps in the fit/gap report.

**What goes wrong:**
- The backend uses Rails "nested attributes". These only delete a child record if the request marks it with `_destroy: true` ([`assessment.rb:16-18`](../api/app/models/assessment.rb#L16-L18), [`vacancy.rb:11-13`](../api/app/models/vacancy.rb#L11-L13)).
- The edit forms just drop the skill from the list they send ([`SkillCard.tsx:64`](../web/src/components/assessment/SkillCard.tsx#L64), [`AssessmentEditPage.tsx:80`](../web/src/pages/assessments/AssessmentEditPage.tsx#L80), [`VacancyEditPage.tsx:49`](../web/src/pages/vacancies/VacancyEditPage.tsx#L49)).
- For the backend, "not in the list" means "leave it alone", not "delete it".

**How I reproduced it:**
1. Create an assessment with skills "Keep Me" and "Remove Me".
2. Send exactly what the Edit page sends after removing "Remove Me".
3. The server still has both skills. (The vacancy form uses the same mechanism.)

> **In plain words:** the form says "here are the skills I want", but the server hears "here are the skills to update". Nothing ever says "delete this one".

---

### F5 — AI levels in an unexpected format are saved as L1 · P1 · LIVE

**Impact:**
- If the AI returns a skill level as `"L3"` (text) or returns no level at all, the skill is saved as **L1**, the lowest level.
- The fit/gap report then shows a **gap** that isn't real.
- The portfolio is marked `complete`, so nobody gets a warning.

The frontend's own data types describe levels as `"L1"`–`"L5"` text ([`types/index.ts:93`](../web/src/types/index.ts#L93)), so this format has probably been seen before.

**What goes wrong:** [`generator.rb:161`](../api/app/services/portfolios/generator.rb#L161) and [`:173`](../api/app/services/portfolios/generator.rb#L173) do `skill_data['level'].to_i.clamp(1, 5)`. In Ruby, `"L3".to_i` and `nil.to_i` are both `0`, and clamping `0` into 1–5 gives `1`.

**How I reproduced it:** I ran the portfolio generator with a fake AI response:
- `"L3"` → saved as **1**
- no level → saved as **1**
- `4` → saved as 4
- Portfolio status: `complete`.

> **In plain words:** when the code can't read the grade, it quietly writes "lowest grade" instead of saying "I couldn't read this". In JavaScript it's like `Math.max(1, parseInt("L3") || 0)`.

---

### F6 — Anyone with the invite link can end the interview as "all covered" · P1 · LIVE

**Impact:**
- An interview that **never started**, or stopped after one minute, is saved as `end_reason: all_covered` ("all skills were covered"). That is false.
- A portfolio is then generated from an empty or partial transcript.
- Anyone who sees the link can also use it up.

**What goes wrong:** [`sessions_controller.rb:118-129`](../api/app/controllers/api/v1/sessions_controller.rb#L118-L129) needs no login. A code comment says the coverage check was removed on purpose. It also never checks that the interview actually started.

**How I reproduced it:**
1. Create a session.
2. With no login, call `POST /sessions/<token>/audio_complete`.
3. Answer: "Session ended". Saved: `status=ended`, `end_reason=all_covered`, `started_at=null`, and an empty coverage map.

> **In plain words:** the "finish exam" button marks you as "answered every question", and anyone holding the exam link can press it, even before the exam starts.

---

### F7 — Comparison depends on the AI repeating skill names exactly · P1 · CODE

**Impact:**
- If the AI writes a skill name slightly differently (for example "React / Frontend Development" instead of "React / Frontend Development **Core**"), the comparison shows that skill as **"not assessed"**.
- If the AI leaves a skill out, it silently disappears from the results.

**What goes wrong:**
- When you pick a skill from the list, its ID is thrown away: `skill_id: undefined` ([`SkillPicker.tsx:41`](../web/src/components/assessment/SkillPicker.tsx#L41)).
- The AI prompt then labels those skills as "custom" ([`generator.rb:129`](../api/app/services/portfolios/generator.rb#L129)).
- The results store whatever skill name the AI wrote back ([`generator.rb:156-165`](../api/app/services/portfolios/generator.rb#L156-L165)).
- The comparison can then only match by exact name ([`fit_gap/engine.rb:88-91`](../api/app/services/fit_gap/engine.rb#L88-L91)).

*Next step:* a test with a fake AI response in Task 2 will turn this into a LIVE finding.

> **In plain words:** we throw away each skill's ID card, then try to find people again by asking the AI to spell their full name perfectly.

---

### F8 — "Required" column in the fit/gap table is always empty · P2 · LIVE

**Impact:**
- In the fit/gap table, the **required level never appears**.
- The "a human changed this rating" marker never appears either.

The stored data is correct (the PDF export shows it), so this is P2. But for a "match" row, the assessor can't see the required level anywhere on screen.

**What goes wrong:**
- The backend sends the field as `expected_level` ([`fit_gap/engine.rb:58-66`](../api/app/services/fit_gap/engine.rb#L58-L66)).
- The frontend looks for `required_level` and `is_override` ([`types/index.ts:130-137`](../web/src/types/index.ts#L130-L137), [`ComparisonTable.tsx:50,56`](../web/src/components/fitgap/ComparisonTable.tsx#L50)).
- The PDF export reads `expected_level` ([`pdf_generator.rb:128`](../api/app/services/exports/pdf_generator.rb#L128)). So the frontend is the side that's wrong.

**How I reproduced it:** the fit/gap response contains `"expected_level":3`, and has no `required_level` or `is_override`.

> **In plain words:** the backend labels the box "expected", the frontend looks for a box labelled "required", finds nothing, and shows an empty cell. No error, just a blank.

---

### F9 — Delete says "deleted" but nothing is deleted · P2 · LIVE

**Impact:** the backend reports success when it didn't do anything. There's no delete button in the current website, so only direct API users are affected today.

**What goes wrong:**
- An assessment with sessions is protected from deletion (`restrict_with_error`, [`assessment.rb:7`](../api/app/models/assessment.rb#L7)). So `destroy` returns `false`.
- The controller ignores that result ([`assessments_controller.rb:51-54`](../api/app/controllers/api/v1/assessments_controller.rb#L51-L54)) and answers "deleted" anyway.

**How I reproduced it:** `DELETE /assessments/2` (which has a session) returns 200 "Assessment deleted". A `GET` afterwards returns 200: it still exists.

> **In plain words:** the code calls a function that says "no, I refused", ignores the answer, and tells the user "done".

---

### F10 — The AI decides "confidence", although the spec gives a fixed rule · P2 · CODE

**What the spec says** (PRD-01 §5): confidence follows a fixed rule. For example, "high" means the skill was probed at least 3 times and reached `covered`.

**What the code does:**
- It asks the AI to apply the rule ([`generator.rb:97-100`](../api/app/services/portfolios/generator.rb#L97-L100)) and saves whatever it says ([`:162`](../api/app/services/portfolios/generator.rb#L162)).
- So the saved confidence can contradict the saved coverage data.
- If the AI writes "High" with a capital H, the value fails validation and **the whole portfolio fails**.
- The frontend already lowercases confidence defensively ([`ConfidenceIndicator.tsx:6`](../web/src/components/portfolio/ConfidenceIndicator.tsx#L6)), which suggests this has happened.

It becomes **P1 if it's seen happening**.

> **In plain words:** we ask the AI to do simple arithmetic we could do ourselves, then trust its answer.

---

### F11 — Coverage updates that run at the same time can overwrite each other · P2 · RISK

**Why it matters:** the coverage map decides **when the interview ends** and what confidence each skill gets. If it's unreliable, interviews can end too early or too late.

**What can go wrong:**
- After each thing the candidate says, a background job updates the coverage map ([`audio_websocket_middleware.rb:187`](../api/app/channels/audio_websocket_middleware.rb#L187)). Up to 10 jobs run at once ([`sidekiq.yml:1`](../api/config/sidekiq.yml#L1)).
- Two jobs for the same interview can both read "count = 2", both write "count = 3", and one update is lost ([`coverage_analyzer_worker.rb:39-49`](../api/app/workers/coverage_analyzer_worker.rb#L39-L49)).
- Adding a newly discovered skill has the same problem ([`:53-63`](../api/app/workers/coverage_analyzer_worker.rb#L53-L63)).
- There's also a rule that isn't in the spec: after 4 probes, a skill is automatically marked `covered`, even if the AI said the evidence isn't enough yet ([`:91-101`](../api/app/workers/coverage_analyzer_worker.rb#L91-L101)).

> **In plain words:** two cashiers update the same stock count from the same starting number, and one sale disappears.

---

### F12 — Transcript lines can be silently lost when the page is refreshed · P2 · RISK

**Why it matters:** the transcript is the evidence for the portfolio.

**What can go wrong:**
- Each connection numbers the lines itself, starting from the highest number saved so far ([`audio_websocket_middleware.rb:116`](../api/app/channels/audio_websocket_middleware.rb#L116)).
- After a refresh (the old connection stays alive for 120 seconds) or with a second tab, two connections can use the same line number.
- The database rejects the duplicate, and the code **silently ignores** that error ([`:655-656`](../api/app/channels/audio_websocket_middleware.rb#L655-L656)). The line is lost.

> **In plain words:** two people hand out ticket numbers from separate rolls. Duplicates get thrown in the bin without anyone being told.

---

### F13 — The live-monitor connection doesn't check the user's role · P2 · CODE

[`coverage_websocket_middleware.rb:125-137`](../api/app/channels/coverage_websocket_middleware.rb#L125-L137) checks that the token is valid and belongs to the right company, but **not the user's role**:
- Any valid token for that company can watch any interview live, including a `student`-role (candidate) token (the seed instructions show how to create one).
- Connections that never log in are also left open forever.

### F14 — "What does not count" is never sent to the AI · P2 · CODE

- The spec (PRD-01 §2) says every skill tells the AI `WHAT DOES NOT COUNT`.
- The skill picker copies the skill's description and levels, but **not** its "does not count" part ([`SkillPicker.tsx:40-51`](../web/src/components/assessment/SkillPicker.tsx#L40-L51)).
- So that line never reaches the AI prompt ([`system_prompt_compiler.rb:59`](../api/app/services/assessments/system_prompt_compiler.rb#L59)), and the AI may give credit for experience that shouldn't count.

### F15 — The "what to ask next" hint ignores discovered skills · P2 · CODE

- The spec's priority order is `not_yet > initiated > partial > discovered > covered`. ("Discovered" = a skill the candidate brought up on their own.)
- The code only ranks the configured skills and leaves out the "discovered" step ([`map_injector.rb:104-114`](../api/app/services/coverage/map_injector.rb#L104-L114)).

### F16 — Deployment files would set production up wrong · P2 · CODE

- The web server runs in `production` mode ([`configmap.yaml:11`](../api/k8s/configmap.yaml#L11)), but the background worker is started in `staging` mode ([`deploy-sidekiq.yaml:61`](../api/k8s/deploy-sidekiq.yaml#L61)). There is no `staging` config file.
- No secrets are provided at all: the signing key, database password, AI key and Redis address are all missing. Redis silently falls back to `localhost` inside the container.
- Images are always pulled as `:latest` ([`deployment.yaml:62-63`](../api/k8s/deployment.yaml#L62-L63)), so you can't reproduce or roll back a specific release. This matters for Task 4.

### F17 — Login security gaps · P2 · CODE

- **Dev token fallback:** [`authAtom.ts:10`](../web/src/stores/authAtom.ts#L10) falls back to a developer token (`VITE_DEV_TOKEN`). If that's set when the site is built, every visitor is logged in as that user, and "log out" can't remove it.
- **Company chosen from unchecked data:** the company is picked from the login token **without checking its signature** first, then from the `Referer` header, then from a default company ([`tenant_resolver_middleware.rb:33-51`](../api/app/middlewares/tenant_resolver_middleware.rb#L33-L51), [`organization.rb:13-27`](../api/app/models/organization.rb#L13-L27)).
- **Removed users keep access:** the backend trusts the token without looking up the user ([`authorize_api_request.rb:8`](../api/app/auth/authorize_api_request.rb#L8)), so a deleted or demoted user keeps access for 3 days.
- **Token storage:** the login token is kept in `localStorage`, where any injected script on the page can read it.
- **Public "secret":** the interview's anti-cheating code is written in the public source code ([`audio_websocket_middleware.rb:16`](../api/app/channels/audio_websocket_middleware.rb#L16)).

### F18–F20 — Minor (P3)

- **F18:** the frontend and backend disagree on types.
  - `ai_level` is a number in the backend but described as text in the frontend. The fit/gap page shows a bare "4" instead of "L4" ([`FitGapReportPage.tsx:196`](../web/src/pages/fitgap/FitGapReportPage.tsx#L196)).
  - `skill_id` is text like `"SK-ENG-001"` but typed as a number ([`types/index.ts:19`](../web/src/types/index.ts#L19)).
- **F19:** a leftover sign-up page ([`SignupPage.tsx`](../web/src/pages/auth/SignupPage.tsx)) calls an endpoint that doesn't exist ([`auth.ts:16`](../web/src/services/auth.ts#L16)), and lets the user **choose to be "admin"**. If someone adds that endpoint later, anyone can make themselves admin. It should be deleted.
- **F20:** small UI issues.
  - You can't change the interview language after creating an assessment.
  - The "Save & Create Session →" button doesn't create a session ([`AssessmentNewPage.tsx:251`](../web/src/pages/assessments/AssessmentNewPage.tsx#L251)).
  - The wrong text appears under "Culture & Competency Fit" ([`FitGapReportPage.tsx:173`](../web/src/pages/fitgap/FitGapReportPage.tsx#L173)).
  - A failed vacancy save shows no error ([`VacancyEditPage.tsx:42-55`](../web/src/pages/vacancies/VacancyEditPage.tsx#L42-L55)).

---

## Missing or unclear specs

These aren't bugs in the code. **Nobody defined them**, so nobody can say what "correct" is. Each one needs a decision before it can be built or tested.

| # | What's missing | Why it matters |
|---|----------------|----------------|
| M1 | **No automated tests and no CI** | Nothing above would have been caught, and nothing stops it coming back. This is the biggest gap for this engagement, and Task 2 builds it. |
| M2 | **No rule for which users belong to which company**, and no way to create users except the Rails console | This is the root cause of F1. |
| M3 | **The spec and the code disagree on how an interview ends** | The specs say the AI closes on its own and invites the candidate's questions. The code forbids closing without a system signal and forbids asking questions ([`system_prompt_compiler.rb:108-129`](../api/app/services/assessments/system_prompt_compiler.rb#L108-L129)). One of them is out of date, and nobody can say which. |
| M4 | **Rules that exist only in the code**: auto-cover after 4 probes, pacing levels, max 10 discovered skills | These rules decide when interviews end, but they aren't written down anywhere to review or test against. |
| M5 | **No versioning when an assessment is edited after interviews happened** | Editing skills changes what past candidates are compared against. |
| M6 | **No website address in the config** | Only the backend address exists, which leads directly to F3. |
| M7 | **No rule for keeping hiring evidence** | Deleting a vacancy also deletes every fit/gap report made against it ([`vacancy.rb:7`](../api/app/models/vacancy.rb#L7)). |
| M8 | **The public repo names the original company** | The imported code mentions it **50 times in 26 files**, plus internal cloud project, server and domain names (in `api/k8s/*`, `web/vercel.json`, READMEs and comments). That's an information leak, and it goes against the brief's "don't name the company" rule. **Fixed:** every identifier was replaced across **all of the history** (not only the latest commit), so no old commit still contains one. |

---

## Patterns: why these bugs keep happening

1. **Keeping companies apart is a habit, not a built-in rule.** Safety depends on each developer remembering an add-on and a special lookup method. Records without a company column slip through (F2). The login has no idea of company membership (F1, M2), and the live-monitor connection doesn't check roles (F13).
   *Fix the whole class:* always load records through their company-owned parent, and add a "Company A can't see Company B" test for every endpoint.
2. **No checks at the borders between systems.**
   - Frontend ↔ backend: data shapes are agreed by convention only (F8, F18).
   - App ↔ AI: the AI's free-text answers go straight into hiring data (F5, F7, F10).

   The AI border is the more dangerous one.
   *Fix:* tests that check the backend's response shape, and strict checks on AI output that **fail loudly** instead of silently guessing.
3. **Success is shown without checking the result.** A save that doesn't save (F4), a delete that doesn't delete (F9), and "all covered" when nothing was covered (F6). The screen looks fine while the data is wrong, which is exactly what the brief's quality bar warns about.
4. **Timing bugs fixed one at a time, without tests.** Code comments mention earlier race-condition fixes ("H1", "H4", "H5", "C2"), but the same patterns are still there (F11, F12), and no test locks the behaviour in.
5. **The specs fell behind the code.** The code changed (M3, M4), but the specs were never updated, so there's no reliable source of truth. That's the "ghost spec" problem the brief describes.

---

## Ship or don't ship

**Don't ship.** Each of these blocks the release on its own:
- **F1 and F2:** customers' data isn't separated, and one customer can change another's hiring results.
- **F3:** candidates can't open their interview link.
- **F4, F5, F6:** hiring results can be silently wrong while the screen says everything is fine.

**What I would require before any client sees it:**
1. **Company separation.** Users belong to a company, and every record is loaded through its company. Tests prove Company A gets **404** on Company B's data, for both reading and changing.
2. **Invite links.** They use the website address, with a test that the link opens the interview page.
3. **Silent data errors.**
   - Edit forms send `_destroy` for removed skills.
   - AI output is checked strictly, so a bad level **fails** instead of becoming L1.
   - `audio_complete` checks who is calling and whether the interview really covered everything.
4. **CI on every change**, including:
   - a check that frontend and backend agree on data shapes (this would have caught F8), and
   - tests with fake AI responses for the portfolio generator (F5, F7).
5. **Decisions on M3** (how interviews end) **and M8** (cleaning the company name out of the repo).

F8–F17 can follow in the next round, each with a test so they can't come back. F18–F20 go to the backlog.

---

## Note: how this repo differs from the original source

To follow the brief's confidentiality rule (M8), the imported code was cleaned **in every commit, including "Initial import of the platform"**. So the initial import is *not* byte-for-byte the original source. The only differences are 50 identifier lines in 26 files, and no behaviour changed except the database names:

| What was replaced | Replaced with |
|---|---|
| The company name in code comments ("extracted from …-api") | "the upstream platform API" |
| Database names (`…_development`, `…_test`) | `platform_development`, `platform_test` |
| Production domain in the k8s ingress/config and the web security policy | `ai-interview-api.example.com` |
| Cloud project and image registry path | `registry.example.com/ai-interview/ai-interview-api` |
| Internal node-pool names | `dedicated-t2d-pool`, `dedicated-compute-class` |
| Product wiki link in the README | "the product wiki" |
| Brand name in the app header and CSS comments | "AI Interview", "Brand teal/yellow" |

This was checked by searching every commit (zero matches), and by confirming that every line that changed contained one of these identifiers.

---

## Changes since the first-pass audit

The first version of this file covered only part of the code. Here's where each first-pass finding went:

| First pass | Now | Change |
|------------|-----|--------|
| F1: cross-company access to portfolios, ratings and fit/gap | **F2** | Now **reproduced live**, including *changing* another company's rating |
| F2: no tests and no CI | **M1** | Moved to "missing specs", since it's a process gap, not a code bug |
| F3: fit/gap "Required" column blank | **F8** | Now reproduced live. The PDF export confirms the frontend is the wrong side. |
| F4: "what to ask next" ignores discovered skills | **F15** | No change |
| F5: `ai_level` type mismatch (number vs `"L3"`) | **F18**, and **F5** | Split in two. The display issue stays P3 (F18). The bigger risk it pointed to, that `"L3"` is saved as L1, is now the separate **P1 F5**, reproduced live. |
| "What worries me" notes (unverified token, race conditions, trusting AI output) | **F17, F11, F5/F10** | Each became its own finding with evidence |
| — | **F1, F3, F4, F6, F7, F9, F12–F14, F16, F19, F20, M2–M8** | New in the full sweep |

---

## How I verified

- **Setup:** backend (Rails + Sidekiq), PostgreSQL 18 and Redis 8, all run natively on my machine, plus the website (Vite). The AI key was a dummy, so real AI calls fail on purpose. I tested the AI-dependent parts with fake AI responses instead.
- **Test data:** two companies. Company A is the default one. Company B has one confidential candidate report: level L4 in "Negotiation", with a quote.
- **How:** I called the running API directly with Company A's normal login. Two exceptions: F1, where I got a Company B login, and F6, which needs no login at all. For F5, I ran the portfolio generator from the command line with a fake AI response.
