# 03 — Release decision: v1.0.3 (supersedes v1.0.2 and earlier)

## Update, 2026-10-02: ship v1.0.3

**Decision: SHIP v1.0.3, with the conditions and accepted risks below. Do not roll out v1.0.2 or earlier.**
**Release owner:** yond44.

**What happened after v1.0.2:** before submitting, I ran a **soak test**: the whole product 20 times in a real browser, with two companies, two real AI interviews, and the API and background-job logs read after every run.
- **381 of 383 steps passed. No data leaked between the companies in any of the 20 runs** (lists after switching accounts in the same browser, the first company's links opened by the second, every API response scanned, and the API isolation sweep). No server errors.
- It found **F35 (P1)**: the Assessments and Vacancies lists only showed the newest 20, so older assessments, their results, and older vacancies (including for fit/gap) could only be reached by typing a URL. This was in the original code, and every client would hit it within weeks. Fixed test-first: red [36970071541](https://github.com/yond44/yonda-quality-net/actions/runs/36970071541), green [36970269123](https://github.com/yond44/yonda-quality-net/actions/runs/36970269123). Checked in the browser with 30 assessments and 25 vacancies.
- It also found three smaller issues, recorded and accepted below (F36, F37, F38), and two more pages for F21.
- One AI interview failed because **Google's Gemini Live was down** (error 1011, reproduced outside the app, recovered within the hour). The second AI run passed end to end.
- **The release gate on v1.0.3 says ✅ RELEASABLE:** [36970472169](https://github.com/yond44/yonda-quality-net/actions/runs/36970472169).

**Conditions:** the same as v1.0.2 (below). This version changes only the web app: no migration, no new setting.

**Extra accepted risks, owner yond44:**
- **F36 (P2):** if the AI service fails in the middle of an interview, the server keeps reconnecting and the candidate is never told. *Mitigation:* the session is still recorded correctly (ended as `error` when next opened, F25); watch the logs for `Gemini closed unexpectedly` during the first clients' interviews. *First fix of the next version:* count a reconnect as a success only once the AI has answered.
- **F37 (P3):** the header badge shows a fixed company name. *Mitigation:* no data is affected; set the badge from the logged-in user in the next version.
- **F38 (P3):** a rate-limited login says "Invalid email or password." *Mitigation:* the limit lasts a minute; show a "too many attempts" message in the next version.
- **F21 (P2), widened:** the live monitor and fit/gap pages also show a blank page instead of "not found" for a record the user can't open. No data is shown.

**The count:** all **18** P0/P1 findings are fixed (F35 added). **17** P2/P3 remain (F9–F21, F34, F36, F37, F38).

---


## Update, 2026-10-01 (latest): ship v1.0.2

**Decision: SHIP v1.0.2, with the conditions and accepted risks below. Do not roll out v1.0.1 or v1.0.0.**
**Release owner:** yond44.

**What happened after v1.0.1:**
- **F30 (P1)**, found in live testing with the real AI: a skill had two ids in the portfolio prompt, so a real interview could end with no portfolio. Fixed test-first: red [36815953972](https://github.com/yond44/yonda-quality-net/actions/runs/36815953972), green [36816139679](https://github.com/yond44/yonda-quality-net/actions/runs/36816139679).
- **An end-to-end test** was then run on the whole product: every API endpoint for two companies (65 checks), then a real Chrome driven by a script through the recruiter's and the candidate's journeys, including a real voice interview with the AI. It found three more P1s and one P3:
  - **F31 (P1, a regression from the F25 fix):** a candidate who pressed End Interview, or ran out of time, was told "Connection lost — your interview has not ended". Red [36827787574](https://github.com/yond44/yonda-quality-net/actions/runs/36827787574), green [36827803414](https://github.com/yond44/yonda-quality-net/actions/runs/36827803414).
  - **F32 (P1):** the PDF export failed (500) for every portfolio a recruiter had overridden. Red [36827823866](https://github.com/yond44/yonda-quality-net/actions/runs/36827823866), green [36827849551](https://github.com/yond44/yonda-quality-net/actions/runs/36827849551).
  - **F33 (P1):** on a form with several skills, clicking one skill's level text changed another skill's level, so a vacancy could be saved with wrong required levels. Red [36827870194](https://github.com/yond44/yonda-quality-net/actions/runs/36827870194), green [36827898429](https://github.com/yond44/yonda-quality-net/actions/runs/36827898429).
  - **F34 (P3):** the live monitor of a finished interview still says "Live". Accepted below.
- After the fixes, the same end-to-end test passed in full (API 65/65; browser journeys 7/7, 9/9, 10/10).
- **The release gate on v1.0.2 says ✅ RELEASABLE:** [36828232430](https://github.com/yond44/yonda-quality-net/actions/runs/36828232430). Every net check passed on the tagged commit, no P0/P1 is left unfixed in the audit, and the release notes describe v1.0.2.

**Conditions (in addition to v1.0.1's and v1.0.0's, below):**
- **Restart every background worker when deploying.** In testing, a worker started before a fix kept running the old code and reproduced F30.
- **Ship the PDF font files** (`api/vendor/fonts/`) with the backend.
- **Re-check the required levels of every vacancy saved before v1.0.2** (F33): a level may have landed on the wrong skill, and the data can't show which.
- **Run the end-to-end test before every release.** It needs running servers, a browser and the real AI, so it isn't part of CI; it is what found F31–F33 after every unit check was green.

**Extra accepted risks, owner yond44:**
- **F34 (P3):** the monitor of a finished interview says "Live" and shows no "ended" banner. The data and the portfolio link are correct.
- **PDF limits (F32):** emoji and Chinese/Japanese characters print as blank boxes; Arabic isn't laid out right to left.
- **Silent export failures:** the web's export buttons show no message if an export fails for another reason (the F21 pattern; F21 is first in line for the next version).
- **Not run live:** interviews that end on "all covered" or at the time limit. Unit tests cover both paths (F6, F31), but the free AI quota didn't allow long live interviews.

**The count:** all **17** P0/P1 findings are fixed (F22, F1, F2, F23, F3, F24, F4, F5, F25, F6, F7, F26, F28, F30, F31, F32, F33). **14** P2/P3 remain (F9–F21, F34).

**What this release shows about the net:** two of the four new P1s were regressions of my own fixes (F30 from F7, F31 from F25). In both cases the fix was right for the case it targeted and wrong for a path its tests didn't exercise, and in both cases a test against the real thing (the real AI, a real browser) caught it, not the unit net. That's why running the end-to-end test before a release is now a condition, not an extra.

---


## Update, 2026-10-01 (later): v1.0.1 is not shippable either

Live testing with the real AI after v1.0.1 found **F30 (P1)**: the F7 fix gave each skill two different ids in the portfolio prompt. When the AI copied the wrong one, the portfolio failed (session 11). It's fixed on `main`, test-first: red [36815953972](https://github.com/yond44/yonda-quality-net/actions/runs/36815953972), green [36816139679](https://github.com/yond44/yonda-quality-net/actions/runs/36816139679). The real AI regenerated session 11's portfolio successfully afterwards.

**Decision: don't ship v1.0.1. The next release (v1.0.2) must go through the release gate first.** The section below explains the v1.0.1 decision as it was made, before F30 was known.

---

## Update, 2026-10-01: ship v1.0.1, not v1.0.0

**Decision: SHIP v1.0.1, with the conditions and accepted risks below. Do not roll out v1.0.0.**
**Release owner:** yond44.

**What happened after v1.0.0 was tagged:**
- A manual review of the generated portfolios found **F28 (P1)**: a skill with no evidence still got a level. Interviews that crashed before anyone spoke had "complete" portfolios with **L1** for a skill nobody discussed. When the AI tried to say "below the scale" (level 0), a retry turned it into L1.
- Recording F28 as *remaining* in the audit made the release gate **block the next version**. Run locally, it said *"⛔ v1.0.1 is BLOCKED — F28 (P1, remaining)"*. That's the gate doing its job: a known P1 stops a release even when every test is green.
- F28 was then fixed test-first, with CI red by itself ([run 36812383367](https://github.com/yond44/yonda-quality-net/actions/runs/36812383367)) and then green ([run 36812959237](https://github.com/yond44/yonda-quality-net/actions/runs/36812959237)). A skill with no evidence is now **"not assessed"**, never given a level.
- **The release gate on v1.0.1 says ✅ RELEASABLE:** [run 36813056953](https://github.com/yond44/yonda-quality-net/actions/runs/36813056953).

**Why this matters:** v1.0.0 was marked releasable because the gate can only check what's known. The P1 was found by a human reviewing real output, which is why the conditions below keep a manual check of the first clients' results.

**Everything below (the v1.0.0 decision) still applies to v1.0.1**, plus three additions:
- **Extra condition:** after deploying, **regenerate the portfolios of interviews with no candidate answers**. Ones generated before v1.0.1 may show an invented level.
- **Extra accepted risks (F28 leftovers), owner yond44:**
  - "below L1" isn't its own outcome; it's recorded as "not assessed" with the AI's reason (product decision M11);
  - the AI's answer format is requested in the prompt but not yet enforced with Gemini's response schema;
  - the existing invented levels stay until regenerated (covered by the condition above).
- **The count:** all **13** P0/P1 findings are fixed (F28 included).

---

## The v1.0.0 decision (kept for the record)

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
