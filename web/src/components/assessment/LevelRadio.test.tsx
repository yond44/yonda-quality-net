// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import LevelRadio from "./LevelRadio";

// Audit F33: every LevelRadio gave its options the same ids ("level-1" … "level-5"), and a
// label points at the FIRST element with its id. With two skills on a form (vacancy,
// assessment), clicking the "L2" text of the second skill changed the first skill's
// level instead. Found in the end-to-end browser test: the vacancy was saved as
// React L2 / Communication L3 instead of React L3 / Communication L2.
function twoSkills() {
    const first = vi.fn();
    const second = vi.fn();
    render(
        <>
            <LevelRadio value={3} onChange={first} />
            <LevelRadio value={3} onChange={second} />
        </>
    );
    return { first, second };
}

describe("F33: choosing a level changes only the skill it belongs to", () => {
    afterEach(cleanup);

    it("clicking the second skill's level label changes the second skill, not the first", () => {
        const { first, second } = twoSkills();

        fireEvent.click(screen.getAllByText("L2")[1]);

        expect(first).not.toHaveBeenCalled();
        expect(second).toHaveBeenCalledWith(2);
    });

    it("gives every level option on the page its own id", () => {
        twoSkills();

        const ids = screen.getAllByRole("radio").map((radio) => radio.id);
        expect(new Set(ids).size).toBe(ids.length);
    });

    it("clicking a level label still picks that level when there is one skill (control)", () => {
        const onChange = vi.fn();
        render(<LevelRadio value={3} onChange={onChange} />);

        fireEvent.click(screen.getByText("L2"));

        expect(onChange).toHaveBeenCalledWith(2);
    });
});
