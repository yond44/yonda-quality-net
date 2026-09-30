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

**Gate self-test, web tests and the web build:**
```bash
node --test .github/scripts/definition-of-ready.test.mjs
cd web && npm ci && npm test && npm run build
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
   - `Net: web tests, type-check and build`

   A check only appears in that list after it has run once, and the gate runs on the first pull request.
3. Leave **"Do not allow bypassing"** unticked. The brief allows the bulk of the work as direct commits to `main`, so the owner can still push directly, but every pull request must pass.

---

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
| **F6–F8** | [36550036611](https://github.com/yond44/yonda-quality-net/actions/runs/36550036611): 8 failing, 0 errors | *Task 3* | *Task 3* |

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
  - [`generator.rb:8-10`](../api/app/services/portfolios/generator.rb#L8-L10): the error class and the accepted text form
  - [`generator.rb:154-193`](../api/app/services/portfolios/generator.rb#L154-L193): `save_skills`, the new `skill_row` and `parse_level`
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

## Assumptions

- **Spec links** may point to a URL, an issue, or a file in this repo. Audit findings (`assessment/01-audit.md#…`) count as specs for defect fixes, because each has an impact, repro steps and the expected behaviour.
- **One user belongs to one company** (made for F1; the spec never defined it, see audit M2).
- **Test databases** are created from migrations, not `schema.rb`, because the migrations create the `ai_interview` schema the app expects.
