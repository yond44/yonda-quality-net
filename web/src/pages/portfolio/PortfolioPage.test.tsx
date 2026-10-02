// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";

// Audit F35: the fit/gap "Choose vacancy" list on the portfolio page only offered the
// newest 20 vacancies. A candidate could not be compared with an older vacancy at all.
// Found in the soak test.

// The HTTP layer is faked, so this holds whatever way the page asks for the vacancies.
let vacancies: string[] = [];
vi.mock("@/services/api", () => ({
    WS_URL: "",
    default: {
        get: vi.fn(async (url: string, config?: { params?: { page?: number; per_page?: number } }) => {
            if (url === "/sessions/7/portfolio")
                return { data: { portfolio: { id: 3, session_id: 7, generation_status: "complete", skills: [], overrides: [] } } };
            if (url === "/sessions/7") return { data: { session: { id: 7, candidate_name: "Rina" } } };
            if (url === "/vacancies") {
                const perPage = Math.min(config?.params?.per_page ?? 20, 100);
                const page = config?.params?.page ?? 1;
                const items = vacancies.slice((page - 1) * perPage, page * perPage)
                    .map((title, i) => ({ id: (page - 1) * perPage + i + 1, role_title: title }));
                return {
                    data: {
                        vacancies: items,
                        meta: { current_page: page, per_page: perPage, total_count: vacancies.length, total_pages: Math.ceil(vacancies.length / perPage) },
                    },
                };
            }
            throw new Error(`unexpected GET ${url}`);
        }),
    },
}));

import PortfolioPage from "./PortfolioPage";

// The dropdown (Radix Select) uses browser functions the test browser doesn't have.
beforeAll(() => {
    Element.prototype.hasPointerCapture ??= () => false;
    Element.prototype.setPointerCapture ??= () => {};
    Element.prototype.releasePointerCapture ??= () => {};
    Element.prototype.scrollIntoView ??= () => {};
});

async function openVacancyChoices(count: number) {
    vacancies = Array.from({ length: count }, (_, i) => `Vacancy ${i + 1}`);
    render(
        <MemoryRouter initialEntries={["/assessments/1/sessions/7/portfolio"]}>
            <Routes>
                <Route path="/assessments/:id/sessions/:sessionId/portfolio" element={<PortfolioPage />} />
            </Routes>
        </MemoryRouter>
    );
    // wait until the page has loaded its vacancies (a mocked request is instant, but async)
    await screen.findByText("Run Fit/Gap Analysis →");
    await new Promise((r) => setTimeout(r, 50));
    const trigger = screen.getByRole("combobox");
    trigger.focus();
    fireEvent.keyDown(trigger, { key: "ArrowDown" }); // opens the list, as a keyboard user would
    await screen.findAllByRole("option");
}

describe("F35: fit/gap can use any of the company's vacancies", () => {
    afterEach(cleanup);

    it("offers a vacancy beyond the newest 20 in the fit/gap choice", async () => {
        await openVacancyChoices(25);

        await vi.waitFor(() =>
            expect(screen.queryByRole("option", { name: "Vacancy 25" }), "an older vacancy isn't offered for fit/gap").not.toBeNull()
        );
    });

    it("still offers every vacancy when there are only a few (control)", async () => {
        await openVacancyChoices(3);

        expect(screen.getAllByRole("option").map((o) => o.textContent)).toEqual(["Vacancy 1", "Vacancy 2", "Vacancy 3"]);
    });
});
