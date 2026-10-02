// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { afterEach, describe, expect, it, vi } from "vitest";

// Audit F35: the API returns lists 20 at a time, but the Assessments page only ever asked
// for the first page and had no way to see more. A company's 21st-newest assessment, with
// its candidates and results, could only be reached by typing its URL. Found in the soak test.

// The HTTP layer is faked, so this holds whatever way the page asks for the other pages.
const pages: Record<number, { name: string }[]> = {};
vi.mock("@/services/api", () => ({
    WS_URL: "",
    default: {
        get: vi.fn(async (url: string, config?: { params?: { page?: number; per_page?: number } }) => {
            if (url !== "/assessments") throw new Error(`unexpected GET ${url}`);
            const all = Object.values(pages).flat();
            const perPage = Math.min(config?.params?.per_page ?? 20, 100);
            const page = config?.params?.page ?? 1;
            const items = all.slice((page - 1) * perPage, page * perPage)
                .map((a, i) => ({ id: (page - 1) * perPage + i + 1, name: a.name, time_limit_min: 30 }));
            return {
                data: {
                    assessments: items,
                    meta: { current_page: page, per_page: perPage, total_count: all.length, total_pages: Math.ceil(all.length / perPage) },
                },
            };
        }),
    },
}));

import AssessmentListPage from "./AssessmentListPage";

function givenAssessments(count: number) {
    for (const k of Object.keys(pages)) delete pages[Number(k)];
    pages[1] = Array.from({ length: count }, (_, i) => ({ name: `Assessment ${i + 1}` }));
}

function openList() {
    render(
        <MemoryRouter>
            <AssessmentListPage />
        </MemoryRouter>
    );
}

describe("F35: every assessment can be reached from the Assessments page", () => {
    afterEach(cleanup);

    it("reaches an assessment beyond the newest 20", async () => {
        givenAssessments(25);
        openList();
        await screen.findByText("Assessment 1");

        const next = screen.queryByRole("button", { name: /next/i });
        if (next) fireEvent.click(next);

        await vi.waitFor(() =>
            expect(screen.queryByText("Assessment 21"), "the 21st assessment can't be reached from the page").not.toBeNull()
        );
    });

    it("shows a short list in full, with no page controls (control)", async () => {
        givenAssessments(3);
        openList();

        expect(await screen.findByText("Assessment 3")).toBeTruthy();
        expect(screen.queryByRole("button", { name: /next/i })).toBeNull();
    });
});
