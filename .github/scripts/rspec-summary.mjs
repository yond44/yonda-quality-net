// Turns RSpec's JSON output into a readable table in the GitHub job summary:
// one row per check (audit finding or critical path) with pass/fail, so anyone
// can see WHAT is broken without reading logs.
//
// Checks are grouped by the prefix of the top-level describe:
//   "F1: ..."            -> audit finding F1
//   "Critical path: ..." -> end-to-end happy path that must never regress
//
// Usage: node rspec-summary.mjs path/to/rspec.json
// Never fails the job itself; the rspec step decides pass/fail.
import fs from 'node:fs';

const out = (text) => {
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, text + '\n');
  console.log(text);
};

let data;
try {
  data = JSON.parse(fs.readFileSync(process.argv[2] || 'rspec.json', 'utf8'));
} catch {
  out('## 🔴 API test net did not run\nRSpec produced no results. The app most likely failed to load. See the job log.');
  process.exit(0);
}

if (data.summary?.errors_outside_of_examples_count > 0) {
  out('## 🔴 API test net could not load the app\n' +
      `${data.summary.errors_outside_of_examples_count} error(s) happened before any test ran (usually the app failing to boot). See the job log.\n`);
}

const groups = new Map();
for (const ex of data.examples || []) {
  const match = ex.full_description.match(/^(F\d+|Critical path)\b/);
  const id = match ? match[1] : 'Other';
  const title = ex.full_description.slice(0, ex.full_description.length - ex.description.length).trim();
  if (!groups.has(id)) groups.set(id, { id, title, total: 0, failed: [] });
  const g = groups.get(id);
  if (title.length < g.title.length) g.title = title;
  g.total += 1;
  if (ex.status === 'failed') g.failed.push(ex.description);
}

const order = (id) => (id === 'Critical path' ? 0 : id === 'Other' ? 999 : Number(id.slice(1)));
const rows = [...groups.values()].sort((a, b) => order(a.id) - order(b.id));
const failing = rows.filter((g) => g.failed.length);

out(failing.length
  ? `## 🔴 NET RED: ${failing.length} of ${rows.length} checks failing (${failing.map((g) => g.id).join(', ')})`
  : `## 🟢 NET GREEN: all ${rows.length} checks pass`);
out('\n| Check | What it protects | Result |\n|---|---|---|');
for (const g of rows) {
  const protects = g.title.replace(/^(F\d+|Critical path)\s*:\s*/, '');
  const result = g.failed.length
    ? `❌ ${g.failed.length} of ${g.total} failing<br>${g.failed.map((d) => `• ${d}`).join('<br>')}`
    : `✅ ${g.total} of ${g.total} pass`;
  out(`| **${g.id}** | ${protects} | ${result} |`);
}
out(`\n_${data.summary_line || ''}_`);
