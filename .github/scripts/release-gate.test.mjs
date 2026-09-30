// Tests for the release gate's own rules, so they can't be silently weakened.
// Run: node --test .github/scripts/release-gate.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { decide } from "./release-gate.mjs";

const audit = (rows) => `# Audit\n\n## Ranked list\n\n| # | Problem | Sev | Type | Evidence | Status |\n|---|---|---|---|---|---|\n${rows}\n\n---\n\n## Findings in detail\n`;
const NOTES = "# Release notes\n\n## v1.0.0\n\nWhat this version delivers.\n";

test("releasable when the net passed, every P0/P1 is fixed and the notes describe the tag", () => {
    const r = decide({
        tag: "v1.0.0",
        netResult: "success",
        auditMarkdown: audit("| F1 | Login bug | **P1** | built-wrong | LIVE | **fixed** |\n| F9 | Minor | P2 | built-wrong | LIVE | remaining |"),
        notesMarkdown: NOTES,
    });
    assert.equal(r.releasable, true);
});

test("blocked when a P0 or P1 is still unfixed, even if every test is green", () => {
    const r = decide({
        tag: "v1.0.0",
        netResult: "success",
        auditMarkdown: audit("| F1 | Login bug | **P1** | built-wrong | LIVE | remaining |"),
        notesMarkdown: NOTES,
    });
    assert.equal(r.releasable, false);
    assert.match(r.checks[1].detail, /F1/);
});

test("blocked when the quality net did not pass", () => {
    const r = decide({
        tag: "v1.0.0",
        netResult: "failure",
        auditMarkdown: audit("| F1 | Login bug | **P1** | built-wrong | LIVE | **fixed** |"),
        notesMarkdown: NOTES,
    });
    assert.equal(r.releasable, false);
});

test("blocked when the release notes don't describe this tag", () => {
    const r = decide({
        tag: "v1.1.0",
        netResult: "success",
        auditMarkdown: audit("| F1 | Login bug | **P1** | built-wrong | LIVE | **fixed** |"),
        notesMarkdown: NOTES,
    });
    assert.equal(r.releasable, false);
    assert.match(r.checks[2].detail, /v1\.1\.0/);
});
