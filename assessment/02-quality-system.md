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
| **Gate: self-test** | The gate's own rules can't be silently weakened | A broken or loosened gate |
| **Net: API boots in production mode** | The backend actually starts with production settings | **F22** (P0): production couldn't boot |
| **Net: API tests (audit findings + critical paths)** | Data integrity and tenant isolation on the risk-carrying paths, plus the main journey | **F1–F8**, and any regression on the critical path |
| **Net: web type-check and build** | The web app compiles and builds | Type errors and broken builds in the frontend |

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
| [`f3_invite_url_spec.rb`](../api/spec/models/f3_invite_url_spec.rb) | **F3** invite link leads to a 404 | The link uses the web app's address, on a route `web/src/App.tsx` really serves |
| [`f4_removed_skills_spec.rb`](../api/spec/requests/f4_removed_skills_spec.rb) | **F4** "removed" skills stay | The exact payload the edit page sends really removes the skill |
| [`f5_level_parsing_spec.rb`](../api/spec/services/f5_level_parsing_spec.rb) | **F5** unreadable AI level stored as L1 | `"L3"` becomes 3, and a missing level fails loudly |
| [`f6_audio_complete_spec.rb`](../api/spec/requests/f6_audio_complete_spec.rb) | **F6** false "all covered" | A never-started or uncovered interview is not recorded as `all_covered` |
| [`f7_skill_identity_spec.rb`](../api/spec/services/f7_skill_identity_spec.rb) | **F7** skills keyed on the AI's wording | Skills stay tied to the configuration, and a dropped skill fails loudly |
| [`f8_fitgap_contract_spec.rb`](../api/spec/requests/f8_fitgap_contract_spec.rb) | **F8** web ↔ API contract | The payload has every field the **web's own TypeScript type** requires |
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
| **Frontend behaviour** | No UI test framework yet; the web job only type-checks and builds | **F21** (error states) and the web side of F4 are untested. The build passes even if a page shows wrong data. |
| **P2/P3 findings** other than F8 | Time goes to P0/P1 first, as the brief allows | F9–F21 have no checks yet (listed as open in the audit) |
| **Production configuration beyond boot** | The boot check uses dummy secrets | **F16**: the real deployment files still lack secrets and pin `:latest` images |
| **Quality of a PR's inputs** | The gate checks the inputs **exist and have the right shape**, not whether they're **good** | A vague spec or a weak test can still pass. Human review is still needed. The gate removes "forgot the spec", not bad judgment. |

---

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
  bundle exec rails zeitwerk:check
```

**Gate self-test and the web build:**
```bash
node --test .github/scripts/definition-of-ready.test.mjs
cd web && npm ci && npm run build
```

## How to extend it

- **A new defect:**
  - Add a spec whose top-level description starts with the finding ID, e.g. `RSpec.describe 'F9: ...'`. It appears in the CI summary automatically.
  - Write it so it **fails on the bug first**, and include a control that must stay green.
- **A new gate rule:** add it in `definition-of-ready.mjs` **and** a case in `definition-of-ready.test.mjs`, so the rule itself is tested.
- **Fakes for AI answers:** build a `FakePortfolioModel` with `levels:`, `rename:` or `omit:` to script how the "model" answers.

## Making the gate impossible to skip (one-time GitHub setting)

A CI check only **blocks** a merge when GitHub is told it's required. This is a repository setting, so it can't be committed as code:

1. Go to **Settings → Branches → Add branch protection rule** for `main`.
2. Tick **Require status checks to pass before merging**, and add:
   - `Gate: Definition of Ready`
   - `Gate: self-test`
   - `Net: API boots in production mode`
   - `Net: API tests (audit findings + critical paths)`
   - `Net: web type-check and build`

   A check only appears in that list after it has run once, and the gate runs on the first pull request.
3. Leave **"Do not allow bypassing"** unticked. The brief allows the bulk of the work as direct commits to `main`, so the owner can still push directly, but every pull request must pass.

---

## Red → green log

Every fix follows the same order: **a failing check is pushed first, then the fix**. Each is a separate commit with its own CI run, so the history shows the transition.

| Finding | Red (failing run) | Green (passing run) | Root cause fixed |
|---|---|---|---|
| **F22** production can't boot | [36547094896](https://github.com/yond44/yonda-quality-net/actions/runs/36547094896): *the CI found it by itself on its first run* | [36548570736](https://github.com/yond44/yonda-quality-net/actions/runs/36548570736) | Removed Active Job config for a framework never loaded; the autoloader no longer also manages boot-time WebSocket middleware |
| **F1** login picks any company | [36548723182](https://github.com/yond44/yonda-quality-net/actions/runs/36548723182): 4/4 failing | [36549163695](https://github.com/yond44/yonda-quality-net/actions/runs/36549163695) | Users belong to one organization, and the token scheme comes only from it |
| **F2–F8** | [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611): 17 failing, 0 errors | *Task 3* | *Task 3* |

For F1, the spec's assertions are unchanged between red and green. Only its setup line changed (it no longer needs to handle the missing column), and the commit message says so.

## Assumptions

- **Spec links** may point to a URL, an issue, or a file in this repo. Audit findings (`assessment/01-audit.md#…`) count as specs for defect fixes, because each has an impact, repro steps and the expected behaviour.
- **One user belongs to one company** (made for F1; the spec never defined it, see audit M2).
- **Test databases** are created from migrations, not `schema.rb`, because the migrations create the `ai_interview` schema the app expects.
