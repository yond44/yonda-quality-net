// Workflow gate: Definition of Ready / Done for pull requests.
//
// A PR cannot go green unless it carries its inputs:
//   1. Spec      a link to the spec/PRD/ticket/audit finding it implements
//   2. Criteria  acceptance criteria as at least one Given / When / Then scenario
//   3. Plan      a short design/solution plan
//   4. Test      if it changes application code, it also adds or changes a test
//
// Docs-only PRs (only *.md or assessment/**) are exempt, so the gate is not bureaucratic.
// The PR description comes from .github/pull_request_template.md.
import fs from 'node:fs';
import { execSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const CODE = [/^api\/(app|config|db|lib)\//, /^web\/src\//, /^\.github\/scripts\//];
const TEST = [/^api\/spec\//, /\.(test|spec)\.(m?[jt]sx?)$/];
const DOCS = [/\.md$/i, /^assessment\//];

// Splits the PR body into "## Heading" sections; HTML comments (template hints) are removed.
export function parseSections(body) {
  const sections = {};
  let current = null;
  for (const line of (body || '').replace(/<!--[\s\S]*?-->/g, '').split(/\r?\n/)) {
    const heading = line.match(/^##\s+(.+?)\s*$/);
    if (heading) { current = heading[1].toLowerCase(); sections[current] = ''; continue; }
    if (current) sections[current] += line + '\n';
  }
  return sections;
}

const section = (sections, prefix) =>
  (Object.entries(sections).find(([name]) => name.startsWith(prefix)) || [, ''])[1].trim();

export function evaluate({ body, changedFiles, fileExists = () => false }) {
  const isTest = (f) => TEST.some((re) => re.test(f));
  const isCode = (f) => !isTest(f) && CODE.some((re) => re.test(f));

  if (changedFiles.length > 0 && changedFiles.every((f) => DOCS.some((re) => re.test(f)))) {
    return { exempt: true, results: [] };
  }

  const sections = parseSections(body);
  const spec = section(sections, 'spec');
  const criteria = section(sections, 'acceptance');
  const plan = section(sections, 'design');

  const specLinked =
    /https?:\/\/\S+/.test(spec) ||
    /(^|\s)#\d+\b/.test(spec) ||
    (spec.match(/[\w./-]+\.(md|pdf)(#[\w-]+)?/g) || []).some((p) => fileExists(p.replace(/#.*$/, '')));

  const hasScenario = /\bgiven\b/i.test(criteria) && /\bwhen\b/i.test(criteria) && /\bthen\b/i.test(criteria);
  const hasPlan = plan.replace(/[-*\s]/g, '').length >= 30;

  const codeChanged = changedFiles.filter(isCode);
  const testChanged = changedFiles.some(isTest);

  return {
    exempt: false,
    results: [
      { rule: 'Spec linked', ok: specLinked,
        fix: 'Under "## Spec / PRD", link what this implements: a URL, an issue (#12), or a repo file (assessment/01-audit.md#f21).' },
      { rule: 'Acceptance criteria (Given / When / Then)', ok: hasScenario,
        fix: 'Under "## Acceptance criteria", write at least one scenario with Given, When and Then.' },
      { rule: 'Design plan', ok: hasPlan,
        fix: 'Under "## Design plan", describe in a few lines how the change works (at least 30 characters).' },
      { rule: 'Test added or changed', ok: codeChanged.length === 0 || testChanged,
        fix: `Code changed (${codeChanged.slice(0, 3).join(', ')}${codeChanged.length > 3 ? ', ...' : ''}) but no test did. Add or update a test in api/spec/ or a *.test.* file.` },
    ],
  };
}

function report({ exempt, results }) {
  const out = (t) => {
    if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, t + '\n');
    console.log(t);
  };
  if (exempt) { out('## 🟢 READY: docs-only change, exempt from the Definition of Ready'); return true; }
  const failed = results.filter((r) => !r.ok);
  out(failed.length
    ? `## 🔴 NOT READY: ${failed.length} of ${results.length} inputs missing. This PR cannot merge.`
    : `## 🟢 READY: all ${results.length} inputs present`);
  out('\n| Input | Status | How to fix |\n|---|---|---|');
  for (const r of results) out(`| ${r.rule} | ${r.ok ? '✅' : '❌'} | ${r.ok ? '' : r.fix} |`);
  return failed.length === 0;
}

// CLI: runs inside the pull_request workflow.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const pr = event.pull_request;
  const changedFiles = execSync(`git diff --name-only ${pr.base.sha}...${pr.head.sha}`, { encoding: 'utf8' })
    .split('\n').filter(Boolean);
  const ready = report(evaluate({ body: pr.body, changedFiles, fileExists: (p) => fs.existsSync(p) }));
  process.exit(ready ? 0 : 1);
}
