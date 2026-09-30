# Release notes

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

- **13 lower-severity findings remain** (P2/P3: F9–F21). None loses or corrupts data. Each is listed with a mitigation and an owner in the release decision.
- **4 product decisions are still open** (M3, M4, M5, M7 in the audit): how interviews end, rules that exist only in the code, versioning edited assessments, and how long hiring evidence is kept.
