import { describe, expect, it } from "vitest";
import { parseLevel } from "./constants";

// Audit F28 (web side): parseLevel turned anything it couldn't read into level 1, the
// same silent-L1 bug as F5 on the backend, and crashed on a missing level. A skill with
// no level is "not assessed" and must stay that way on screen.
describe("F28: a missing or unreadable level is never shown as L1", () => {
    it("keeps a missing level missing", () => {
        expect(parseLevel(null)).toBeNull();
    });

    it("does not turn an unreadable level into 1", () => {
        expect(parseLevel("high")).toBeNull();
    });

    it("still reads real levels (control)", () => {
        expect(parseLevel(4)).toBe(4);
        expect(parseLevel("L3")).toBe(3);
    });
});
