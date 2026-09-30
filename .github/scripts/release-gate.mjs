// Release gate: decides whether a tagged version is releasable.
//
// A version is releasable only if all three hold:
//   1. the quality net passed on the tagged commit;
//   2. no P0/P1 finding is left unfixed in the audit (assessment/01-audit.md),
//      so the release is tied to the human record, not only to the tests;
//   3. RELEASE_NOTES.md has a section for this tag, stating what it delivers.
//
// Run by .github/workflows/release.yml on every version tag. Writes a one-line verdict
// ("v1.0.0 is RELEASABLE" / "BLOCKED") to the run summary and fails when blocked.

import { readFileSync, appendFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

const clean = (cell) => cell.replace(/\*\*/g, "").trim();

// Rows of the audit's ranked table: | F1 | problem | **P1** | type | evidence | status |
export function auditFindings(auditMarkdown) {
    const start = auditMarkdown.indexOf("## Ranked list");
    if (start < 0) throw new Error('assessment/01-audit.md has no "## Ranked list" section');
    const section = auditMarkdown.slice(start).split(/\n## /)[0];

    return section
        .split("\n")
        .filter((line) => /^\|\s*F\d+\s*\|/.test(line))
        .map((line) => {
            const cells = line.split("|").slice(1, -1).map(clean);
            return { id: cells[0], problem: cells[1], severity: cells[2], status: cells[5].toLowerCase() };
        });
}

export function openBlockers(findings) {
    return findings.filter((f) => /^P[01]$/.test(f.severity) && f.status !== "fixed");
}

export function hasReleaseNotes(notesMarkdown, tag) {
    const escaped = tag.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`^##\\s+${escaped}(\\s|$)`, "m").test(notesMarkdown);
}

export function decide({ tag, netResult, auditMarkdown, notesMarkdown }) {
    const findings = auditFindings(auditMarkdown);
    const blockers = openBlockers(findings);
    const openOthers = findings.filter((f) => f.status !== "fixed" && !blockers.includes(f));
    const notesOk = notesMarkdown !== null && hasReleaseNotes(notesMarkdown, tag);

    const checks = [
        {
            name: "Quality net passed on this commit",
            ok: netResult === "success",
            detail: netResult === "success" ? "every check passed" : `the net's result was "${netResult}"`,
        },
        {
            name: "No P0/P1 finding left unfixed in the audit",
            ok: blockers.length === 0,
            detail: blockers.length === 0
                ? `all P0/P1 are fixed; ${openOthers.length} P2/P3 remain as accepted risks (see assessment/03-release-decision.md)`
                : blockers.map((b) => `${b.id} (${b.severity}, ${b.status}): ${b.problem}`).join("; "),
        },
        {
            name: `Release notes describe ${tag}`,
            ok: notesOk,
            detail: notesOk ? "RELEASE_NOTES.md has a section for this tag" : `add a "## ${tag}" section to RELEASE_NOTES.md`,
        },
    ];

    return { tag, releasable: checks.every((c) => c.ok), checks };
}

function summary({ tag, releasable, checks }) {
    const verdict = releasable ? `# ✅ ${tag} is RELEASABLE` : `# ⛔ ${tag} is BLOCKED`;
    const rows = checks.map((c) => `| ${c.ok ? "✅" : "❌"} | ${c.name} | ${c.detail} |`);
    return [verdict, "", "| | Release check | Detail |", "|---|---|---|", ...rows, ""].join("\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    const tag = process.env.TAG ?? "untagged";
    const result = decide({
        tag,
        netResult: process.env.NET_RESULT ?? "unknown",
        auditMarkdown: readFileSync("assessment/01-audit.md", "utf8"),
        notesMarkdown: existsSync("RELEASE_NOTES.md") ? readFileSync("RELEASE_NOTES.md", "utf8") : null,
    });

    const text = summary(result);
    console.log(text);
    if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, text + "\n");

    if (!result.releasable) {
        for (const c of result.checks.filter((x) => !x.ok)) {
            console.log(`::error title=${tag} is BLOCKED::${c.name}: ${c.detail}`);
        }
        process.exit(1);
    }
    console.log(`::notice title=${tag} is RELEASABLE::All release checks passed`);
}
