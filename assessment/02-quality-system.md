# 02 — Quality System

This is the "net" around the platform. It has two halves:

1. **The workflow gate.** A pull request can't merge unless it carries its **inputs**: a linked spec, acceptance criteria, a design plan, and a test. This targets "ghost spec" work *before* it's built.
2. **The test net (CI).** It runs on every push and every pull request, goes **red by itself** on the real defects from the audit ([`01-audit.md`](01-audit.md)), and stays red until each one is fixed.

Everything runs in GitHub Actions: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml). On any run page, the **summary** shows one row per audit finding (✅ / ❌), and each failure also appears as a red **annotation**. You can see what's broken without reading logs.

---

## The checks

| Check (as named on GitHub) | What it protects | Catches (from the audit) |
|---|---|---|
| **Gate: Definition of Ready** *(pull requests only)* | No change merges without its inputs | M9 (tickets "done" with no change or test), and the brief's "ghost spec" problem |
| **Gate: self-test** | The two gates' own rules can't be silently weakened | A broken or loosened gate |
| **Net: API boots in production mode** | The backend actually starts with production settings | **F22** (P0): production couldn't boot |
| **Net: API tests (audit findings + critical paths)** | Data integrity and tenant isolation on the risk-carrying paths, plus the main journey | **F1–F8, F23**, and any regression on the critical path |
| **Net: web tests, type-check and build** | The web app's risk-carrying logic, and that it compiles and builds | **F24**, plus type errors and broken builds in the frontend |

### What the gate checks

A PR description starts from [`.github/pull_request_template.md`](../.github/pull_request_template.md). The gate ([`definition-of-ready.mjs`](../.github/scripts/definition-of-ready.mjs)) fails the PR if any of these is missing:

| Input | Rule |
|---|---|
| **Spec linked** | The "Spec / PRD" section contains a URL, an issue reference (`#12`), or a path to a file that **exists** in the repo (e.g. `assessment/01-audit.md#f21`) |
| **Acceptance criteria** | At least one scenario written as **Given / When / Then** (the format gate G2 asks for) |
| **Design plan** | A short plan: at least a sentence, not left empty |
| **Test added or changed** | If the PR changes application code (`api/app`, `api/config`, `api/db`, `api/lib`, `web/src`), it must also change a test (`api/spec/…` or `*.test.*` / `*.spec.*`) |

**Not bureaucratic, by design:**
- **Docs-only PRs** (only `*.md` or `assessment/`) are exempt.
- The template's hint text is ignored, so a PR can't pass by leaving the template untouched.
- When the gate fails, it prints **exactly which input is missing and how to fix it**.

### What the test net covers

One spec file per **class of risk**, not a coverage percentage:

| Spec | Class of risk | Key assertion |
|---|---|---|
| [`login_tenant_isolation_spec.rb`](../api/spec/requests/auth/login_tenant_isolation_spec.rb) | **F1** login gives a token for the wrong company | A token is only ever issued for the user's own company |
| [`f2_cross_tenant_portfolio_spec.rb`](../api/spec/requests/f2_cross_tenant_portfolio_spec.rb) | **F2** one company reads or **changes** another's data | Company A gets 404 on company B's records, and nothing is read or changed |
| [`f23_token_company_mismatch_spec.rb`](../api/spec/requests/f23_token_company_mismatch_spec.rb) | **F23** a valid token opens another company | A token is rejected (401) in any company except the one it was issued for, whatever form the header takes |
| [`f3_invite_url_spec.rb`](../api/spec/models/f3_invite_url_spec.rb) | **F3** invite link leads to a 404 | The link uses the web app's address, on a route `web/src/App.tsx` really serves |
| [`f4_removed_skills_spec.rb`](../api/spec/requests/f4_removed_skills_spec.rb) | **F4** "removed" skills stay | The exact payload the edit page sends really removes the skill |
| [`f5_level_parsing_spec.rb`](../api/spec/services/f5_level_parsing_spec.rb) | **F5** unreadable AI level stored as L1 | `"L3"` becomes 3, and a missing level fails loudly |
| [`f6_audio_complete_spec.rb`](../api/spec/requests/f6_audio_complete_spec.rb) | **F6** false "all covered" | A never-started or uncovered interview is not recorded as `all_covered` |
| [`f7_skill_identity_spec.rb`](../api/spec/services/f7_skill_identity_spec.rb) | **F7** skills keyed on the AI's wording | Skills stay tied to the configuration, and a dropped skill fails loudly |
| [`f8_fitgap_contract_spec.rb`](../api/spec/requests/f8_fitgap_contract_spec.rb) | **F8** web ↔ API contract | The payload has every field the **web's own TypeScript type** requires |
| [`internetSpeedTest.test.ts`](../web/src/utils/internetSpeedTest.test.ts) | **F24** the internet check blocks good connections | The real check, run on a simulated network, passes the reported connection, measures against our own backend, one thing at a time, and never passes when it couldn't measure |
| [`useAudioWebSocket.test.ts`](../web/src/hooks/useAudioWebSocket.test.ts) and [`InterviewPage.test.tsx`](../web/src/pages/interview/InterviewPage.test.tsx) | **F25** a failure is shown to the candidate as a finished interview | After a dropped connection, or when the page can't load, the candidate is never told "Interview Complete"; a real end still is |
| [`f25_abandoned_session_spec.rb`](../api/spec/requests/f25_abandoned_session_spec.rb) | **F25** an abandoned interview stays "Live" forever | An interview long past its time limit isn't reported as live, to the recruiter or on the candidate's link; one within its limit stays resumable |
| [`f26_opening_watchdog_spec.rb`](../api/spec/clients/f26_opening_watchdog_spec.rb) | **F26** the AI never opens the interview and the candidate is stuck muted | If the AI hasn't answered the start message in time it is asked again, then the turn goes back to the candidate; nothing happens once the AI talks |
| [`f27_hidden_notes_spec.rb`](../api/spec/services/f27_hidden_notes_spec.rb) | **F27** the AI reads its hidden notes aloud, and the record hides it | The notes are sent under the tag the AI's instructions name (read from the real instructions); a slip is marked in the recruiter's transcript |
| [`f28_no_evidence_spec.rb`](../api/spec/services/f28_no_evidence_spec.rb), [`constants.test.ts`](../web/src/utils/constants.test.ts) and [`LevelBadge.test.tsx`](../web/src/components/portfolio/LevelBadge.test.tsx) | **F28** a skill with no evidence gets a level | No answers → "not assessed" without asking the AI; the AI's "not_assessed" is kept; fit/gap and the page show "not assessed", never L1 |
| [`f30_one_skill_id_spec.rb`](../api/spec/services/f30_one_skill_id_spec.rb) | **F30** portfolios fail when the AI copies a different id | A fake AI that copies the coverage id (as the real one did) still gets a portfolio; each skill has one id across the prompt |
| [`useAudioWebSocket.test.ts`](../web/src/hooks/useAudioWebSocket.test.ts) (F31 block) and [`InterviewEnd.test.tsx`](../web/src/pages/interview/InterviewEnd.test.tsx) | **F31** a candidate who ends the interview is told "Connection lost" | After End Interview, and after the time runs out, the page shows "Interview Complete"; a real drop still reconnects |
| [`f32_pdf_export_spec.rb`](../api/spec/requests/f32_pdf_export_spec.rb) | **F32** the PDF export crashes on characters its font can't encode | A portfolio with an override, or with symbols such as `→` and `≥` in the evidence, exports as a PDF |
| [`LevelRadio.test.tsx`](../web/src/components/assessment/LevelRadio.test.tsx) | **F33** a level click changes another skill | With two level pickers on a page, clicking the second one's "L2" changes only the second; every option has its own id |
| [`AssessmentListPage.test.tsx`](../web/src/pages/assessments/AssessmentListPage.test.tsx), [`VacancyListPage.test.tsx`](../web/src/pages/vacancies/VacancyListPage.test.tsx) and [`PortfolioPage.test.tsx`](../web/src/pages/portfolio/PortfolioPage.test.tsx) | **F35** records past the first page of 20 are unreachable | The 21st assessment and vacancy can be reached; fit/gap offers a vacancy beyond the newest 20; a short list shows no page controls |
| [`critical_path_spec.rb`](../api/spec/requests/critical_path_spec.rb) | **Regression on the main journey** | Log in → assessment → invite → candidate opens it; interview → portfolio → fit/gap |

**Two design choices keep the net honest:**
- **Controls.** Each finding spec has a "the right thing still works" example (e.g. *company B still sees its own portfolio*). A "fix" that just returns 404 to everyone, or breaks the auto-end, goes red.
- **Contract tests read the other side's real code.** F8 takes its field list from `web/src/types/index.ts`, and F3 checks the route in `web/src/App.tsx`. Renaming something on **either** side fails the build. Hand-maintained contracts were the root pattern behind several audit findings.

**AI is never called in tests.** Fake models stand in for Gemini ([`fixture_helpers.rb`](../api/spec/support/fixture_helpers.rb)). They behave like a model that follows the prompt: they read the skills and IDs from the real prompt and answer with them. So the tests exercise the real prompt → parse → store path, can script awkward answers (paraphrased names, `"L3"`, missing levels), and run offline in seconds.

---

## What the net deliberately does NOT cover

Knowing the gaps is part of the system. These are known and accepted for now:

| Not covered | Why | Risk that remains |
|---|---|---|
| **Real AI behaviour** (question quality, probing, rating accuracy) | Tests use fake models, so they're deterministic and free | The AI could interview badly and no check would notice. That needs a separate evaluation set against the spec, not unit tests. |
| **The live voice interview** (WebSocket audio, reconnects, timing) | Needs a real browser, audio and Gemini Live | Races **F11** (coverage updates) and **F12** (lost transcript lines) are untested |
| **Frontend screens** | Web tests (Vitest, with a simulated browser) cover the internet check (F24), the interview connection and the interview page's load and end states (F25). Most other pages are not rendered by any test | **F21** (error states) and the web side of F4 are untested. The build passes even if a page shows wrong data. |
| **P2/P3 findings** other than F8 | Time goes to P0/P1 first, as the brief allows | F9–F21 have no checks yet (listed as open in the audit) |
| **Production configuration beyond boot** | The boot check uses dummy secrets | **F16**: the real deployment files still lack secrets and pin `:latest` images |
| **Quality of a PR's inputs** | The gate checks the inputs **exist and have the right shape**, not whether they're **good** | A vague spec or a weak test can still pass. Human review is still needed. The gate removes "forgot the spec", not bad judgment. |

---

## The release gate

A separate workflow, [`release.yml`](../.github/workflows/release.yml), runs **on every version tag** (`v1.0.0`, `v1.0.1`, ...). It's reusable for every release, not a one-off script.

1. It re-runs the **whole quality net** on the tagged commit, reusing [`ci.yml`](../.github/workflows/ci.yml) rather than copying it.
2. A final check, **"Release status"**, decides ([`release-gate.mjs`](../.github/scripts/release-gate.mjs)) and shows one line on the run page: **"✅ v1.0.0 is RELEASABLE"** or **"⛔ v1.0.0 is BLOCKED"**, with a table of the three conditions:
   - the quality net passed on this commit;
   - **no P0/P1 finding is left unfixed in the audit**. This is read from the Status column of [`01-audit.md`](01-audit.md), so a known blocker stops a release even if every test is green;
   - `RELEASE_NOTES.md` has a section for this tag.

Its rules are tested in [`release-gate.test.mjs`](../.github/scripts/release-gate.test.mjs), which runs in "Gate: self-test".

To release: add a `## vX.Y.Z` section to `RELEASE_NOTES.md`, merge it, then push the tag (`git tag vX.Y.Z && git push origin vX.Y.Z`). Read the verdict on the tag's run.

## How to run it locally

**Backend tests.** Needs PostgreSQL and the local setup from the API README:
```bash
cd api
RAILS_ENV=test bundle exec rails db:create db:migrate   # first time only
bundle exec rspec                                      # the whole net
bundle exec rspec --format json --out rspec.json && node ../.github/scripts/rspec-summary.mjs rspec.json   # the per-finding table
```

**Production boot check** (the same check CI runs, with dummy settings):
```bash
cd api
RAILS_ENV=production SECRET_KEY_BASE=x ALLOWED_ORIGINS=http://x GEMINI_API_KEY=x \
  GEMINI_LIVE_MODEL=x GEMINI_FLASH_MODEL=x GEMINI_PRO_MODEL=x FORCE_SSL=false \
  WEB_BASE_URL=http://localhost:5173 \
  bundle exec rails zeitwerk:check
```

**Gate self-tests, web tests and the web build:**
```bash
node --test .github/scripts/definition-of-ready.test.mjs .github/scripts/release-gate.test.mjs
cd web && npm ci && npm test && npm run build
```

## How to extend it

- **A new defect:**
  - Add a spec whose top-level description starts with the finding ID, e.g. `RSpec.describe 'F9: ...'`. It appears in the CI summary automatically.
  - Write it so it **fails on the bug first**, and include a control that must stay green.
- **A new gate rule:** add it in `definition-of-ready.mjs` **and** a case in `definition-of-ready.test.mjs`, so the rule itself is tested.
- **Fakes for AI answers:** build a `FakePortfolioModel` with `levels:`, `rename:` or `omit:` to script how the "model" answers.

## Making the gate impossible to skip (one-time GitHub setting)

**Status: enabled** on `main` (2026-09-30), with all five checks below required. Verified through GitHub's API. It was turned on after pull requests #1 and #2, which is why those two could still be merged with a red gate (see "The gate in action").

A CI check only **blocks** a merge when GitHub is told it's required. This is a repository setting, so it can't be committed as code:

1. Go to **Settings → Branches → Add branch protection rule** for `main`.
2. Tick **Require status checks to pass before merging**, and add:
   - `Gate: Definition of Ready`
   - `Gate: self-test`
   - `Net: API boots in production mode`
   - `Net: API tests (audit findings + critical paths)`
   - `Net: web tests, type-check and build`

   A check only appears in that list after it has run once, and the gate runs on the first pull request.
3. Leave **"Do not allow bypassing"** unticked. The brief allows the bulk of the work as direct commits to `main`, so the owner can still push directly, but every pull request must pass.

---

## The gate in action: three pull requests

The brief asks for the gate to be **shown working on real changes**, not just described. Three pull requests did that, and all three stay visible:

| Pull request | What it changes | Its description | Gate: Definition of Ready | Rest of CI | What happened |
|---|---|---|---|---|---|
| [#2](https://github.com/yond44/yonda-quality-net/pull/2) | A one-line "quick fix" to the fit/gap page's culture box, with no test | The empty template, on purpose | ❌ **Blocked** on all four inputs ([36667157742](https://github.com/yond44/yonda-quality-net/actions/runs/36667157742)) | ❌ (F8 wasn't fixed on `main` yet) | Merged anyway (see below), then **reverted** on `main` |
| [#1](https://github.com/yond44/yonda-quality-net/pull/1) | The F8 fix, with a new test | The empty template, **by mistake**: the prepared description wasn't pasted | ❌ **Blocked**: no spec, criteria or plan ([36667125182](https://github.com/yond44/yonda-quality-net/actions/runs/36667125182)) | ✅ All green | Merged anyway (see below). The code was sound; the gate caught the missing inputs |
| [#3](https://github.com/yond44/yonda-quality-net/pull/3) | The F25 follow-up: a server error while opening the interview was shown as "Interview Complete" | Spec linked, Given/When/Then criteria, design plan, tests | ✅ **Passed** in both runs | ❌ then ✅: [36668038365](https://github.com/yond44/yonda-quality-net/actions/runs/36668038365) with only the new tests, [36668170107](https://github.com/yond44/yonda-quality-net/actions/runs/36668170107) with the fix | All checks green |

**What this showed:**
- **The gate does its job.** It stopped the two PRs that had no inputs, including a real fix whose description was simply forgotten, and passed the one that had them. A forgotten description is exactly the everyday slip it exists to catch.
- **It only *blocks* once branch protection is on.** Without the GitHub rule, a failed check is just a red mark, and anyone can still press Merge. That's how #1 and #2 got in. Turning on "Require status checks to pass before merging" (see "Making the gate impossible to skip" above) is what turns the gate from a warning into a gate. The unspecified change from #2 was reverted on `main`, because it quietly made a product decision nobody had specified.
- **Red → green inside a pull request.** In #3 the tests were pushed first. The gate passed (the inputs were there) while the tests were red, then the fix turned the tests green.

Before opening them, the descriptions were also run through the gate's own code (`evaluate()` in [`definition-of-ready.mjs`](../.github/scripts/definition-of-ready.mjs)) with each branch's real list of changed files.

## Red → green log

Every fix follows the same order: **a failing check is pushed first, then the fix**. Each is a separate commit with its own CI run, so the history shows the transition.

| Finding | Red (failing run) | Green (passing run) | Root cause fixed |
|---|---|---|---|
| **F22** production can't boot | [36547094896](https://github.com/yond44/yonda-quality-net/actions/runs/36547094896): *the CI found it by itself on its first run* | [36548570736](https://github.com/yond44/yonda-quality-net/actions/runs/36548570736) | Removed Active Job config for a framework never loaded; the autoloader no longer also manages boot-time WebSocket middleware |
| **F1** login picks any company | [36548723182](https://github.com/yond44/yonda-quality-net/actions/runs/36548723182): 4/4 failing | [36549163695](https://github.com/yond44/yonda-quality-net/actions/runs/36549163695) | Users belong to one organization, and the token scheme comes only from it |
| **F2** one company reads or changes another's data | [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611): 4/5 failing | [36555110517](https://github.com/yond44/yonda-quality-net/actions/runs/36555110517) (F2 no longer flagged) | Portfolios and portfolio skills are looked up through the caller's company (via their session), never by bare ID |
| **F23** a valid token opens another company *(new finding, found while fixing F2)* | [36555404757](https://github.com/yond44/yonda-quality-net/actions/runs/36555404757): 3/4 failing | [36555539895](https://github.com/yond44/yonda-quality-net/actions/runs/36555539895) (F23 no longer flagged) | The verified token's company must equal the request's company, checked once where every logged-in request passes |
| **F3** invite link opens a 404 | [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611): 1/2 failing | [36557839764](https://github.com/yond44/yonda-quality-net/actions/runs/36557839764) (F3 no longer flagged) | Invite links use a new `WEB_BASE_URL` (the web app), and production refuses to boot without it |
| **F24** internet check blocks good connections *(found in manual testing)* | [36563351392](https://github.com/yond44/yonda-quality-net/actions/runs/36563351392): 5/6 failing (web tests) | [36563510380](https://github.com/yond44/yonda-quality-net/actions/runs/36563510380) (web check green) | Limits derived from the voice audio; upload and ping measured on our own backend, one at a time; a failed measurement is "couldn't measure", never an invented number |
| **F4** removed skills stay in the database | [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611): 2/2 failing | [36565150346](https://github.com/yond44/yonda-quality-net/actions/runs/36565150346) (F4 no longer flagged) | The edit endpoints treat the sent list as complete: skills left out of it are deleted in the same save |
| **F5** an unreadable AI level is saved as L1 | [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611): 2/3 failing; the new regeneration check: [36566738655](https://github.com/yond44/yonda-quality-net/actions/runs/36566738655) (3/4 failing) | [36568044569](https://github.com/yond44/yonda-quality-net/actions/runs/36568044569) (F5 no longer flagged) | The level is read strictly (3, "3", "L3") or generation fails loudly; all skills are checked first, then saved in one transaction |
| **F25** a dropped connection looks like a finished interview; an abandoned one stays "Live" *(found in manual testing)* | [36660161292](https://github.com/yond44/yonda-quality-net/actions/runs/36660161292): 2 web + 2 API checks failing | [36660629180](https://github.com/yond44/yonda-quality-net/actions/runs/36660629180) (F25 no longer flagged; web check green) | Failures get their own screens (never "complete"); an interview more than 15 minutes past its time limit is ended as `error` when read |
| **F6** interviews recorded "all covered" without checking | [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611): 2/3 failing | [36663487852](https://github.com/yond44/yonda-quality-net/actions/runs/36663487852) (F6 no longer flagged) | `all_covered` is checked where every ending is recorded (otherwise `partial_coverage`); a never-started interview can't be ended |
| **F7** results depend on the AI spelling skill names exactly | [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611): 3/3 failing | [36665937396](https://github.com/yond44/yonda-quality-net/actions/runs/36665937396) (F7 no longer flagged) | Each skill gets a unique reference in the prompt; answers are mapped back through it and stored under the configured name; a missing skill fails loudly |
| **F26** the AI never opens the interview; the candidate is stuck muted *(found in manual testing)* | [36665966050](https://github.com/yond44/yonda-quality-net/actions/runs/36665966050): 2/3 failing | [36665991784](https://github.com/yond44/yonda-quality-net/actions/runs/36665991784) (F26 no longer flagged) | A watchdog asks again after 10 s, then gives the turn back to the candidate; the start message is signed |
| **F27** the AI reads its hidden notes aloud, and the record hides it *(found in manual testing)* | [36666018100](https://github.com/yond44/yonda-quality-net/actions/runs/36666018100): 2/3 failing | [36666047243](https://github.com/yond44/yonda-quality-net/actions/runs/36666047243) (F27 no longer flagged) | Notes are sent under the tag the AI is told to keep silent; a slip is marked in the recruiter's transcript |
| **F8** "Required" column always empty | [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611): 3/3 failing | [#1](https://github.com/yond44/yonda-quality-net/pull/1) [36667125182](https://github.com/yond44/yonda-quality-net/actions/runs/36667125182) (all tests green) and `main` after the merge [36667342497](https://github.com/yond44/yonda-quality-net/actions/runs/36667342497) | The comparison also carries `required_level` and `is_override`; old reports get `required_level` filled in when read |
| **F25 follow-up** a server error while opening the interview shown as "Interview Complete" | [#3](https://github.com/yond44/yonda-quality-net/pull/3) [36668038365](https://github.com/yond44/yonda-quality-net/actions/runs/36668038365): the new web and API checks failing | [#3](https://github.com/yond44/yonda-quality-net/pull/3) [36668170107](https://github.com/yond44/yonda-quality-net/actions/runs/36668170107) | The server reports an already-ended session as ended; any other failure shows "Something went wrong" |
| **F28** a skill with no evidence gets a level *(found in manual review, after v1.0.0)* | [36812383367](https://github.com/yond44/yonda-quality-net/actions/runs/36812383367): API 4/5 + 3 web checks failing | [36812959237](https://github.com/yond44/yonda-quality-net/actions/runs/36812959237) (F28 no longer flagged) | No evidence means "not assessed" (no level): never-answered interviews skip the AI; the AI may answer `not_assessed`; fit/gap and the page say so |
| **F30** portfolios fail when the AI copies the coverage id *(found in live testing, after v1.0.1)* | [36815953972](https://github.com/yond44/yonda-quality-net/actions/runs/36815953972): 2/2 failing | [36816139679](https://github.com/yond44/yonda-quality-net/actions/runs/36816139679) (F30 no longer flagged) | One id per skill across the prompt: the coverage data uses the same `S12` reference as the skill list |
| **F31** a candidate who ends the interview is told "Connection lost" *(found in the end-to-end browser test; an F25 regression)* | [36827787574](https://github.com/yond44/yonda-quality-net/actions/runs/36827787574): 3 web checks failing (the F25 checks green) | [36827803414](https://github.com/yond44/yonda-quality-net/actions/runs/36827803414) (F31 no longer flagged) | The page marks a close it asked for; the close handler ignores it instead of reporting a lost connection |
| **F32** the PDF export fails after an override *(found in the end-to-end test)* | [36827823866](https://github.com/yond44/yonda-quality-net/actions/runs/36827823866): API 2/3 failing with 500 | [36827849551](https://github.com/yond44/yonda-quality-net/actions/runs/36827849551) (F32 no longer flagged) | A Unicode TrueType font (DejaVu Sans) instead of PDF's built-in fonts |
| **F33** a level click changes another skill *(found in the end-to-end browser test)* | [36827870194](https://github.com/yond44/yonda-quality-net/actions/runs/36827870194): 2 web checks failing | [36827898429](https://github.com/yond44/yonda-quality-net/actions/runs/36827898429) (all checks green) | Each level picker gets its own id prefix (`useId`) |
| **F35** the lists only show the newest 20 *(found in the soak test)* | [36970071541](https://github.com/yond44/yonda-quality-net/actions/runs/36970071541): 3 web checks failing | [36970269123](https://github.com/yond44/yonda-quality-net/actions/runs/36970269123) (F35 no longer flagged) | Page controls on both lists; the fit/gap choice loads every vacancy |

For F1, the spec's assertions are unchanged between red and green. Only its setup line changed (it no longer needs to handle the missing column), and the commit message says so.

---

## Fix notes: what each fix changed, and why

One entry per fix, in the order they were fixed. Each says what was red, the root cause, every file changed (with links), the code before → after, why it was fixed this way, and the green run. Snippets are shortened to the lines that matter.

### F22: the backend couldn't start in production (P0)

- **Red:** [36547094896](https://github.com/yond44/yonda-quality-net/actions/runs/36547094896), the CI's very first run. "API boots in production mode" crashed with `undefined method 'active_job'`.
- **Root cause:** two problems that only appear when production loads the app.
  1. The production settings configured **Active Job**, a Rails feature this app never loads (it uses Sidekiq workers directly).
  2. Production loads every file at startup and checks that each file name matches its class name. The WebSocket files, like `audio_websocket_middleware.rb`, hold classes spelled `AudioWebSocketMiddleware` (capital S), so the check failed.

  Development loads files only when they're used, so neither problem ever showed up there.
- **Files changed:**
  - [`production.rb:37-39`](../api/config/environments/production.rb#L37-L39)
  - [`application.rb:32-36`](../api/config/application.rb#L32-L36)
- **Before → after:**
  ```ruby
  # production.rb — BEFORE
  config.active_job.queue_adapter = :sidekiq
  # AFTER: removed, with a comment saying the app doesn't load Active Job

  # application.rb — BEFORE: app/channels was in the autoload list
  #{config.root}/app/channels
  # AFTER: the autoloader ignores that folder
  Rails.autoloaders.main.ignore(config.root.join('app/channels'))
  ```
- **Why this way:** those files are already loaded by hand at boot ([`websocket.rb:11-12`](../api/config/initializers/websocket.rb#L11-L12)), so the autoloader was managing them a second time. Renaming the classes instead would have touched the live-interview code, which the net can't test.
- **Green:** [36548570736](https://github.com/yond44/yonda-quality-net/actions/runs/36548570736).

### F1: login let any user pick any company (P1)

- **Red:** [36548723182](https://github.com/yond44/yonda-quality-net/actions/runs/36548723182), 4/4 failing.
- **Root cause:** users had no company. Login took the company from a header the client sends (`X-Tenant-Scheme`), or else from "the first row" of the organizations table.
- **Files changed:**
  - **Added:** [`20260929000000_add_organization_to_users.rb`](../api/db/migrate/20260929000000_add_organization_to_users.rb), which adds the `users.organization_id` column
  - [`user.rb:8`](../api/app/models/user.rb#L8)
  - [`authentication_controller.rb:16-21`](../api/app/controllers/api/v1/authentication_controller.rb#L16-L21)
  - [`schema.rb`](../api/db/schema.rb), regenerated
- **Before → after:**
  ```ruby
  # BEFORE: the company comes from the client, or "whatever row is first"
  scheme = request.headers['X-Tenant-Scheme'].presence ||
           ActiveRecord::Base.connection.select_value('SELECT scheme FROM organizations LIMIT 1') || 'test-corp'
  token  = JsonWebToken.encode({ user_id: user.id, role: user.role, scheme: })

  # AFTER: the company comes only from the user's own record
  organization = user.organization
  return json_error('Account is not assigned to an organization', :unauthorized) unless organization
  token = JsonWebToken.encode({ user_id: user.id, role: user.role, scheme: organization.scheme })
  ```
- **Why this way:**
  - **Why not just `user_id`?** The token already had the user's ID. What was missing was the link between a person and their company. All data is labelled by company (`tenant_id`), not by person. Filtering by user would stop colleagues from seeing each other's assessments, which is a redesign, not a fix.
  - **Why no foreign key?** `organizations` lives in the `public` schema and is owned by the upstream platform. The existing `tenant_id` columns follow the same convention.
  - **Assumption:** one user belongs to one company (audit M2).
- **Green:** [36549163695](https://github.com/yond44/yonda-quality-net/actions/runs/36549163695).

### F2: one company could read and change another's candidate reports (P1)

- **Red:** [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611), 4/5 failing.
- **Root cause:** portfolios and portfolio skills have no `tenant_id` column, so the automatic company filter (`TenantScoped`) never applied to them. The controllers loaded them by ID number alone.
- **Files changed:**
  - [`portfolio.rb:18`](../api/app/models/portfolio.rb#L18)
  - [`portfolio_skill.rb:15`](../api/app/models/portfolio_skill.rb#L15)
  - [`portfolios_controller.rb:146-148`](../api/app/controllers/api/v1/portfolios_controller.rb#L146-L148): the new finder, used at [`:82`](../api/app/controllers/api/v1/portfolios_controller.rb#L82), [`:104`](../api/app/controllers/api/v1/portfolios_controller.rb#L104), [`:130`](../api/app/controllers/api/v1/portfolios_controller.rb#L130) and [`:162`](../api/app/controllers/api/v1/portfolios_controller.rb#L162)
  - [`portfolio_skills_controller.rb:51`](../api/app/controllers/api/v1/portfolio_skills_controller.rb#L51)
- **Before → after:**
  ```ruby
  # BEFORE: any company, any ID
  portfolio        = Portfolio.find(params[:id])
  @portfolio_skill = PortfolioSkill.joins(:portfolio).find(params[:id])

  # AFTER: only records whose interview belongs to the caller's company
  scope :for_tenant, ->(tenant_id) { where(session_id: Session.unscoped.where(tenant_id:).select(:id)) }
  portfolio        = Portfolio.for_tenant(current_tenant_id).find(params[:id])
  @portfolio_skill = PortfolioSkill.for_tenant(current_tenant_id).find(params[:id])
  ```
  In JavaScript terms: `Portfolio.findOne({ id, sessionId: { in: sessionIdsOf(myCompany) } })`. Another company's record now answers 404, as if it didn't exist.
- **Why this way, not a `tenant_id` column:** a column would need a data backfill. It would also change how the background jobs and the live-interview WebSocket (which the net can't test) create these records. The scoped lookup closes the hole with a small, tested change. The column is recorded in the audit as the better long-term design.
- **Green:** [36555110517](https://github.com/yond44/yonda-quality-net/actions/runs/36555110517).

### F23: a valid login from one company worked inside any other company (P1, found while fixing F2)

- **Red:** [36555404757](https://github.com/yond44/yonda-quality-net/actions/runs/36555404757), 3/4 failing.
- **Root cause:** the request's company is picked by the tenant middleware from **unverified** input, and it only reads the token if the header starts with `Bearer `. The login check accepts the token in any form. Nothing compared the two, so `Authorization: Token <A's token>` plus `X-Tenant-Scheme: company-b` let a company A user work inside company B.
- **Files changed:**
  - [`application_controller.rb:54-66`](../api/app/controllers/application_controller.rb#L54-L66)
- **Before → after:**
  ```ruby
  # BEFORE: the token is checked, but not which company it belongs to
  result = AuthorizeApiRequest.new(request.headers, roles).call
  Current.user = result[:user]

  # AFTER: the token's company must be the request's company
  result = AuthorizeApiRequest.new(request.headers, roles).call
  unless result[:user].scheme.present? && result[:user].scheme == current_organization&.scheme
    raise(ExceptionHandler::InvalidToken, Message.invalid_token)   # → 401
  end
  Current.user = result[:user]
  ```
- **Why this way:** this is the one place every logged-in request passes, and the first place that knows the **verified** user. A single check closes every variant at once (any header form, the tenant header, the `Referer`), instead of patching each way in. The middleware can't do this check, because it runs before the token is verified.
- **Green:** [36555539895](https://github.com/yond44/yonda-quality-net/actions/runs/36555539895).

### F3: invite links sent candidates to a 404 page (P1)

- **Red:** [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611), 1/2 failing.
- **Root cause:** the link used `APP_BASE_URL`, the backend's address, but `/interview/:token` is a page of the **web app**.
- **Files changed:**
  - [`session.rb:28-33`](../api/app/models/session.rb#L28-L33)
  - [`production.rb:25-27`](../api/config/environments/production.rb#L25-L27)
  - The setting renamed in [`application.yml.sample:21`](../api/config/application.yml.sample#L21), [`README.md:30`](../api/README.md#L30), [`configmap.yaml:20`](../api/k8s/configmap.yaml#L20), and [`ci.yml:57`](../.github/workflows/ci.yml#L57) / [`:93`](../.github/workflows/ci.yml#L93)
- **Before → after:**
  ```ruby
  # BEFORE: the backend's address
  base = ENV.fetch('APP_BASE_URL', 'http://localhost:3001')
  # AFTER: the web app's address
  base = ENV.fetch('WEB_BASE_URL', 'http://localhost:5173').chomp('/')

  # production.rb — NEW: refuse to start without it
  raise "WEB_BASE_URL must be set in production (the web app's public address)" if ENV["WEB_BASE_URL"].blank?
  ```
- **Why this way:**
  - **A new setting, not a new value for `APP_BASE_URL`:** that setting was documented as the backend's address. Reusing a setting for a different meaning is how F3 happened in the first place.
  - **Refusing to start:** otherwise a missing setting would silently send every candidate to `localhost`, the same failure in a new form.
- **Green:** [36557839764](https://github.com/yond44/yonda-quality-net/actions/runs/36557839764).

### F24: the internet check blocked candidates with good connections (P1, found in manual testing)

- **Red:** [36563351392](https://github.com/yond44/yonda-quality-net/actions/runs/36563351392), 5/6 web tests failing.
- **Root cause:** the check wasn't tied to what it protects.
  - Its limits were 15–20 times what the voice interview uses.
  - Upload was timed against public echo servers abroad.
  - All measurements ran at the same time, competing for the connection.
  - A failed measurement turned into an invented number that could pass or fail a candidate.
- **Files changed:**
  - **Added:** [`internetSpeedTest.test.ts`](../web/src/utils/internetSpeedTest.test.ts), the web app's first test (Vitest)
  - [`internetSpeedTest.ts`](../web/src/utils/internetSpeedTest.ts), rewritten. The key parts: limits [`:30-34`](../web/src/utils/internetSpeedTest.ts#L30-L34), targets [`:38-39`](../web/src/utils/internetSpeedTest.ts#L38-L39), upload [`:79-90`](../web/src/utils/internetSpeedTest.ts#L79-L90), order and pass rule [`:111-127`](../web/src/utils/internetSpeedTest.ts#L111-L127)
  - [`HardwareCheck.tsx:243-247`](../web/src/components/HardwareCheck.tsx#L243-L247): the "couldn't measure" message
  - [`package.json:10`](../web/package.json#L10) (`npm test`) and [`ci.yml:124-128`](../.github/workflows/ci.yml#L124-L128) (CI runs the web tests)
- **Before → after:**
  ```ts
  // Limits — BEFORE: 8 Mbps down / 4 Mbps up.  AFTER: 1.5 / 1 (voice ≈ 0.38 down / 0.26 up, ×4 headroom)

  // Upload target
  // BEFORE: "https://httpbin.org/post", "https://postman-echo.com/post"
  // AFTER:  `${API_BASE_URL}/speed_test`  (our own backend, where the interview audio goes)

  // Order
  // BEFORE: await Promise.all([download(), upload(), ping()])
  // AFTER:  ping, then download, then upload, one at a time

  // Failures
  // BEFORE: return 0.5;   // invented: exactly 4 Mbps, so it PASSES
  // AFTER:  return res.ok ? toMbps(bytes, ms) : null;   // null = "couldn't measure"
  const passed = measured && download >= min && upload >= min && ping <= max;
  ```
- **Why this way:** the check should answer one question: *can this connection carry the interview?* So it measures the interview's own path, with limits taken from the interview's own audio format. The limits are an assumption, because no spec defines them (audit M10).
- **Green:** [36563510380](https://github.com/yond44/yonda-quality-net/actions/runs/36563510380).

### F4: removing a skill in the edit form didn't remove it (P1)

- **Red:** [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611), 2/2 failing.
- **Root cause:** the website sends the list of skills to **keep**. The backend's nested-attributes feature only deletes a skill marked `_destroy: true`, and the website never sends that marker. So a skill left out of the list silently stayed: the screen showed it gone, but the database kept it.
- **Files changed:**
  - [`application_controller.rb:80-93`](../api/app/controllers/application_controller.rb#L80-L93): a new shared helper
  - [`assessments_controller.rb:42-44`](../api/app/controllers/api/v1/assessments_controller.rb#L42-L44) and [`vacancies_controller.rb:39-41`](../api/app/controllers/api/v1/vacancies_controller.rb#L39-L41): both edit endpoints use it
  - [`f4_removed_skills_spec.rb:39-60`](../api/spec/requests/f4_removed_skills_spec.rb#L39-L60): 2 controls added. The original checks are unchanged.
- **Before → after:**
  ```ruby
  # BEFORE: the list goes straight in; anything missing from it is left alone
  if @assessment.update(assessment_params)

  # AFTER: every existing skill missing from the list is marked for deletion first
  attributes = with_left_out_rows_destroyed(assessment_params, :assessment_skills_attributes,
                                            @assessment.assessment_skills.pluck(:id))
  if @assessment.update(attributes)

  # the helper, in short:
  kept_ids = rows.filter_map { |row| row[:id].presence&.to_s }
  left_out = existing_ids.map(&:to_s) - kept_ids
  permitted.merge(key => rows + left_out.map { |id| { id:, _destroy: true } })
  ```
  In JavaScript terms: `const removed = existingIds.filter(id => !sentIds.includes(id)); rows.push(...removed.map(id => ({ id, _destroy: true })))`.
- **Why this way:**
  - **Backend, not website:** "send the list I want" is the natural contract, and the backend was the side misreading it. The red test sends the website's real payload, so changing the website instead would have meant changing the test.
  - **Reusing Rails' own `_destroy` marker** means the deletions happen inside Rails' normal save, in one transaction. A rejected save deletes nothing, and one of the new controls proves it.
  - **Only when a list is sent.** An edit that only renames the assessment keeps every skill; the other new control proves that.
- **Green:** [36565150346](https://github.com/yond44/yonda-quality-net/actions/runs/36565150346).

### F5: an AI level the code couldn't read was saved as L1 (P1)

- **Red:** [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611), 2/3 failing. The new regeneration check failed on its own in [36566738655](https://github.com/yond44/yonda-quality-net/actions/runs/36566738655) (3/4 failing).
- **Root cause:** the level was saved with `skill_data['level'].to_i.clamp(1, 5)`. In Ruby, `"L3".to_i` and `nil.to_i` are both `0`, and clamping 0 into 1–5 gives **1**. The portfolio was then marked complete, so a candidate who was really L3 showed as L1, and fit/gap reported a fake gap. Separately, the old skills were deleted **before** the new ones were saved one by one, so a bad answer part-way through left a half-saved portfolio.
- **Files changed:**
  - [`generator.rb:8-11`](../api/app/services/portfolios/generator.rb#L8-L11): the error class and the accepted text form
  - [`generator.rb:158-224`](../api/app/services/portfolios/generator.rb#L158-L224): `save_skills`, the new `skill_row` and `parse_level`
  - [`f5_level_parsing_spec.rb:39-52`](../api/spec/services/f5_level_parsing_spec.rb#L39-L52): the new regeneration check, pushed before the fix
- **Before → after:**
  ```ruby
  # BEFORE: unreadable becomes L1, too high is silently capped at L5
  ai_level: skill_data['level'].to_i.clamp(1, 5),
  # ...and the old skills are deleted first, then new ones are saved one by one
  portfolio.portfolio_skills.destroy_all
  (data['configured_skills'] || []).each { |s| portfolio.portfolio_skills.create!(...) }

  # AFTER: read strictly, or stop with a clear reason
  level = case raw
          when Integer then raw
          when Float   then raw.to_i if raw == raw.floor
          when String  then raw[LEVEL_TEXT, 1]&.to_i     # "3", "L3"
          end
  return level if level&.between?(1, 5)
  raise UnreadableLevel, "Unreadable level for '#{skill_data['skill_label']}': #{raw.inspect}"

  # ...and everything is checked first, then replaced in one transaction
  rows = configured.map { ... skill_row ... } + discovered.map { ... skill_row ... }
  PortfolioSkill.transaction do
    portfolio.portfolio_skills.destroy_all
    rows.each { |row| portfolio.portfolio_skills.create!(row) }
  end
  ```
  In JavaScript terms, the old line was `Math.min(5, Math.max(1, parseInt(level) || 0))`. The new one is "match `^L?[1-5]$`, or throw".
- **Why this way:**
  - **Fail, don't guess.** A wrong grade on a real candidate is worse than a visible failure. The job retries automatically, and the recruiter can press Regenerate.
  - **Accept `"L3"`:** it's unambiguous, and the website's own types describe levels that way, so rejecting it would cause needless failures.
  - **Check first, then save in one transaction:** a regeneration must never destroy a good earlier result on its way to failing.
- **Green:** [36568044569](https://github.com/yond44/yonda-quality-net/actions/runs/36568044569) (F5 no longer flagged).

### F25: a dropped connection looked like a finished interview, and stayed "Live" forever (P1, found in manual testing)

- **Red:** [36660161292](https://github.com/yond44/yonda-quality-net/actions/runs/36660161292). 2 web checks and 2 API checks failed; each has a control that passed.
- **Root cause:** the code treated "I don't know what happened" as "it finished".
  - When reconnecting failed, the page reported the interview as **complete**.
  - When the page couldn't load, it showed the **"Interview Complete"** screen.
  - The only check that ends an overdue interview runs **inside** the live connection, so once the candidate was gone nothing ever ended it, and the recruiter saw it as **"Live"** forever.
- **Files changed:**
  - [`types/index.ts:185-189`](../web/src/types/index.ts#L185-L189): three new page states for failures
  - [`useAudioWebSocket.ts:130-131`](../web/src/hooks/useAudioWebSocket.ts#L130-L131): a failed reconnect is "connection lost"
  - [`InterviewPage.tsx:51-52`](../web/src/pages/interview/InterviewPage.tsx#L51-L52): a failed load is an error, and a 404 means an invalid link
  - [`InterviewPage.tsx:245-275`](../web/src/pages/interview/InterviewPage.tsx#L245-L275): the three failure screens
  - [`session.rb:25`](../api/app/models/session.rb#L25) and [`:38-55`](../api/app/models/session.rb#L38-L55): the "abandoned" rule
  - [`end_handler.rb:14-34`](../api/app/services/sessions/end_handler.rb#L14-L34): an optional real end time
  - [`sessions_controller.rb:14`](../api/app/controllers/api/v1/sessions_controller.rb#L14), [`:139`](../api/app/controllers/api/v1/sessions_controller.rb#L139), [`:161`](../api/app/controllers/api/v1/sessions_controller.rb#L161) and [`assessments_controller.rb:81`](../api/app/controllers/api/v1/assessments_controller.rb#L81): applied wherever a session is shown
- **Before → after:**
  ```ts
  // useAudioWebSocket.ts: reconnects exhausted
  // BEFORE
  onStateChange("complete");
  // AFTER
  onStateChange("connection_lost");   // "Connection lost. Your interview has not ended" + Reconnect

  // InterviewPage.tsx: the invite link can't be loaded
  // BEFORE
  .catch(() => setInterviewState("complete"));
  // AFTER
  .catch((err) => setInterviewState(err?.response?.status === 404 ? "invalid_link" : "load_error"));
  ```
  ```ruby
  # session.rb - NEW: an interview can't still be live 15 minutes past its time limit
  def abandoned?(now = Time.current)
    return false unless active? && started_at
    time_limit = Assessment.unscoped.where(id: assessment_id).pick(:time_limit_min)
    time_limit.present? && now > started_at + time_limit.minutes + ABANDONED_AFTER_LIMIT
  end

  def end_if_abandoned!
    return self unless abandoned?
    last_activity = transcript_turns.maximum(:created_at) || started_at
    Sessions::EndHandler.new(self).call(reason: 'error', ended_at: last_activity)
    self
  end

  # sessions_controller.rb - BEFORE / AFTER
  @session = Session.find(params[:id])
  @session = Session.find(params[:id]).end_if_abandoned!
  ```
- **Why this way:**
  - **Separate failure screens, not one generic error:** "connection lost" (reconnect works), "couldn't load" (retry works) and "invalid link" (retry won't help) each need a different action from the candidate.
  - **The interview stays resumable within its time limit:** a dropped Wi-Fi connection shouldn't cost a candidate their interview.
  - **Ended when read, not by a timer:** there is no job scheduler in the project, and every place a recruiter or candidate could see a stale "Live" now checks first. Disclosed as a limitation.
  - **Reason `error`, not a new one:** the website already highlights `error` endings to the recruiter, so no new status was needed.
- **Green:** [36660629180](https://github.com/yond44/yonda-quality-net/actions/runs/36660629180) (F25 no longer flagged; web check green).

### F6: interviews were recorded as "all skills covered" without checking (P1)

- **Red:** [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611), 2/3 failing.
- **Root cause:** `all_covered` is a claim about the interview's data, but nothing checked it. `audio_complete` wrote it for any interview, even one that never started. And when the AI said a goodbye phrase early, the server **forced** "all covered", so a normal interview cut short was recorded as complete. Reproduced both ways: by calling the endpoint, and in a real interview (session 7), where the only skill was still `not_yet`.
- **Files changed:**
  - **Added:** [`20260930000000_add_partial_coverage_end_reason.rb`](../api/db/migrate/20260930000000_add_partial_coverage_end_reason.rb), the new `partial_coverage` end reason (a database enum value); [`schema.rb`](../api/db/schema.rb) regenerated
  - [`session.rb:7-8`](../api/app/models/session.rb#L7-L8): the reason list
  - [`end_handler.rb:27-30`](../api/app/services/sessions/end_handler.rb#L27-L30): the check, where every ending is recorded
  - [`sessions_controller.rb:124-129`](../api/app/controllers/api/v1/sessions_controller.rb#L124-L129): a never-started interview is refused
- **Before → after:**
  ```ruby
  # sessions_controller.rb, audio_complete
  # BEFORE: any interview, started or not, is ended as "all covered"
  Sessions::EndHandler.new(session).call(reason: 'all_covered')

  # AFTER: only a running interview can finish
  return json_error("Interview has not started", :conflict) unless session.active? && session.started_at
  Sessions::EndHandler.new(session).call(reason: 'all_covered')

  # end_handler.rb — NEW: "all covered" must be true, whoever claims it
  reason = 'partial_coverage' if reason.to_s == 'all_covered' && !Coverage::MapInjector.new(@session).all_covered?
  ```
  In JavaScript terms: `if (reason === "all_covered" && !coverage.allCovered()) reason = "partial_coverage";`
- **Why this way:**
  - **The check sits where every ending is recorded,** not in one endpoint. That covers the endpoint, the AI's early goodbye and the server's own timeout, with one line.
  - **It reuses the live interview's own "all covered" rule,** so there's a single definition of "covered".
  - **The interview still always ends.** A code comment says an earlier coverage check in the endpoint stalled auto-end. Here only the recorded reason changes, never whether the interview ends.
  - **A new reason instead of reusing one:** none of the existing reasons (`manual_candidate`, `manual_assessor`, `time_ceiling`, `error`) says "ended before every skill was covered". The website only special-cases `error`, so it shows the new reason like any normal ending.
- **Green:** [36663487852](https://github.com/yond44/yonda-quality-net/actions/runs/36663487852) (F6 no longer flagged).

### F7: results depended on the AI spelling skill names exactly (P1)

- **Red:** [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611), 3/3 failing.
- **Root cause:** the portfolio stored **whatever skill name the AI wrote back**, and fit/gap matches skills by name. Many skills have no catalogue ID, so the prompt labelled them all `custom`, and the AI's answer couldn't be tied back to a configured skill. A reworded name became "not assessed", and a skill the AI left out silently disappeared.
- **Files changed:**
  - [`generator.rb:9`](../api/app/services/portfolios/generator.rb#L9): a new error for mismatched answers
  - [`generator.rb:107-108`](../api/app/services/portfolios/generator.rb#L107-L108): the prompt tells the AI to copy each skill's reference back
  - [`generator.rb:137`](../api/app/services/portfolios/generator.rb#L137): each skill's reference in the prompt
  - [`generator.rb:163`](../api/app/services/portfolios/generator.rb#L163) and [`:174-197`](../api/app/services/portfolios/generator.rb#L174-L197): `skill_ref` and `configured_rows`, which map the answers back
  - [`generator.rb:199-202`](../api/app/services/portfolios/generator.rb#L199-L202): the stored name and ID come from the configuration
- **Before → after:**
  ```ruby
  # The prompt — BEFORE: skills without a catalogue ID are all "(custom)"
  lines << "SKILL: #{skill.skill_label} (#{skill.skill_id || 'custom'})"
  # AFTER: every skill has its own reference
  lines << "SKILL: #{skill.skill_label} (#{skill_ref(skill)})"      # e.g. "SKILL: Negotiation Skills (S12)"

  # Saving — BEFORE: store what the AI wrote
  skill_id:    skill_data['skill_id'],
  skill_label: skill_data['skill_label'],
  # AFTER: find the configured skill through the reference, store ITS name and ID
  skill = configured[skill_data['skill_id'].to_s.strip]
  raise SkillMismatch, "AI answered for an unknown skill: ..." unless skill
  ...
  missing = configured.except(*answered.keys).values.map(&:skill_label)
  raise SkillMismatch, "AI's answer is missing configured skills: #{missing.join(', ')}" if missing.any?
  ```
  In JavaScript terms: `const skill = configuredByRef[answer.skill_id]; if (!skill) throw ...; save({ label: skill.label, id: skill.id })`.
- **Why this way:**
  - **A reference we control, not a name the AI controls.** The AI only has to copy a short code, which is far more reliable than reproducing a long name exactly, and nothing depends on its wording any more.
  - **Row IDs, not catalogue IDs:** custom skills have no catalogue ID, and every skill has a row ID.
  - **Fail loudly on a missing skill:** a silently missing skill looks like "not assessed" to the recruiter, which is wrong data. A visible failure retries and can be regenerated.
- **Green:** [36665937396](https://github.com/yond44/yonda-quality-net/actions/runs/36665937396) (F7 no longer flagged).

### F26: the AI sometimes never opened the interview, and the candidate was stuck muted (P1, found in manual testing)

- **Red:** [36665966050](https://github.com/yond44/yonda-quality-net/actions/runs/36665966050), 2/3 failing.
- **Root cause:** the server asked the AI to open the interview **once**, and treated the AI as speaking (with the candidate's microphone muted) until it answered. Nothing checked that an answer ever came. When it didn't, the interview hung forever. The start message was also bracketed but unsigned, which the AI's own instructions describe as an injection attempt.
- **Files changed:**
  - [`live_client.rb:14-19`](../api/app/clients/gemini/live_client.rb#L14-L19): the timeout, the number of tries, and the default text
  - [`live_client.rb:43`](../api/app/clients/gemini/live_client.rb#L43): a new `on_opening_unanswered` callback
  - [`live_client.rb:107-115`](../api/app/clients/gemini/live_client.rb#L107-L115): `trigger_opening` starts the watchdog
  - [`live_client.rb:147-174`](../api/app/clients/gemini/live_client.rb#L147-L174): `send_opening`, `check_opening_answered` and `opening_answered!`
  - [`live_client.rb:406`](../api/app/clients/gemini/live_client.rb#L406): the AI's first audio marks the opening as answered
  - [`live_client.rb:128`](../api/app/clients/gemini/live_client.rb#L128) and [`:139`](../api/app/clients/gemini/live_client.rb#L139): the watchdog stops when the client closes
  - [`audio_websocket_middleware.rb:23-26`](../api/app/channels/audio_websocket_middleware.rb#L23-L26): the signed start message
  - [`audio_websocket_middleware.rb:155`](../api/app/channels/audio_websocket_middleware.rb#L155), [`:362`](../api/app/channels/audio_websocket_middleware.rb#L362) and [`:372-378`](../api/app/channels/audio_websocket_middleware.rb#L372-L378): the signed message is used, and the turn is given back
- **Before → after:**
  ```ruby
  # live_client.rb — BEFORE: sent once, never checked
  def trigger_opening
    @ws.send({ realtimeInput: { text: '[Start the interview. ...]' } }.to_json)
  end

  # AFTER: sent, watched, sent again, then reported
  def send_opening
    @opening_attempts += 1
    @opening_pending = true
    @ws.send({ realtimeInput: { text: @opening_text } }.to_json)
    @opening_timer = EM::Timer.new(OPENING_REPLY_TIMEOUT) { check_opening_answered }
  end

  def check_opening_answered
    return unless @opening_pending && @connected && !@superseded
    if @opening_attempts < OPENING_ATTEMPTS then send_opening          # ask again
    else @opening_pending = false; @on_opening_unanswered&.call end    # give up, report it
  end

  # audio_websocket_middleware.rb — NEW: give the candidate the turn
  def handle_opening_unanswered(browser_ws, state, session)
    state.model_speaking = false
    send_json(browser_ws, type: 'speaker_changed', speaker: 'candidate')
  end
  ```
  In JavaScript terms: `send(start); timer = setTimeout(() => answered ? null : (tries < 2 ? send(start) : giveTurnToCandidate()), 10_000)`.
- **Why this way:**
  - **A watchdog, not only a better message.** The real cause isn't proven, and an AI can stay silent for other reasons too (an outage, a slow start). A timeout protects the candidate whatever the cause.
  - **Retry once, then hand over.** A second try covers a one-off miss; giving the candidate the turn after that lets their voice restart the conversation, instead of making them wait longer.
  - **The check sits in the AI client,** where the AI's first audio is seen, so it can be tested without a live connection.
- **Green:** [36665991784](https://github.com/yond44/yonda-quality-net/actions/runs/36665991784) (F26 no longer flagged).

### F27: the AI could read its hidden notes aloud, and the transcript hid it (P2, found in manual testing)

- **Red:** [36666018100](https://github.com/yond44/yonda-quality-net/actions/runs/36666018100), 2/3 failing.
- **Root cause:** two mismatches.
  - The AI's instructions say to keep silent any message that starts with `[COVERAGE MAP`, but the app sent its notes as `[COVERAGE_MAP]`, so the rule described a tag the AI never received.
  - A text filter then removed any echo of the notes from the transcript **without a trace**, so the recruiter couldn't know the candidate might have heard them.
- **Files changed:**
  - [`map_injector.rb:42-44`](../api/app/services/coverage/map_injector.rb#L42-L44): the tag the notes are sent under
  - [`audio_websocket_middleware.rb:235-254`](../api/app/channels/audio_websocket_middleware.rb#L235-L254): the recruiter's transcript and the candidate's live transcript get different text
  - [`audio_websocket_middleware.rb:283-294`](../api/app/channels/audio_websocket_middleware.rb#L283-L294): `recruiter_transcript_text`, the marker
- **Before → after:**
  ```ruby
  # map_injector.rb
  # BEFORE: a tag the AI's instructions never name
  "[COVERAGE_MAP]\n#{payload.to_json}\n[/COVERAGE_MAP]"
  # AFTER: the tag the instructions tell the AI to keep silent
  "[COVERAGE MAP]\n#{payload.to_json}\n[/COVERAGE MAP]"

  # audio_websocket_middleware.rb
  # BEFORE: the echo is removed and nobody knows it happened
  text = sanitize_output_transcription(text)
  save_transcript_turn(session, turn_number, 'ai', text)
  # AFTER: the recruiter's copy says what happened; the candidate's page gets the clean words
  recruiter_text = recruiter_transcript_text(text)   # adds the marker if anything was removed
  text = sanitize_output_transcription(text)
  save_transcript_turn(session, turn_number, 'ai', recruiter_text)
  ```
- **Why this way:**
  - **Fix the sender, not the instructions.** Every assessment stores its compiled instructions. Changing the tag the app sends makes all of them correct at once; changing the wording would only reach assessments that are recompiled.
  - **A contract test, not a copy of the tag in the test.** The test reads the tag from the real compiled instructions, so if either side changes the tag again, CI goes red.
  - **Record the slip instead of hiding it.** The audio can't be taken back, so the honest option is to make it visible to the recruiter.
- **Green:** [36666047243](https://github.com/yond44/yonda-quality-net/actions/runs/36666047243) (F27 no longer flagged).

### F8: the "Required" column in the fit/gap table was always empty (P2)

- **Red:** [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611), 3/3 failing.
- **Root cause:** the backend sent the vacancy's level as `expected_level`, but the website reads `required_level` (and `is_override` for the ✏ marker). Nothing checked that the two sides agreed, so the page showed an empty cell with no error.
- **Files changed:**
  - [`engine.rb:62-66`](../api/app/services/fit_gap/engine.rb#L62-L66): the two fields the web reads
  - [`portfolios_controller.rb:211-212`](../api/app/controllers/api/v1/portfolios_controller.rb#L211-L212): reports saved before the fix get `required_level` when read
- **Before → after:**
  ```ruby
  # engine.rb — BEFORE
  { skill_label: label, candidate_level: candidate_level, expected_level: expected_level, result: result, ... }

  # AFTER: also the fields the web's TypeScript type requires
  { skill_label: label, candidate_level: candidate_level,
    required_level: expected_level,                                   # what the web reads
    expected_level: expected_level,                                   # the PDF export and old reports
    is_override: portfolio_skill.present? && portfolio_skill[:overridden],
    result: result, ... }

  # portfolios_controller.rb — reports saved before the fix
  skill_comparisons: Array(report.skill_comparisons).map { |c| { 'required_level' => c['expected_level'] }.merge(c) }
  ```
- **Why this way:**
  - **Add fields; don't rename them.** Nothing that works today changes: the PDF export and stored reports keep `expected_level`.
  - **Fill in old reports when they're read,** so no data migration is needed.
  - **The test's source of truth is the web's own type file,** so the next time one side renames a field, CI goes red before a user sees an empty column.
- **Delivered in pull request [#1](https://github.com/yond44/yonda-quality-net/pull/1).** Its description was left as the empty template by mistake, so the gate failed it, correctly (see "The gate in action").
- **Green:** [36667125182](https://github.com/yond44/yonda-quality-net/actions/runs/36667125182) (PR #1, all tests green) and [36667342497](https://github.com/yond44/yonda-quality-net/actions/runs/36667342497) (`main` after the merge).

### F28: a skill with no evidence still got a level (P1, found in manual review after v1.0.0)

- **Red:** [36812383367](https://github.com/yond44/yonda-quality-net/actions/runs/36812383367): "F28 failing (4 of 5)" on the API, and the 3 new web checks.
- **Root cause:** the system had **no way to say "not enough evidence"**. Every skill had to have a level 1–5 (in the database, the model and the web), and the generator asked the AI to grade every skill, even when the candidate never spoke. So an empty interview got L1. And when the AI tried to say "below the scale" (level 0), the F5 check refused it, and a retry produced L1.
- **Files changed:**
  - **Added:** [`20261001000000_allow_not_assessed_skills.rb`](../api/db/migrate/20261001000000_allow_not_assessed_skills.rb) (a level may be empty), with [`schema.rb`](../api/db/schema.rb) regenerated
  - [`portfolio_skill.rb:10-15`](../api/app/models/portfolio_skill.rb#L10-L15) and [`assessor_override.rb:6-7`](../api/app/models/assessor_override.rb#L6-L7): an empty level is allowed and means "not assessed"
  - [`generator.rb:30-37`](../api/app/services/portfolios/generator.rb#L30-L37): no candidate answers → no AI call
  - [`generator.rb:100-102`](../api/app/services/portfolios/generator.rb#L100-L102): the prompt allows `"not_assessed"` and forbids guessing
  - [`generator.rb:175-192`](../api/app/services/portfolios/generator.rb#L175-L192), [`:222-231`](../api/app/services/portfolios/generator.rb#L222-L231) and [`:239-243`](../api/app/services/portfolios/generator.rb#L239-L243): storing "not assessed"
  - [`engine.rb:46-48`](../api/app/services/fit_gap/engine.rb#L46-L48): fit/gap shows `not_assessed`, not a gap
  - [`pdf_generator.rb:84-87`](../api/app/services/exports/pdf_generator.rb#L84-L87): the PDF says "Not assessed"
  - Web: [`constants.ts:3-12`](../web/src/utils/constants.ts#L3-L12) (`parseLevel`), [`LevelBadge.tsx:11-24`](../web/src/components/portfolio/LevelBadge.tsx#L11-L24), [`SkillPortfolioCard.tsx`](../web/src/components/portfolio/SkillPortfolioCard.tsx), [`OverridePanel.tsx`](../web/src/components/portfolio/OverridePanel.tsx), [`LevelRadio.tsx`](../web/src/components/assessment/LevelRadio.tsx), [`FitGapReportPage.tsx`](../web/src/pages/fitgap/FitGapReportPage.tsx) and [`types/index.ts`](../web/src/types/index.ts)
  - Test setup only: [`fixture_helpers.rb:26`](../api/spec/support/fixture_helpers.rb#L26) (`create_answered_interview`), used by the F5, F7 and critical-path tests, whose assertions are unchanged
- **Before → after:**
  ```ruby
  # generator.rb — BEFORE: always ask the AI to grade every skill
  response = @gemini_client.generate_content(prompt, temperature: 0.2)
  # AFTER: no answers from the candidate → nothing to grade, no AI call
  if candidate_answered?
    response = @gemini_client.generate_content(build_prompt, temperature: 0.2)
    save_skills(portfolio, response)
  else
    replace_skills(portfolio, not_assessed_rows('the candidate gave no answers in this interview.'))
  end

  # parse_level — NEW: the AI's "not_assessed" is stored as no level (nil), never as L1
  return nil if raw.is_a?(String) && raw.strip.downcase.tr(' ', '_') == 'not_assessed'
  ```
  ```ts
  // constants.ts — BEFORE: unreadable → 1 (the F5 bug, on the web)
  return isNaN(n) ? 1 : n;
  // AFTER: unreadable or missing → null ("not assessed")
  const match = level.match(/^\s*L?\s*([1-5])\s*$/i);
  return match ? Number(match[1]) : null;
  ```
- **Why this way:**
  - **"Not assessed" instead of L1.** L1 is a real finding ("understands the concept but can't apply it"); "never tested" is the absence of a finding. Using L1 would reject candidates when our system failed, or pass them for junior roles on a skill nobody tested. It would also bring back the F5 bug on purpose.
  - **Don't ask the AI when the candidate never answered.** There's nothing to grade, and asking invites an invented level.
  - **Give the AI an honest option** (`"not_assessed"`) instead of forcing a 1–5 number. The live run showed it was already trying to say exactly that (level 0).
  - **Recruiters stay in control:** a not-assessed skill can still be given a level by hand.
- **Green:** [36812959237](https://github.com/yond44/yonda-quality-net/actions/runs/36812959237) (F28 no longer flagged). Then the release gate on `v1.0.1`: [36813056953](https://github.com/yond44/yonda-quality-net/actions/runs/36813056953), **RELEASABLE**.

### F30: portfolios failed with the real AI, because a skill had two ids in the prompt (P1, found in live testing after v1.0.1)

- **Red:** [36815953972](https://github.com/yond44/yonda-quality-net/actions/runs/36815953972), 2/2 failing.
- **Root cause:** a regression from the F7 fix. F7 gave each configured skill a reference in the prompt's skill list (`S12`) and mapped answers back through it. But the coverage data in the same prompt still used the catalogue id or a name slug, so the AI saw **two ids for one skill**. When it copied the coverage one, the answer was rejected as an unknown skill, and after 3 retries there was no portfolio. The F7 tests missed it because their fake AI always copied the reference.
- **Files changed:**
  - [`generator.rb:51`](../api/app/services/portfolios/generator.rb#L51) and [`:58-59`](../api/app/services/portfolios/generator.rb#L58-L59): the configured skills are passed to the coverage data
  - [`generator.rb:154-156`](../api/app/services/portfolios/generator.rb#L154-L156): each coverage entry's id comes from `coverage_id`
  - [`generator.rb:164-176`](../api/app/services/portfolios/generator.rb#L164-L176): `coverage_id`, the same `S12` reference as the skill list
- **Before → after:**
  ```ruby
  # generator.rb, the coverage data in the prompt
  # BEFORE: a different id from the skill list
  id: map.skill_id || map.skill_label.downcase.gsub(/\s+/, '-'),      # "react-/-frontend-development-core"
  # AFTER: the same reference as "SKILL: React / Frontend Development Core (S7)"
  id: coverage_id(map, configured_skills),                            # "S7"
  ```
  In JavaScript terms: `coverage.id = configuredSkills.find(s => s.label === map.label)?.ref ?? map.slug`.
- **Why this way:**
  - **Remove the second id rather than accept both.** Accepting either id would hide the inconsistency. One id per skill means there's nothing to choose between.
  - **A contract test,** so if either part of the prompt changes its ids again, CI goes red.
  - **Checked with the real AI,** because the fake AI is what let this through in the first place.
- **Green:** [36816139679](https://github.com/yond44/yonda-quality-net/actions/runs/36816139679) (F30 no longer flagged).

### F31: a candidate who ended the interview was told "Connection lost" (P1, found in the end-to-end browser test; a regression from the F25 fix)

- **Red:** [36827787574](https://github.com/yond44/yonda-quality-net/actions/runs/36827787574), 3 web checks failing (the F25 checks green). Two levels: the hook ([`useAudioWebSocket.test.ts`](../web/src/hooks/useAudioWebSocket.test.ts), F31 block) and the page, with the real page code and stand-ins only for microphone, speakers and timer ([`InterviewEnd.test.tsx`](../web/src/pages/interview/InterviewEnd.test.tsx)).
- **Root cause:** `disconnect()` stopped reconnects by setting the attempt counter to its maximum. When the browser then reported the close, the close handler saw "no attempts left" and, since the F25 fix, reported `connection_lost`. Before F25 the same branch said "complete", which hid the problem. A close the page asked for and a reconnect that failed looked the same.
- **Files changed:**
  - [`useAudioWebSocket.ts:30-32`](../web/src/hooks/useAudioWebSocket.ts#L30-L32): a `closedOnPurposeRef` flag
  - [`useAudioWebSocket.ts:41`](../web/src/hooks/useAudioWebSocket.ts#L41): cleared on every new connection
  - [`useAudioWebSocket.ts:128`](../web/src/hooks/useAudioWebSocket.ts#L128): the close handler ignores a close the page asked for
  - [`useAudioWebSocket.ts:157`](../web/src/hooks/useAudioWebSocket.ts#L157) and [`:164`](../web/src/hooks/useAudioWebSocket.ts#L164): `disconnect()` and leaving the page set the flag
- **Before -> after:**
  ```ts
  // disconnect()
  // BEFORE: "no reconnect" was faked by using up the attempts
  reconnectAttemptsRef.current = RECONNECT_DELAYS.length;
  // AFTER: say what happened
  closedOnPurposeRef.current = true;

  // ws.onclose
  // BEFORE: (no check) -> attempts used up -> onStateChange("connection_lost")
  // AFTER:
  if (closedOnPurposeRef.current) return; // the page closed it: nothing was lost
  ```
- **Why this way:**
  - **Name the intent instead of overloading a counter.** The counter means "how many reconnects were tried"; reusing it to mean "don't reconnect" is what let two different events look the same.
  - **Fixed in the hook,** so every way the page closes the connection (End Interview, the time limit, leaving the page) is covered by one change.
  - **Lesson:** the F25 tests covered a drop and a server end, but not the page's own close. The end-to-end test is what found it.
- **Green:** [36827803414](https://github.com/yond44/yonda-quality-net/actions/runs/36827803414); in the browser, End Interview shows "Interview Complete".

### F32: the PDF export crashed for every overridden portfolio (P1, found in the end-to-end test)

- **Red:** [36827823866](https://github.com/yond44/yonda-quality-net/actions/runs/36827823866) ([`f32_pdf_export_spec.rb`](../api/spec/requests/f32_pdf_export_spec.rb)), 2/3 failing with 500.
- **Root cause:** the PDF used PDF's built-in fonts, which only encode Windows-1252. The override line prints `→`, which isn't in that set, so the PDF library raised an error. Any AI text with such a character did the same.
- **Files changed:**
  - [`pdf_generator.rb:19-29`](../api/app/services/exports/pdf_generator.rb#L19-L29): the font family (DejaVu Sans, normal and bold)
  - [`pdf_generator.rb:41-42`](../api/app/services/exports/pdf_generator.rb#L41-L42): the document uses it
  - `api/vendor/fonts/`: `DejaVuSans.ttf`, `DejaVuSans-Bold.ttf` and the font's `LICENSE`
- **Before -> after:**
  ```ruby
  # BEFORE: PDF's built-in Helvetica (Windows-1252 only) -> "→" raises IncompatibleStringEncoding
  Prawn::Document.new(page_size: 'A4', ...) do |pdf|
  # AFTER: a Unicode TrueType font
  Prawn::Document.new(page_size: 'A4', ...) do |pdf|
    pdf.font_families.update(FONT_FAMILY)
    pdf.font('DejaVuSans')
  ```
  In JavaScript terms: like switching a `latin1` encoder that throws on `→` to a UTF-8 one.
- **Why this way:**
  - **A Unicode font, not replacing the arrow.** Replacing `→` with `->` would fix the one character we know about. The AI writes free text, so the next symbol would crash it again. With a TrueType font, a missing glyph is drawn as a box and never raises.
  - **The font is kept in the repo** (with its licence), so the export works the same on every machine and in CI, without depending on system fonts.
- **Checked:** every saved portfolio exports (16/16, including three with overrides), and the extracted PDF text reads "Level: L4 (AI: L2 → Override: L4)".
- **Green:** [36827849551](https://github.com/yond44/yonda-quality-net/actions/runs/36827849551).

### F33: clicking a level on the second skill changed the first skill (P1, found in the end-to-end browser test)

- **Red:** [36827870194](https://github.com/yond44/yonda-quality-net/actions/runs/36827870194) ([`LevelRadio.test.tsx`](../web/src/components/assessment/LevelRadio.test.tsx)), 2/3 failing.
- **Root cause:** every level picker used the ids `level-1` … `level-5`. A label activates the **first** element on the page with its id, so with two pickers on a form, the second one's labels changed the first one.
- **Files changed:** [`LevelRadio.tsx:1`](../web/src/components/assessment/LevelRadio.tsx#L1), [`:17`](../web/src/components/assessment/LevelRadio.tsx#L17) and [`:28-29`](../web/src/components/assessment/LevelRadio.tsx#L28-L29)
- **Before -> after:**
  ```tsx
  // BEFORE: the same id in every picker
  <RadioGroupItem value={String(level)} id={`level-${level}`} />
  <Label htmlFor={`level-${level}`}>
  // AFTER: a prefix unique to this picker
  const idPrefix = useId();
  <RadioGroupItem value={String(level)} id={`${idPrefix}-level-${level}`} />
  <Label htmlFor={`${idPrefix}-level-${level}`}>
  ```
- **Why this way:**
  - **`useId()`** is React's built-in way to make ids unique per component instance (and stable between renders), so no caller has to pass an id.
  - **One component fixed,** so every form that uses it is fixed: vacancy (new and edit), assessment skills, and the override panel.
  - **The test checks both** the behaviour (the right handler is called) and the cause (no duplicate ids), so a future change that brings back shared ids fails CI.
- **Green:** [36827898429](https://github.com/yond44/yonda-quality-net/actions/runs/36827898429); in the browser, the vacancy is saved with the levels chosen.

### F35: the lists only showed the newest 20 assessments and vacancies (P1, found in the soak test)

- **Red:** [36970071541](https://github.com/yond44/yonda-quality-net/actions/runs/36970071541), 3 web checks failing.
- **Root cause:** the API pages its lists (20 per page, `meta.total_pages`), but the two list pages always asked for page 1 and had no page controls, and the fit/gap vacancy choice used that same first page. Nobody noticed with a handful of test records; the soak test created enough to cross 20.
- **Files changed:**
  - [`Pager.tsx`](../web/src/components/Pager.tsx): Previous / Page X of Y / Next, shown only when there's more than one page
  - [`AssessmentListPage.tsx:36-50`](../web/src/pages/assessments/AssessmentListPage.tsx#L36-L50) and [`:109`](../web/src/pages/assessments/AssessmentListPage.tsx#L109): keeps the current page and shows the pager; [`VacancyListPage.tsx`](../web/src/pages/vacancies/VacancyListPage.tsx) the same
  - [`vacancies.ts:19-28`](../web/src/services/vacancies.ts#L19-L28): `listAll()` fetches every page, 100 at a time
  - [`PortfolioPage.tsx:46`](../web/src/pages/portfolio/PortfolioPage.tsx#L46): the fit/gap choice uses `listAll()`
- **Before -> after:**
  ```tsx
  // AssessmentListPage (and VacancyListPage)
  // BEFORE: page 1 only, no way to ask for more
  assessmentsApi.list().then((res) => setAssessments(res.data.assessments))
  // AFTER: the current page, plus a pager from meta.total_pages
  assessmentsApi.list(page).then((res) => { setAssessments(res.data.assessments); setTotalPages(res.data.meta?.total_pages ?? 1); })
  <Pager page={page} totalPages={totalPages} onChange={setPage} />

  // PortfolioPage, fit/gap choice
  // BEFORE: vacanciesApi.list()     -> the newest 20
  // AFTER:  vacanciesApi.listAll()  -> every page, 100 at a time
  ```
- **Why this way:**
  - **Pages for the lists, everything for the choice.** A list people browse reads better a page at a time; a choice must offer every option, or some fit/gap comparisons are impossible.
  - **No API change.** The API already paged correctly and caps a page at 100; the defect was only that the web never asked for page 2.
  - **The tests fake the HTTP layer, not the service,** so they check what the recruiter can reach, not how the page fetches it.
- **Green:** [36970269123](https://github.com/yond44/yonda-quality-net/actions/runs/36970269123); in the browser with the real data, page 2 opens an old assessment and fit/gap runs against the oldest vacancy.

## Assumptions

- **Spec links** may point to a URL, an issue, or a file in this repo. Audit findings (`assessment/01-audit.md#…`) count as specs for defect fixes, because each has an impact, repro steps and the expected behaviour.
- **One user belongs to one company** (made for F1; the spec never defined it, see audit M2).
- **Test databases** are created from migrations, not `schema.rb`, because the migrations create the `ai_interview` schema the app expects.
