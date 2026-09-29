// Self-tests for the workflow gate, so the gate itself cannot be silently weakened.
// Run: node --test .github/scripts/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { evaluate } from './definition-of-ready.mjs';

const READY_BODY = `
## Spec / PRD
assessment/01-audit.md#f21
## Acceptance criteria
Given a vacancy that does not exist
When the assessor opens its edit page
Then they see "not found" instead of an empty form
## Design plan
Replace the swallowed catch with an error state and a not-found banner on the page.
## Tests
Component test for the not-found banner.
`;
const exists = (p) => p === 'assessment/01-audit.md';
const failing = (res) => res.results.filter((r) => !r.ok).map((r) => r.rule);

test('a complete PR with code and a test is ready', () => {
  const res = evaluate({ body: READY_BODY, changedFiles: ['web/src/pages/x.tsx', 'web/src/pages/x.test.tsx'], fileExists: exists });
  assert.deepEqual(failing(res), []);
});

test('the untouched template (only hint comments) is not ready on any input', () => {
  const template = '## Spec / PRD\n<!-- link -->\n## Acceptance criteria\n<!-- Given x When y Then z -->\n## Design plan\n<!-- plan -->';
  const res = evaluate({ body: template, changedFiles: ['api/app/models/user.rb'], fileExists: exists });
  assert.deepEqual(failing(res), ['Spec linked', 'Acceptance criteria (Given / When / Then)', 'Design plan', 'Test added or changed']);
});

test('code changed without a test is blocked', () => {
  const res = evaluate({ body: READY_BODY, changedFiles: ['api/app/controllers/api/v1/sessions_controller.rb'], fileExists: exists });
  assert.deepEqual(failing(res), ['Test added or changed']);
});

test('a spec path that does not exist does not count as a link', () => {
  const body = READY_BODY.replace('assessment/01-audit.md#f21', 'docs/made-up-spec.md');
  const res = evaluate({ body, changedFiles: ['api/spec/x_spec.rb'], fileExists: exists });
  assert.deepEqual(failing(res), ['Spec linked']);
});

test('URLs and issue references count as spec links', () => {
  for (const link of ['https://example.com/prd', 'Implements #12']) {
    const res = evaluate({ body: READY_BODY.replace('assessment/01-audit.md#f21', link), changedFiles: ['api/spec/x_spec.rb'] });
    assert.deepEqual(failing(res), [], link);
  }
});

test('acceptance criteria without Given/When/Then are rejected', () => {
  const body = READY_BODY.replace(/Given[\s\S]*?empty form/, '- it should work');
  const res = evaluate({ body, changedFiles: ['api/spec/x_spec.rb'], fileExists: exists });
  assert.deepEqual(failing(res), ['Acceptance criteria (Given / When / Then)']);
});

test('docs-only changes are exempt', () => {
  const res = evaluate({ body: '', changedFiles: ['assessment/01-audit.md', 'README.md'] });
  assert.equal(res.exempt, true);
});

test('a docs change mixed with code is not exempt', () => {
  const res = evaluate({ body: '', changedFiles: ['README.md', 'api/app/models/user.rb'] });
  assert.equal(res.exempt, false);
});
