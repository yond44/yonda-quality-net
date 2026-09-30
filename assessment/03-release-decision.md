# 03 — Release decision: v1.0.0

**Decision: SHIP v1.0.0, with the conditions and accepted risks below.**
**Release owner:** yond44. I'm accountable for this call and for the engineering risks listed.

In one sentence: every blocker and major issue from the audit is fixed and guarded by an automated check, and the release gate marks this version releasable. The remaining issues are minor, and each is listed with what limits it and who owns it. Two of them (F12 and F21) should be fixed first in the next release, and until then the first clients' interviews should be watched for the problem F12 can cause.

---

## What the release gate checked

The tag `v1.0.0` (commit `32d6d69`) ran the release gate: [run 36689598002](https://github.com/yond44/yonda-quality-net/actions/runs/36689598002). Its verdict is the **"Release status"** check on the tag's commit: **✅ v1.0.0 is RELEASABLE**.

| Check | What it proves | Result |
|---|---|---|
| Net: API tests (audit findings + critical paths) | Every P0/P1 finding stays fixed; companies are kept apart; the main journey works | ✅ |
| Net: web tests, type-check and build | The web app builds, and the tested page logic (internet check, failure screens) holds | ✅ |
| Net: API boots in production mode | The backend starts with production settings | ✅ |
| Gate: self-test | The Definition-of-Ready gate's and the release gate's own rules still hold | ✅ |
| **No P0/P1 left unfixed in the audit** | Read from the Status column of [`01-audit.md`](01-audit.md), so a known blocker stops a release even if every test is green | ✅ |
| **Release notes describe v1.0.0** | [`RELEASE_NOTES.md`](../RELEASE_NOTES.md) states what this version claims to deliver | ✅ |

How the release gate works, and how to reuse it for the next version, is in [`02-quality-system.md`](02-quality-system.md) ("The release gate").

## What it found

- **All 12 P0/P1 findings are fixed:** F22, F1, F2, F23, F3, F4, F5, F6, F7, F24, F25 and F26. Each was proven by a check that failed first and passes now (the red → green log in `02`). Two P2s (F8 and F27) were fixed as well.
- **13 P2/P3 findings remain**, and **4 product decisions are open**. None of them is a known P0/P1.
- **Branch protection is on:** the five checks are required before a pull request can merge.

## What the gate does *not* prove (judging my own work)

- **The live voice interview is only partly covered.** The live connection code is tested through its pieces (the AI client's watchdog, the message the server sends, the transcript filter) and by one real manual interview. There is no automated end-to-end test of a real call.
- **The AI's behaviour isn't tested.** Tests use a fake AI. The real one can still end an interview early (now recorded honestly as `partial_coverage`) or read a hidden note aloud (now visible in the transcript).
- **The gate trusts the audit's Status column.** Marking a finding "fixed" is a human judgment. The gate enforces it; it doesn't verify it.
- **A correction to the v1.0.0 release notes:** they said none of the remaining findings "loses or corrupts data". That's too strong. F11 and F12 are unconfirmed timing risks that could, so the notes on `main` have been corrected.

## Conditions for shipping

1. **Do the required deploy steps** in [`RELEASE_NOTES.md`](../RELEASE_NOTES.md): run the migrations, assign every user to their company, set `WEB_BASE_URL`, rotate `SECRET_KEY_BASE`, and re-send old invite links.
2. **Build the website with `VITE_DEV_TOKEN` empty** (F17). Otherwise every visitor is logged in as that developer.
3. **Don't deploy with the Kubernetes files as they are** (F16). Ops must add the secrets, fix the worker's mode and pin image versions first.
4. **For the first clients, check each interview's transcript for gaps** until F12 is fixed.
5. **Next release (v1.0.1) starts with F21 and F12,** then F13 and F17.

## Accepted risks and owners

| Risk | Sev | Why it can wait | What limits it now | Owner |
|---|---|---|---|---|
| **F12:** transcript lines can be lost after a page refresh | P2, unconfirmed | Not reproduced; needs two live connections for the same interview at once | Condition 4. **First fix in v1.0.1.** The F25 "Reconnect" button reloads the page, which makes the trigger more likely | Engineering (yond44) |
| **F21:** a failed load shows an empty edit form | P2 | The page is wrong, but the stored data is right | **Made riskier by the F4 fix:** saving that empty form with a new name would remove the skills. An empty name fails validation, so it needs deliberate typing. **First fix in v1.0.1** | Engineering (yond44) |
| **F11:** simultaneous coverage updates can overwrite each other | P2, unconfirmed | Not reproduced; timing-dependent | Since F6, a lost update makes an ending `partial_coverage`, not a false "complete" | Engineering (yond44) |
| **F13:** the live monitor doesn't check the user's role | P2 | Login only issues tokens to admins, so other roles can't log in | Keep non-admin roles disabled | Engineering (yond44) |
| **F17:** login gaps (dev-token fallback, removed users keep access for up to 3 days, token in `localStorage`) | P2 | Each needs a specific misconfiguration or a stolen token | Conditions 1–2; rotate the key if a user must be cut off at once | Engineering + Ops |
| **F16:** deployment files would misconfigure production | P2 | Not application code | Condition 3 | Ops owner (to be named by the client) |
| **F9:** delete reports success but deletes nothing | P2 | No delete button in the website; only direct API users are affected | Nothing is lost; the response is wrong | Engineering (yond44) |
| **F10:** the AI decides "confidence" | P2 | The level is correct; confidence is a secondary label | Recruiters can override ratings | Engineering + Product owner |
| **F14, F15:** prompt details (what doesn't count; the next-question hint) | P2 | They affect question focus, not stored results | Recruiters review the transcript | Engineering (yond44) |
| **F18–F20:** cosmetic issues | P3 | No effect on function or data | Backlog | Engineering (yond44) |
| **M3, M4, M5, M7:** open product decisions (how interviews end, rules only in code, versioning, evidence retention) | — | They need a product decision, not code | Current behaviour documented in the audit | Product owner (to be named by the client) |
| **M2, M10:** working assumptions (one user = one company; minimum connection speed) | — | Reasonable defaults, written down | Easy to change once decided | Product owner (to be named by the client) |

## Why ship rather than block

- **No P0 or P1 is open.** By the brief's own rule, the release isn't blocked on severity.
- **The remaining issues are known, limited and owned.** The two with a possible data impact (F12, F11) are unconfirmed timing risks with a watch-and-fix plan, not known defects.
- **Blocking would hold back fixes that matter more:** cross-company data access, wrong levels stored for candidates, and interviews that couldn't start. Those are fixed in this version, and they're worse than anything still open.

If F12 turns out to be real in the first clients' interviews, it becomes a data-integrity issue (at least P1) and **the next release must fix it before any wider rollout**.
