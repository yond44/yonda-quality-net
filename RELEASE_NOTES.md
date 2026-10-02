# Release notes

## v1.0.3

*Fixes one P1 found in a 20-run soak test after v1.0.2. Use this version instead of v1.0.2 and earlier.*

### What this version delivers

- **F35: every assessment and vacancy can be reached in the app.** The Assessments and Vacancies lists have page controls (Previous / Page X of Y / Next) once there are more than 20. Before, everything past the newest 20 was hidden, so older assessments, their candidates and results could only be opened by typing a URL. The fit/gap "Choose vacancy" list now offers every vacancy, not just the newest 20.
- Everything in v1.0.2 and earlier.

### Before deploying (required)

- Everything listed for v1.0.2, v1.0.1 and v1.0.0 below. This version changes only the web app: **no migration, no new setting**.

### Known issues in this version

- **17 lower-severity findings remain** (P2/P3): F9–F21, F34, and three new ones from the soak test:
  - **F36 (P2):** if the AI service fails in the middle of an interview, the candidate isn't told; the server keeps reconnecting. The session is still recorded correctly (ended as an error when next opened).
  - **F37 (P3):** the header badge shows a fixed company name, whoever is logged in.
  - **F38 (P3):** a login blocked by the 5-per-minute limit says "Invalid email or password." even when the password is right.
- Two more pages (live monitor, fit/gap report) show a blank page instead of "not found" for a record the user can't open (added to F21; no data is shown).
- Everything listed under "Known issues" for v1.0.2 still applies.

## v1.0.2

*Fixes four P1 findings found after v1.0.1: one in live testing with the real AI (F30), three in an end-to-end test with a real browser and a real interview (F31–F33). Use this version instead of v1.0.1 and v1.0.0.*

### What this version delivers

- **F30: portfolios are built with the real AI.** Each skill has one id across the portfolio prompt, so the AI can't copy a second id that the answer check rejects. (v1.0.1 could fail to build a portfolio for a real interview.)
- **F31: a candidate who ends the interview is told it's complete.** Pressing End Interview, or running out of time, no longer shows "Connection lost — your interview has not ended". A connection that really drops still offers to reconnect.
- **F32: the PDF export works for every portfolio.** It no longer fails for a portfolio a recruiter has overridden, or for AI text with symbols such as "→" or "≥". The PDF uses a Unicode font (DejaVu Sans, shipped with the backend).
- **F33: choosing a level changes only the skill it belongs to.** On forms with several skills (vacancies, assessments), clicking the level text of one skill no longer changes another skill's level.
- Everything in v1.0.1 and v1.0.0.

### Before deploying (required)

- Everything listed for v1.0.1 and v1.0.0 below. This version adds **no migration**.
- **Restart every background worker (Sidekiq) when deploying.** A worker started before the deploy keeps running the old code: in testing, an old worker reproduced F30 after it was fixed.
- **Ship the font files** in `api/vendor/fonts/` with the backend (they're in the repo; check that the deploy image doesn't strip them).
- **Re-check the required levels of every vacancy created or edited before this version** (F33). A level may have been saved on the wrong skill, and nothing in the data shows which.

### Known issues in this version

- **14 lower-severity findings remain** (P2/P3: F9–F21 and F34, the live monitor of a finished interview still saying "Live"). Each is listed with a mitigation and an owner in the release decision.
- **PDF limits (F32):** emoji and Chinese/Japanese characters print as blank boxes, and Arabic isn't laid out right to left. The web's export buttons still show no message if an export fails for another reason (the F21 pattern).
- **The end-to-end test is not part of CI.** It needs running servers, a browser and the real AI, so it's run before a release (scripts and results are described in `assessment/01-audit.md`, "How I verified"). Long interviews that end on "all covered" or at the 10-minute limit were not run live; unit tests cover those paths.

## v1.0.1

*Fixes a P1 found in a manual review after v1.0.0 was tagged. Use this version instead of v1.0.0.*

### What this version delivers

- **F28: a skill with no evidence is "Not assessed", never given a level.** An interview where the candidate never answered (for example, one that crashed before anyone spoke) no longer gets an invented L1. The AI can say a skill wasn't assessed, fit/gap shows "not assessed" instead of a gap, and the website and PDF say "Not assessed". A recruiter can still set a level by hand.
- Everything in v1.0.0.

### Before deploying (required)

- Everything listed for v1.0.0 below, plus **run the new migration**, which allows a skill to have no level. It can be rolled back only while no skill is "not assessed".
- **Regenerate portfolios from interviews without candidate answers.** Ones generated before this version may show an invented level.

## v1.0.0

*The first release built and checked with the quality net.* It fixes every P0 and P1 finding in the audit ([`assessment/01-audit.md`](assessment/01-audit.md)). Each fix is covered by a check that failed before it and passes now. The release decision, with the accepted risks, is in [`assessment/03-release-decision.md`](assessment/03-release-decision.md).

### What this version delivers

**Companies are kept apart**
- **F1:** login issues a token only for the user's own company.
- **F2:** one company can no longer read or change another company's candidate reports.
- **F23:** a valid login no longer works inside another company.

**Candidates can take their interview, and are told the truth about it**
- **F3:** invite links open the interview page.
- **F24:** the internet check measures what the voice interview actually needs, against our own backend, and never invents a result.
- **F25:** a dropped connection, a page that can't load, or a server error is never shown as "Interview Complete". An interview abandoned past its time limit is ended instead of staying "Live" forever.
- **F26:** if the AI doesn't answer the opening, it's asked again, and then the candidate gets the turn.
- **F6:** "all skills covered" is recorded only when the coverage data says so. Otherwise the reason is `partial_coverage`.

**Hiring results are stored correctly**
- **F4:** a skill removed in an edit form is really removed.
- **F5:** AI levels are read strictly (`3`, `"3"`, `"L3"`). An unreadable level fails the generation instead of becoming L1, and a failed regeneration keeps the previous result.
- **F7:** portfolio skills are tied to the configured skills, not to how the AI worded them.
- **F8:** the fit/gap "Required" column and the override marker are shown.
- **F27:** the AI's hidden notes use the tag its instructions tell it to keep silent. If it reads one aloud anyway, the recruiter's transcript says so.

**Platform**
- **F22:** the backend starts in production mode.

**Quality system**
- The **quality net**: checks on every push and pull request (API tests, web tests, production boot, web build).
- The **Definition-of-Ready gate**: a pull request needs a linked spec, acceptance criteria, a design plan and a test.
- The **release gate**: every version tag is checked and marked releasable or blocked.
- Branch protection makes these checks required before merging.

### Before deploying (required)

1. **Run the database migrations.** They add `users.organization_id` (F1) and the `partial_coverage` end reason (F6). The second can't be rolled back.
2. **Assign every existing user to their company.** A user without one can't log in (F1).
3. **Set `WEB_BASE_URL`** to the website's public address. The backend won't start in production without it (F3).
4. **Rotate `SECRET_KEY_BASE`**, so login tokens issued before the F1 and F23 fixes stop working.
5. **Re-send invite links** sent before this release. They point at the backend (F3).

### Known issues in this version

- **13 lower-severity findings remain** (P2/P3: F9–F21). None is *known* to lose or corrupt data; F11 and F12 are unconfirmed timing risks that could. Each is listed with a mitigation and an owner in the release decision. *(Corrected after tagging: the v1.0.0 tag's copy says "none loses or corrupts data", which was too strong.)*
- **4 product decisions are still open** (M3, M4, M5, M7 in the audit): how interviews end, rules that exist only in the code, versioning edited assessments, and how long hiring evidence is kept.
