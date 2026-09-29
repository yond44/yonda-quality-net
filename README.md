# The Product
Please refer to the product wiki for initial product specification

# The Platform

A two-service application used for the Product Engineer case study. It is provided as a single repository so the whole thing clones, runs, and releases as one unit.

```
.
├── api/    # Backend service (Ruby on Rails, PostgreSQL, Redis/Sidekiq)
└── web/    # Frontend web app (React 18 + TypeScript, Vite, Tailwind)
```

The two services run together: the web app talks to the API over REST and WebSocket.

## Running it locally

Each service has its own setup guide. Run the API first, then the web app pointed at it.

1. **API** — see [`api/README.md`](api/README.md). Rails app; needs Ruby (see `api/.ruby-version`), PostgreSQL, and Redis. It serves on `http://localhost:3001`.
2. **Web** — see [`web/README.md`](web/README.md). Vite app; `npm install`, copy `.env.example` to `.env`, point `VITE_API_BASE_URL` at the API, then `npm run dev`. It serves on `http://localhost:5173`.

## Quality net (CI + workflow gate)

Every push and pull request runs the checks in [`.github/workflows/ci.yml`](.github/workflows/ci.yml). A pull request must also pass the **Definition-of-Ready gate**: link a spec, write Given/When/Then acceptance criteria and a design plan, and change a test when it changes code. The PR template sets this up.

Run the net locally:

```bash
cd api && bundle exec rspec                            # audit-finding specs + critical paths
node --test .github/scripts/definition-of-ready.test.mjs   # the gate's own rules
cd web && npm run build                                # web type-check + build
```

What each check protects, what it deliberately doesn't cover, and how to extend it: [`assessment/02-quality-system.md`](assessment/02-quality-system.md).

## Notes for the case study

- This is the codebase you assess, harden, and release. Treat it as a version about to ship to a client.
- Work in the `/assessment` folder at the repo root for your written deliverables; code changes go in `api/` or `web/`.
- See the case-study brief you were given for what to produce and how it is evaluated.
