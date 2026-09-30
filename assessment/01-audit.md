# 01 — Platform Audit

**What I checked:** all the code in `api/` (backend) and `web/` (frontend), the deployment files, and the two product specs from the product wiki ("First Principles: AI Interview Behavior" and "Real Simulation: End-to-End Interview").

**How I checked:**
1. I read the code and compared it to the specs.
2. I ran the whole app on my machine and **reproduced the main problems for real**. Each finding below says how to reproduce it.

**Status:** F22, F1, F2, F23, F3, F24, F4, F5, F25 and F6 are `fixed`. Everything else is `open`. I update the Status column as fixes land in Task 3.

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

**Do not ship this to a client.** First, the most basic problem:

0. **As configured, the backend can't even start in production** (F22, P0). Development never loads the code the way production does, so nobody noticed. The new CI caught it on its very first run.

Beyond that, there are three groups of problems:

1. **Customers are not separated from each other.**
   - Any assessor can log into *another company's* workspace just by adding one header to the login request (F1).
   - Even without that trick, any assessor can read *and change* another company's candidate ratings by guessing an ID number (F2).
   - I proved both on the running app: from Company A's account, I downloaded Company B's confidential candidate report, then changed that candidate's rating from L4 to L1.
   - A normal Company A login also works **inside Company B**, if it's sent in a slightly different form with Company B's name in a header (F23). Found while fixing F2.
2. **Candidates can't start their interview.**
   - The invite link points to the backend server instead of the website, so the candidate sees a "404 Not Found" page (F3).
   - The internet check before the interview demands about 15 times the upload speed the interview uses, and measures it against free servers abroad. A candidate with a good connection can be blocked, with no way around it (F24).
3. **Hiring results can be silently wrong, while the screen says everything worked.**
   - Removing a skill in the edit form doesn't actually remove it (F4).
   - If the AI answers in a format the code doesn't expect, the skill is saved as the lowest level, L1 (F5).
   - An interview that ends early, because the AI says goodbye too soon or because someone holding the link ends it, is recorded as "all skills covered" without any check (F6).

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
- **TEST**: reproduced by an automated request through the whole backend (middleware, login check, database), the same path a real request takes.

---

## Ranked list

| # | Problem | Sev | Type | Evidence | Status |
|---|---------|-----|------|----------|--------|
| F22 | The backend cannot start in its production configuration | **P0** | built-wrong | LIVE + CI | **fixed** |
| F1 | Login lets any user pick any company's workspace | **P1** | built-wrong | LIVE | **fixed** |
| F2 | One company can read **and change** another company's candidate data | **P1** | built-wrong | LIVE | **fixed** |
| F23 | A valid login from one company works inside **any other company** (found while fixing F2) | **P1** | built-wrong | TEST | **fixed** |
| F3 | Invite links lead candidates to a 404 page | **P1** | built-wrong | LIVE | **fixed** |
| F4 | Removing a skill in an edit form doesn't remove it | **P1** | built-wrong | LIVE | **fixed** |
| F5 | AI levels in an unexpected format are saved as **L1** | **P1** | built-wrong | LIVE | **fixed** |
| F6 | Interviews are recorded as "all skills covered" without checking, including when the AI says goodbye early | **P1** | built-wrong | LIVE | **fixed** |
| F7 | Candidate-vs-vacancy comparison depends on the AI repeating skill names exactly | **P1** | built-wrong | CODE | open |
| F24 | The pre-interview internet check blocks candidates whose connection is good enough (found in manual testing) | **P1** | built-wrong | LIVE | **fixed** |
| F25 | A dropped connection tells the candidate "Interview Complete", and the interview stays "Live" forever (found in manual testing) | **P1** | built-wrong | LIVE | **fixed** |
| F26 | The AI sometimes never opens the interview; the candidate is stuck in silence with a muted mic (found in manual testing) | **P1** | built-wrong | LIVE | open |
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
| F21 | Four pages silently swallow load errors, so a missing or forbidden record shows as an empty form (source ticket #2, closed "not planned", still present) | P2 | built-wrong | LIVE (API) + CODE | open |

---

## Findings in detail

### F22 — The backend cannot start in its production configuration · P0 · LIVE + CI

**Impact:** with the production settings from the deployment files (`RAILS_ENV=production`), the API **crashes at boot**. Nothing works at all: no login, no interviews, no results. There is no workaround short of changing the code. This finding was added after the first two passes of the audit, which is why it has the highest number.

**What goes wrong** (two separate causes, and either one alone is enough to crash):
1. [`production.rb:34`](../api/config/environments/production.rb#L34) configures Active Job (`config.active_job.queue_adapter = :sidekiq`), but the app never loads the Active Job framework: [`application.rb`](../api/config/application.rb#L5-L8) only loads Model, Record and Controller. Result: `undefined method 'active_job'`. The app uses Sidekiq workers directly, so the line configures something that isn't there.
2. Production loads every file at boot. Rails expects each file name to match the class inside it, but `app/channels/audio_websocket_middleware.rb` defines `AudioWebSocketMiddleware` (capital **S**; the file name implies `AudioWebsocketMiddleware`), and the same goes for the coverage middleware. Development loads these files a different way ([`websocket.rb`](../api/config/initializers/websocket.rb)), so it never notices.

**Why nobody noticed:** development loads code lazily and never runs `production.rb`. So the only environment where this code runs this way is production itself.

**How I found and reproduced it:**
- `bundle exec rails zeitwerk:check`, Rails' own loader check, fails with "expected file … to define constant AudioWebsocketMiddleware".
- `RAILS_ENV=production rails runner 'puts :ok'` crashes with `undefined method 'active_job'`.
- **The CI caught it by itself on its first run:** the check "Net: API boots in production mode" went red ([run 36547094896](https://github.com/yond44/yonda-quality-net/actions/runs/36547094896)).

> **In plain words:** the car starts fine in the garage (development), but the "drive on the road" setting (production) points at an engine part that was never installed.

---

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

**Status: fixed.**
- **Test first:** [`login_tenant_isolation_spec.rb`](../api/spec/requests/auth/login_tenant_isolation_spec.rb) was committed while all 4 examples failed. The fix commit then made all 4 pass, with the checks unchanged.
- **The fix:**
  - Users now belong to one organization ([`AddOrganizationToUsers`](../api/db/migrate/20260929000000_add_organization_to_users.rb), [`user.rb`](../api/app/models/user.rb)).
  - Login issues a token **only** for that organization. The `X-Tenant-Scheme` header is ignored, and the "first row" fallback is gone ([`authentication_controller.rb`](../api/app/controllers/api/v1/authentication_controller.rb)).
  - A user with no organization can't log in.
- **Assumption (the spec never defined this, see M2):** one user belongs to exactly one company. If users ever need several companies, this becomes a membership table, and the header can then choose *among the user's own* companies.

**What remains after the fix (disclosed, not hidden):**
- **Existing users must be assigned.** Every user who exists before this migration has no organization and **can't log in** until an operator sets one. I didn't auto-assign, because there's no safe way to guess. *Deploy step:* assign every user to their organization before releasing.
- **Old tokens still work.** Tokens issued before the fix are still valid for up to 3 days, because the backend trusts token claims without looking up the user (F17). A token someone already obtained for another company keeps working until it expires. *Deploy step:* rotate `SECRET_KEY_BASE` on release to invalidate all old tokens.
- **Scope of this fix.** It closes *how the wrong token gets issued*. It doesn't close F2: portfolios are still reachable by ID with a *correct* token.

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

**Status: fixed.**
- **Test first:** [`f2_cross_tenant_portfolio_spec.rb`](../api/spec/requests/f2_cross_tenant_portfolio_spec.rb) was committed while 4 of its 5 examples failed. The fix commit made all 5 pass, with the checks unchanged. The 5th example is a control: company B still sees its own portfolio, so the fix can't be a blanket 404.
- **The fix:** portfolios and portfolio skills now have a `for_tenant` lookup that finds the company **through the session** they belong to ([`portfolio.rb`](../api/app/models/portfolio.rb), [`portfolio_skill.rb`](../api/app/models/portfolio_skill.rb)). Every lookup by ID in the two controllers goes through it. Fit/gap reports are only ever reached through an already-checked portfolio. A record from another company now answers **404**, as if it doesn't exist, and nothing is read or changed.
- **Why not add a company column to these tables?** That would make the automatic `TenantScoped` filter cover them too, but it needs a data backfill, and it would change how the background jobs and the live-interview WebSocket (which the net can't test, see `02-quality-system.md`) create these records. The scoped lookup closes the hole with a small, tested change. The column is the better long-term design, and it's recorded as follow-up work.

**What remains after the fix (disclosed, not hidden):**
- **The protection is explicit, not automatic.** A new endpoint that loads a portfolio with a bare `Portfolio.find` would reopen this hole. The F2 spec only covers the endpoints that exist today.

---

### F23 — A valid login from one company works inside any other company · P1 · TEST

*Found while fixing F2. The first audit filed "company chosen from unchecked data" under F17 as a P2 weakness. Trying to exploit it showed it's a full cross-company breach, so it's re-ranked here as its own P1.*

**Impact:** any logged-in user of Company A can read **and change everything** in Company B: assessments, interviews, vacancies and candidate reports. They only need their own normal login. This defeats the F1 and F2 fixes, because it doesn't need a wrong token or a guessed ID.

**What goes wrong:** two parts of the backend read the same login header in two different ways, and nobody checks that they agree.
- **Which company is this request for?** The tenant middleware only reads the token if the header starts with `Bearer `. Otherwise it takes the company from the `X-Tenant-Scheme` header, or from the `Referer` ([`tenant_resolver_middleware.rb:33-51`](../api/app/middlewares/tenant_resolver_middleware.rb#L33-L51)).
- **Is this user logged in?** The login check accepts the token in **any** form: it just takes the last word of the header ([`authorize_api_request.rb:65-69`](../api/app/auth/authorize_api_request.rb#L65-L69)).
- **The missing check:** nothing compares the company written inside the (verified) token with the company the request is working in.

**How I reproduced it** (an automated request through the whole backend, with Company A's valid token):
1. `Authorization: Bearer <A's token>` plus `X-Tenant-Scheme: company-b` shows only Company A's data. The normal form is safe.
2. `Authorization: Token <A's token>` plus `X-Tenant-Scheme: company-b` returns **Company B's assessments**.
3. Just `Authorization: <A's token>` (no prefix), with a `Referer` on Company B's address, does the same.
4. A `PUT` in the same form **renamed Company B's assessment**: 200 OK.

> **In plain words:** the guard at the door reads your badge only if you hold it face-up. If you hold it upside down, the guard asks "which floor?" and believes your answer, while the turnstile still lets the badge through because it's a real badge.

**Status: fixed.**
- **Test first:** [`f23_token_company_mismatch_spec.rb`](../api/spec/requests/f23_token_company_mismatch_spec.rb) was committed and pushed while 3 of its 4 examples failed, and CI flagged it by itself. The fix commit made all 4 pass, with the checks unchanged. The 4th example is a control: the normal `Bearer` login still works.
- **The fix:** one check at the single place every logged-in request passes through ([`application_controller.rb`](../api/app/controllers/application_controller.rb), `authenticate_with_roles!`). After the token's signature is verified, the company written inside it **must equal** the company the request is working in. Otherwise the request gets **401**. This closes every variant at once (any header form, the tenant header, the `Referer`), instead of patching each way in.
- **Why there, and not in the middleware:** the middleware runs before the token is verified, so it can't trust what it reads. The login check is the first place that knows who the user really is.

**What remains after the fix (disclosed, not hidden):**
- The middleware still **guesses** the company from unverified input first. It's now harmless for logged-in requests, but the candidate endpoints (no login) still rely on it, and the other F17 items (dev-token fallback, users removed but still holding tokens) are still open.

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

**Status: fixed.**
- **Test first:** [`f3_invite_url_spec.rb`](../api/spec/models/f3_invite_url_spec.rb) was committed while it failed. The fix made it pass, with the checks unchanged. Its second check reads the web app's real route list (`web/src/App.tsx`), so renaming the page on **either** side turns CI red again.
- **The fix:**
  - Invite links now use a new setting, **`WEB_BASE_URL`**, the web app's address ([`session.rb`](../api/app/models/session.rb)).
  - `APP_BASE_URL` was only ever used for invite links, so it's replaced everywhere: the config sample, the README, the Kubernetes config and CI.
  - **Production refuses to start without `WEB_BASE_URL`** ([`production.rb`](../api/config/environments/production.rb)). Otherwise every invite would quietly point at `localhost`, the same silent failure in a new form. The CI production-boot check now sets it.
- **Why a new setting, not a new value for `APP_BASE_URL`?** Its documented meaning was "the backend's address". Changing what an existing setting means is how F3 happened in the first place.

**What remains after the fix (disclosed, not hidden):**
- **Deploy step:** set `WEB_BASE_URL` to the website's public address. Links already sent to candidates before the fix still point at the backend. They must be re-sent (or the backend must redirect `/interview/*` to the website).

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

**Status: fixed.**
- **Test first:** [`f4_removed_skills_spec.rb`](../api/spec/requests/f4_removed_skills_spec.rb) sends exactly what the edit pages send. Its 2 original checks failed and now pass, unchanged. The fix commit adds 2 **controls** that pass with and without the fix: an edit **without** a skills list keeps every skill, and a rejected save deletes nothing.
- **The fix:** the backend now treats the list the form sends as the **complete** list. Any existing skill left out of it is deleted, in the same database transaction as the rest of the save ([`application_controller.rb`](../api/app/controllers/application_controller.rb), used by the assessment and vacancy edit endpoints). The website needed no change.
- **Why the backend and not the website:** "send the list I want" is the natural contract, and the backend was the side misreading it. Fixing it there protects every client, not just this page.

**What remains after the fix (disclosed, not hidden):**
- **Fit/gap reports generated before a vacancy's skills were edited are cached**, and keep showing the old requirements until someone regenerates them. The rating-override feature already regenerates reports when its input changes. Doing the same for vacancy edits is a small follow-up.
- **Editing an assessment after interviews happened** still changes what earlier candidates are compared against. That's M5 (no versioning), a product decision.

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

**Status: fixed.**
- **Tests:** [`f5_level_parsing_spec.rb`](../api/spec/services/f5_level_parsing_spec.rb). Its original checks (`"L3"` is read as 3; a missing level fails loudly and stores no L1) failed and now pass, unchanged. A new check was pushed on its own first, and failed: **a regeneration that fails keeps the previous good skills**. The old code deleted them before saving the new ones. The control (a plain `4` is still read as 4) passes throughout.
- **The fix** ([`generator.rb`](../api/app/services/portfolios/generator.rb)):
  - The level is read strictly. `3`, `"3"` and `"L3"` are accepted. Anything else (missing, `0`, `7`, `3.5`, `"high"`) stops the generation with a message naming the skill, instead of becoming L1 or being silently capped at L5.
  - Every skill in the answer is checked **before** anything is saved. The old skills are then replaced in **one transaction**, so a bad answer never leaves a half-saved portfolio.
- **What the user sees:** the background job already retries up to 3 times, and the AI often answers correctly on a retry. If every retry fails, the portfolio shows **failed** with the reason, and the recruiter can press **Regenerate**. A visible failure replaces a wrong grade nobody would notice.

**What remains after the fix (disclosed, not hidden):**
- The **confidence** value is still whatever the AI says (F10), and a value outside high/medium/low still fails the save. It fails loudly and cleanly now, but it's still a failure a stricter prompt could avoid.

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

**Also reproduced in a normal interview, with nobody calling anything by hand** (manual test, 2026-09-30, session 7):
1. Mid-interview, the AI closed on its own: *"I think I've got a clear picture, thank you for your time. You'll hear back from the team soon."* Its instructions forbid exactly this without a wrap-up signal.
2. The server matched a goodbye phrase and **assumed every skill was covered**: `AI closed without system signal — forcing coverage_pending` ([`audio_websocket_middleware.rb:250-254`](../api/app/channels/audio_websocket_middleware.rb#L250-L254), phrases at [`:708-725`](../api/app/channels/audio_websocket_middleware.rb#L708-L725)).
3. The candidate's browser called `audio_complete` automatically, and the session was saved as **`all_covered`**. A portfolio generation was queued.
4. The database still showed the only skill as **`not_yet`, probed 0 times**.

*Caveat:* coverage never moved partly because the free AI key was rate-limited, so every background coverage update failed (see "How I verified"). The finding doesn't depend on it: the server wrote `all_covered` without looking at coverage at all.

So this isn't only "someone calls the endpoint". It happens in the main flow whenever the AI says goodbye early, which is why it stays **P1**.

**Status: fixed.**
- **Tests:** [`f6_audio_complete_spec.rb`](../api/spec/requests/f6_audio_complete_spec.rb). Its 2 checks (a never-started interview isn't ended; an interview with an uncovered skill isn't `all_covered`) failed and now pass, unchanged. The control (a fully covered interview still auto-ends as `all_covered`, with one portfolio job) passes throughout.
- **The fix:**
  - `all_covered` is now **checked where every ending is recorded** ([`end_handler.rb`](../api/app/services/sessions/end_handler.rb)), with the same rule the live interview uses to decide coverage ([`map_injector.rb:48`](../api/app/services/coverage/map_injector.rb#L48)). If it isn't true, the ending is recorded as a new, honest reason: **`partial_coverage`** ([migration](../api/db/migrate/20260930000000_add_partial_coverage_end_reason.rb), [`session.rb`](../api/app/models/session.rb)). This covers every path: the endpoint, the AI's early goodbye, and the server's own timeout.
  - `audio_complete` **refuses an interview that never started** (409), and changes nothing ([`sessions_controller.rb`](../api/app/controllers/api/v1/sessions_controller.rb)).
  - The interview still **always ends** when `audio_complete` is called for a running interview. An earlier code comment says a coverage check there used to stall auto-end; now only the recorded reason changes, never whether it ends.

**What remains after the fix (disclosed, not hidden):**
- **The AI can still end an interview early** by saying a goodbye phrase. It's now recorded honestly as `partial_coverage`, but the interview is still cut short. Changing how goodbyes are detected means changing the live WebSocket code, which the net can't test.
- **Someone holding the link can still end a running interview early.** It's recorded as `partial_coverage` too.
- **A portfolio is still generated** for a `partial_coverage` interview. The recruiter now sees the honest reason next to it.

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

### F24 — The pre-interview internet check blocks candidates whose connection is good enough · P1 · LIVE

*Found during manual testing of the candidate flow, after the F3 fix made the invite link work.*

**Impact:** before the interview starts, the candidate's page checks their browser, internet, microphone and speakers. The **Start** button stays disabled until every check passes ([`HardwareCheck.tsx:284`](../web/src/components/HardwareCheck.tsx#L284)). A candidate whose connection easily carries the interview can be **blocked from starting it**, and nothing on the page lets them continue. The result depends on free third-party servers in another country, not on whether the candidate can actually do the interview.

**Why P1, not P0 or P2:** most candidates pass, and a blocked candidate can get through by switching to a network with faster upload (a manual workaround), so it's not P0. It's not P2, because the pass/fail decision is based on the wrong measurement and on invented fallback numbers, so the result is wrong underneath.

**What goes wrong:**
- **The limits are far above what the interview uses.** The check requires download ≥ 8 Mbps and upload ≥ 4 Mbps ([`internetSpeedTest.ts:19-23`](../web/src/utils/internetSpeedTest.ts#L19-L23)). The interview only sends the candidate's **voice**: 16 kHz, 16-bit mono audio, about **0.26 Mbps** ([`useAudioCapture.ts:22`](../web/src/hooks/useAudioCapture.ts#L22), sent as raw binary by [`useAudioWebSocket.ts:137`](../web/src/hooks/useAudioWebSocket.ts#L137)). It receives the AI's voice at 24 kHz, about **0.4 Mbps** ([`useAudioPlayback.ts:3`](../web/src/hooks/useAudioPlayback.ts#L3)). No video is sent, and the camera is off by default ([`HardwareCheck.tsx:35`](../web/src/components/HardwareCheck.tsx#L35)). So the check demands about **15 times** the upload and **20 times** the download the interview needs.
- **Upload is measured against the wrong servers.** It sends 0.5 MB to public echo services (`httpbin.org`, `postman-echo.com`), which send the data back. The timer also counts their processing and reply ([`internetSpeedTest.ts:90-100`](../web/src/utils/internetSpeedTest.ts#L90-L100)).
- **The measurements compete with each other.** Download, upload and ping all run at the same time on the same connection ([`internetSpeedTest.ts:133-137`](../web/src/utils/internetSpeedTest.ts#L133-L137)).
- **The right tool exists but isn't used.** The backend has its own endpoint for this (`POST /api/v1/speed_test`, [`routes.rb:14-17`](../api/config/routes.rb#L14-L17)), but the setting that points the check at it (`VITE_SPEED_TEST_UPLOAD_URL`) is empty in `.env.example`.
- **Invented numbers when a measurement fails.**
  - If every upload server fails, the code returns a made-up 0.5 MB/s, which is **exactly 4 Mbps**, so the check **passes** ([`internetSpeedTest.ts:105`](../web/src/utils/internetSpeedTest.ts#L105)).
  - If the download fails, it guesses a speed from how long a tiny icon took to load ([`:74-82`](../web/src/utils/internetSpeedTest.ts#L74-L82)).
  - A server that quickly answers with an error page is counted as a fast upload, because `fetch` doesn't treat HTTP errors as failures.

**How I reproduced it** (on the running app, as the candidate):
1. Open a working invite link. The pre-interview check runs.
2. The result: **download 129.03 Mbps, upload 2.96 Mbps, ping 22 ms, "Internet: Failed"**. The Start button stays disabled.
3. 2.96 Mbps is about **11 times** the upload the interview needs, but it's below the 4 Mbps limit.
4. **Local workaround:** with `VITE_SPEED_TEST_UPLOAD_URL` pointed at the backend's own `/api/v1/speed_test`, the upload is measured on the path the interview audio really takes.

> **In plain words:** it's like refusing to let someone make a phone call unless their line could stream 4K video, and measuring the line by mailing a parcel to a warehouse abroad and waiting for it to come back.

**Status: fixed.**
- **Test first:** [`internetSpeedTest.test.ts`](../web/src/utils/internetSpeedTest.test.ts), the web app's first automated test (Vitest, now run by CI). It runs the **real** check on a simulated network, where every request takes the time the given speed and ping would need. It was committed while 5 of its 6 examples failed. The fix made all 6 pass, with the checks unchanged. The 6th example is a control: a 0.2 Mbps upload must still **fail**, so the fix can't just wave everyone through.
- **The fix** ([`internetSpeedTest.ts`](../web/src/utils/internetSpeedTest.ts), [`HardwareCheck.tsx`](../web/src/components/HardwareCheck.tsx)):
  - **Limits from the audio format:** download ≥ 1.5 Mbps and upload ≥ 1 Mbps, about 4 times what the voice interview uses. Ping stays at ≤ 300 ms. The derivation is written next to the numbers.
  - **Upload and ping are measured against our own backend** (`/api/v1/speed_test` and `/api/v1/health`), the path the interview audio really takes.
  - **One measurement at a time**, so they don't compete.
  - **No invented numbers.** A failed measurement or an HTTP error counts as "couldn't measure". The check then fails, and the page says *"We couldn't measure your connection"* with the Retry button, instead of showing made-up speeds.
- **Assumption (M10):** the limits are my derivation from the code, not a product decision. If the product later adds video, they must go up.

**What remains after the fix (disclosed, not hidden):**
- **Download is still timed on public CDN files**, because the backend has no download endpoint. With a 1.5 Mbps limit a CDN almost never decides the result, but a candidate whose network blocks those CDNs would see "couldn't measure".
- **Upload is measured to our own backend.** If the backend is down, the check says "couldn't measure", which is correct: the interview couldn't run either.

---

### F25 — A dropped connection is shown as "Interview Complete", and the interview stays "Live" forever · P1 · LIVE

*Found during manual testing of the candidate flow.*

**Impact:**
- **The candidate is told the interview succeeded when it failed.** After a dropped connection, the page says *"Interview Complete. The interview has been recorded. The hiring team will review your results."* Nothing was recorded. The candidate leaves, and never knows they should reopen the link.
- **The recruiter sees the interview as "Live" forever.** The backend is never told the interview was abandoned, so it stays `active`: no end, no portfolio, no result. Nothing ever cleans it up.
- **Any error loading the interview page also shows "Interview Complete"**, for example a server restart, a network error or a rate limit. The candidate can't tell "done" from "broken".

Connections drop in normal use: a candidate's Wi-Fi, a server restart during a deploy, an outage at the AI provider. So this is the main flow, not an edge case.

**What goes wrong:**
- **The reconnect loop gives up with "complete".** The page retries after 1, 2 and 4 seconds, then reports the interview as complete ([`useAudioWebSocket.ts:119-130`](../web/src/hooks/useAudioWebSocket.ts#L119-L130)).
- **Load errors are shown as "complete".** If the interview info can't be loaded, the page switches to the "Interview Complete" screen ([`InterviewPage.tsx:51`](../web/src/pages/interview/InterviewPage.tsx#L51)).
- **Nothing ends an abandoned interview.** The time-limit check only runs while the live connection is open ([`audio_websocket_middleware.rb`](../api/app/channels/audio_websocket_middleware.rb), `check_time_ceiling`). Once the candidate is gone, the session stays `active` with no end.

**How it was reproduced** (manual test on the running app):
1. Start an interview from an invite link.
2. The live connection fails. Locally this was triggered by the API process crashing when it connected to the AI (a Windows-only build problem with the WebSocket library, not a product bug). In production the same path is taken by any dropped connection.
3. The page shows "reconnecting" for about 7 seconds, then **"Interview Complete"**.
4. The recruiter's live monitor still shows the interview as **Live**, with coverage "Not Yet" and no transcript. In the database the session is still `active`, hours later.
5. Reopening the link while the API was down also showed **"Interview Complete"**.

> **In plain words:** when the phone line drops, the app tells the caller "thanks, your call has been recorded" and hangs up, while the office's switchboard shows the call as still in progress, forever.

**Status: fixed.**
- **Tests first,** pushed without a fix, and each failed on the bug. Each has a control that passes throughout.
  - [`useAudioWebSocket.test.ts`](../web/src/hooks/useAudioWebSocket.test.ts): the candidate is never told "complete" after a lost connection. The control: a real end from the server still shows "complete".
  - [`InterviewPage.test.tsx`](../web/src/pages/interview/InterviewPage.test.tsx): a page that can't load isn't shown as "Interview Complete". The control: an ended interview still is.
  - [`f25_abandoned_session_spec.rb`](../api/spec/requests/f25_abandoned_session_spec.rb): an interview still `active` long after its time limit isn't reported as live, to the recruiter or on the candidate's link. The control: an interview within its time limit stays live.
- **The fix, web** ([`useAudioWebSocket.ts`](../web/src/hooks/useAudioWebSocket.ts), [`InterviewPage.tsx`](../web/src/pages/interview/InterviewPage.tsx)):
  - When reconnecting fails, the page says **"Connection lost. Your interview has not ended"**, with a Reconnect button. The interview is still resumable, so reconnecting really continues it.
  - When the page can't load the interview, it says **"We couldn't load your interview"** with Try again, or **"This interview link isn't valid"** when the server doesn't know the link.
- **The fix, backend** ([`session.rb`](../api/app/models/session.rb), [`end_handler.rb`](../api/app/services/sessions/end_handler.rb), [`sessions_controller.rb`](../api/app/controllers/api/v1/sessions_controller.rb), [`assessments_controller.rb`](../api/app/controllers/api/v1/assessments_controller.rb)):
  - An interview still `active` **more than 15 minutes past its time limit** is ended with reason `error` whenever it's read: the recruiter's session view and list, the assessment list, and the candidate's link. The website already highlights `error` endings for the recruiter.
  - Its end time is its **last activity** (the last transcript line, or the start), so its recorded duration isn't inflated to hours.
  - Within the time limit plus 15 minutes nothing changes, so a candidate whose connection dropped can reopen the link and continue.

**What remains after the fix (disclosed, not hidden):**
- **An abandoned interview is ended when someone next looks at it**, not at the moment its time runs out. A scheduled cleanup job would be better, but the project has no job scheduler.
- **During the resumable window, the recruiter's live monitor still shows "Live"**, because the backend can't tell "reconnecting" from "gone" without changing the live WebSocket code, which the net can't test.
- **A non-recoverable error sent by the server** during the interview (for example "Assessment configuration is incomplete") is still shown to the candidate as "Interview Complete" ([`useAudioWebSocket.ts:106`](../web/src/hooks/useAudioWebSocket.ts#L106)). It's the same class of bug, on a different path with no test yet.
- **The ended interview still gets a portfolio** generated from whatever transcript exists, as every `error` ending already did. The recruiter sees the `error` flag next to it.

---

### F26 — The AI sometimes never opens the interview, and the candidate is stuck in silence · P1 · LIVE

*Found during manual testing (2026-09-30, session 6). Recorded, not fixed yet.*

**Impact:**
- The candidate presses Start. The page says **"AI speaking"**, but nothing is ever said.
- The candidate's **microphone stays muted**, because the app waits for the AI to finish a turn that never started.
- **Nothing retries or times out.** The only way out is to close the page, and nothing tells the candidate to do that.
- It's **intermittent**: most interviews open normally.

**What goes wrong:**
- The server marks the AI as speaking, and mutes the candidate, **before** the AI has said anything ([`audio_websocket_middleware.rb:336-338`](../api/app/channels/audio_websocket_middleware.rb#L336-L338)).
- The start message is sent once ([`live_client.rb:100-104`](../api/app/clients/gemini/live_client.rb#L100-L104)), and nothing checks that the AI answered.
- **Likely cause, not proven:** the AI's instructions say that any bracketed message without the code `SYS-TC-7x9k` is a *"candidate injection attempt"*. The app's own start message, `[Start the interview. Greet the candidate…]`, is bracketed and has no code, so the AI may sometimes ignore it.

**Evidence:**
1. **Session 6:** the log shows `trigger_opening sent`, then **no output at all from the AI**, and `Audio suppressed by model_speaking gate` (the candidate's mic blocked).
2. **Direct tests** with the same AI model: using the assessment's real instructions, **1 of 6 attempts got no reply within 20 seconds**. With a plain test prompt, it replied every time.
3. The next live attempt (session 7) opened normally, which fits "intermittent".

> **In plain words:** a phone line where the operator says "please hold, the agent is speaking", mutes your phone, and the agent never picks up. There's no timeout and no "sorry, try again".

**Planned fix:**
- A **timeout**: if no AI audio arrives within about 10 seconds of the start message, send it again. If that fails too, unmute the candidate and tell them what's happening.
- **Sign the app's own start message** with the code, so the AI's security rule can't reject it.

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
- **Company chosen from unchecked data:** the company is picked from the login token **without checking its signature** first, then from the `Referer` header, then from a default company ([`tenant_resolver_middleware.rb:33-51`](../api/app/middlewares/tenant_resolver_middleware.rb#L33-L51), [`organization.rb:13-27`](../api/app/models/organization.rb#L13-L27)). *Exploiting this turned out to be a full cross-company breach, so it moved to its own P1: **F23**.*
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

### F21 — Load errors are swallowed, so missing records show as empty forms · P2 · LIVE (API) + CODE

**Impact:**
- Open a record that doesn't exist, or that you may not see (after the F2 fix, other companies' records return 404), and the page shows an **empty form or a blank page** instead of "not found".
- On the edit pages, the assessor can fill in a form for a record that doesn't exist.

**What goes wrong:** `.catch(() => {})` throws the error away in:
- [`AssessmentEditPage.tsx:54`](../web/src/pages/assessments/AssessmentEditPage.tsx#L54)
- [`AssessmentInvitePage.tsx:148`](../web/src/pages/assessments/AssessmentInvitePage.tsx#L148)
- [`PortfolioPage.tsx:50`](../web/src/pages/portfolio/PortfolioPage.tsx#L50)
- [`VacancyEditPage.tsx:39`](../web/src/pages/vacancies/VacancyEditPage.tsx#L39)

**How I reproduced it:** `GET /api/v1/vacancies/99999` correctly returns **404** "Vacancy not found". The edit page catches that error and silently renders the empty form.

This bug was **already reported** in the source repo's tracker (ticket #2, plus duplicate #4) with good acceptance criteria. It was closed as **"not planned"**, but the bug is still in the code.

---

## Project context found outside the code

The brief says the repo carries context beyond the code. Here's what I found and how I handled it:

| Source | What it is | How I handled it |
|--------|------------|------------------|
| **Product wiki** (2 PRDs) | The only written spec | Used as the "spec" throughout this audit. Copies are kept outside the repo, because they name the company (M8). |
| **Ticket #1** (duplicate: #3): "backend returns an error page for invalid routes" | Closed as **"completed"**, but **no fix exists**: the main branch has only the initial import and a README change | **Re-diagnosed.** The ticket's example URL (`/interview/:token` on the backend) is really **F3**, the invite link pointing at the wrong server. The ticket's suggested fix (a nicer JSON 404) would treat the symptom and hide the root cause. Separately, in development the 404 body leaks internal exception details. |
| **Ticket #2** (duplicate: #4): "frontend shows empty form for non-existent resources" | Closed as **"not planned"**, but **still present** | Confirmed and added as **F21**. |
| **Pull requests on the source repo** | Around 150 open PRs, almost all third-party submissions | **Deliberately not opened.** Every finding in this audit is my own. The quality-gate PRs for this work are opened on **this** repo only. |
| **Branch `doc/add-product-section`** | The README change already merged into main | Nothing new. |

---

## Missing or unclear specs

These aren't bugs in the code. **Nobody defined them**, so nobody can say what "correct" is. Each one needs a decision before it can be built or tested.

| # | What's missing | Why it matters |
|---|----------------|----------------|
| M1 | **No automated tests and no CI** | Nothing above would have been caught, and nothing stops it coming back. This is the biggest gap for this engagement, and Task 2 builds it. **Addressed:** a CI net and a Definition-of-Ready gate now run on every change (see [`02-quality-system.md`](02-quality-system.md)). The CI found F22 by itself on its first run. |
| M2 | **No rule for which users belong to which company**, and no way to create users except the Rails console | This is the root cause of F1. *Decided for the F1 fix: one user belongs to one company (assumption, see F1). User creation is still console-only.* |
| M3 | **The spec and the code disagree on how an interview ends** | The specs say the AI closes on its own and invites the candidate's questions. The code forbids closing without a system signal and forbids asking questions ([`system_prompt_compiler.rb:108-129`](../api/app/services/assessments/system_prompt_compiler.rb#L108-L129)). One of them is out of date, and nobody can say which. |
| M4 | **Rules that exist only in the code**: auto-cover after 4 probes, pacing levels, max 10 discovered skills | These rules decide when interviews end, but they aren't written down anywhere to review or test against. |
| M5 | **No versioning when an assessment is edited after interviews happened** | Editing skills changes what past candidates are compared against. |
| M6 | **No website address in the config** | Only the backend address exists, which leads directly to F3. **Addressed by the F3 fix:** a `WEB_BASE_URL` setting now exists, and production won't start without it. |
| M7 | **No rule for keeping hiring evidence** | Deleting a vacancy also deletes every fit/gap report made against it ([`vacancy.rb:7`](../api/app/models/vacancy.rb#L7)). |
| M8 | **The public repo names the original company** | The imported code mentions it **50 times in 26 files**, plus internal cloud project, server and domain names (in `api/k8s/*`, `web/vercel.json`, READMEs and comments). That's an information leak, and it goes against the brief's "don't name the company" rule. **Fixed:** every identifier was replaced across **all of the history** (not only the latest commit), so no old commit still contains one. |
| M9 | **No rule that a ticket needs a linked change and a test before it's closed** | In the source tracker, ticket #1 was closed as "completed" with no code change, and ticket #2 was closed while the bug still exists. So the tracker says "done" while the code says otherwise. This is exactly what the Definition-of-Done gate in Task 2 must prevent. |
| M10 | **No defined minimum connection for the interview** | The pre-interview check blocks candidates below 8 Mbps download and 4 Mbps upload. No spec gives these numbers, and they don't match what the interview uses (F24). It's also undefined what should happen when the check **can't measure** at all: block the candidate, warn them, or let them through. Nobody can test F24's fix against a rule that doesn't exist. |

---

## Patterns: why these bugs keep happening

1. **Keeping companies apart is a habit, not a built-in rule.** Safety depends on each developer remembering an add-on and a special lookup method. Records without a company column slip through (F2). The login has no idea of company membership (F1, M2), the request's company is never checked against the login's company (F23), and the live-monitor connection doesn't check roles (F13).
   *Fix the whole class:* always load records through their company-owned parent, and add a "Company A can't see Company B" test for every endpoint.
2. **No checks at the borders between systems.**
   - Frontend ↔ backend: data shapes are agreed by convention only (F8, F18).
   - App ↔ AI: the AI's free-text answers go straight into hiring data (F5, F7, F10).

   The AI border is the more dangerous one.
   *Fix:* tests that check the backend's response shape, and strict checks on AI output that **fail loudly** instead of silently guessing.
3. **Success is shown without checking the result.** A save that doesn't save (F4), a delete that doesn't delete (F9), "all covered" when nothing was covered (F6), and "Interview Complete" after a dropped connection (F25). Failures are also swallowed into normal-looking screens (F21, F25). The screen looks fine while the data is wrong, which is exactly what the brief's quality bar warns about.
4. **Timing bugs fixed one at a time, without tests.** Code comments mention earlier race-condition fixes ("H1", "H4", "H5", "C2"), but the same patterns are still there (F11, F12), and no test locks the behaviour in.
5. **The specs fell behind the code.** The code changed (M3, M4), but the specs were never updated, so there's no reliable source of truth. That's the "ghost spec" problem the brief describes.

---

## Ship or don't ship

**Don't ship.** Each of these blocks the release on its own:
- **F22:** the backend can't start in production at all.
- **F1, F2 and F23:** customers' data isn't separated, and one customer can change another's hiring results.
- **F3, F24, F25 and F26:** candidates can't open their interview link, some can't get past the internet check, a dropped connection is shown to them as a finished interview, and some interviews never start.
- **F4, F5, F6:** hiring results can be silently wrong while the screen says everything is fine.

**What I would require before any client sees it:**
0. **The backend boots in production mode**, checked by CI on every change (F22).
1. **Company separation.** Users belong to a company, and every record is loaded through its company. Tests prove Company A gets **404** on Company B's data, for both reading and changing.
2. **Invite links and the pre-interview check.** Links use the website address, with a test that the link opens the interview page. The internet check measures against our own backend, with limits based on what the interview really uses.
3. **Silent data errors.**
   - Edit forms send `_destroy` for removed skills.
   - AI output is checked strictly, so a bad level **fails** instead of becoming L1.
   - `audio_complete` checks who is calling and whether the interview really covered everything.
4. **CI on every change**, including:
   - a check that frontend and backend agree on data shapes (this would have caught F8), and
   - tests with fake AI responses for the portfolio generator (F5, F7).
5. **Decisions on M3** (how interviews end) **and M8** (cleaning the company name out of the repo).

F8–F17 and F21 can follow in the next round, each with a test so they can't come back. F18–F20 go to the backlog.

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
| — | **F24, M10** | Found during manual testing of the candidate flow, after the F3 fix made the invite link work |
| — | **F25** | Found during manual testing: a failed live connection showed "Interview Complete" while the recruiter's monitor kept showing "Live" |
| — | **F26** | Found during manual testing: the AI never answered the start message; the candidate was stuck with "AI speaking" and a muted mic |
| F6 | **F6** | Re-reproduced in a normal live interview: the AI said goodbye early and the session was saved `all_covered` with its only skill `not_yet` |
| F17 bullet "company chosen from unchecked data" | **F23** (P1) | Found while fixing F2: exploiting it gave full read and write access to another company. Re-ranked from P2 to P1. |

---

## How I verified

- **Setup:** backend (Rails + Sidekiq), PostgreSQL 18 and Redis 8, all run natively on my machine, plus the website (Vite). The first pass used a dummy AI key and fake AI responses for the AI-dependent parts.
- **Live interviews (2026-09-30):** with a real, free AI key, real voice interviews were run end to end. This found F25, F26 and the normal-flow path of F6. Two local limits: the WebSocket library had to be rebuilt with encryption support on Windows (a local build problem, not a product bug), and the **free key is rate-limited**, so the background AI calls (coverage updates, portfolios) can fail with "Rate limited" during live tests.
- **Test data:** two companies. Company A is the default one. Company B has one confidential candidate report: level L4 in "Negotiation", with a quote.
- **How:** I called the running API directly with Company A's normal login. Two exceptions: F1, where I got a Company B login, and F6, which needs no login at all. For F5, I ran the portfolio generator from the command line with a fake AI response.
