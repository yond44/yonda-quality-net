// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import LevelBadge from "./LevelBadge";

// Audit F28 (web side): a skill with no level must be shown as "Not assessed",
// not as an empty badge or a made-up level.
describe("F28: the level badge says when a skill wasn't assessed", () => {
    afterEach(cleanup);

    it('shows "Not assessed" for a skill with no level', () => {
        render(<LevelBadge level={null} />);

        expect(screen.getByText("Not assessed")).toBeTruthy();
    });

    it("still shows a real level (control)", () => {
        render(<LevelBadge level={3} />);

        expect(screen.getByText("L3")).toBeTruthy();
    });
});
