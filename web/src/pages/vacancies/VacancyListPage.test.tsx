// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { afterEach, describe, expect, it, vi } from "vitest";

// Audit F35: the Vacancies page only ever showed the newest 20 vacancies, with no way to
// see more. An older vacancy could only be opened by typing its URL. Found in the soak test.

// The HTTP layer is faked, so this holds whatever way the page asks for the other pages.
let all: { role_title: string }[] = [];
vi.mock("@/services/api", () => ({
    WS_URL: "",
    default: {
        get: vi.fn(async (url: string, config?: { params?: { page?: number; per_page?: number } }) => {
            if (url !== "/vacancies") throw new Error(`unexpected GET ${url}`);
            const perPage = Math.min(config?.params?.per_page ?? 20, 100);
            const page = config?.params?.page ?? 1;
            const items = all.slice((page - 1) * perPage, page * perPage)
                .map((v, i) => ({ id: (page - 1) * perPage + i + 1, role_title: v.role_title }));
            return {
                data: {
                    vacancies: items,
                    meta: { current_page: page, per_page: perPage, total_count: all.length, total_pages: Math.ceil(all.length / perPage) },
                },
            };
        }),
    },
}));

import VacancyListPage from "./VacancyListPage";

function givenVacancies(count: number) {
    all = Array.from({ length: count }, (_, i) => ({ role_title: `Vacancy ${i + 1}` }));
}

function openList() {
    render(
        <MemoryRouter>
            <VacancyListPage />
        </MemoryRouter>
    );
}

describe("F35: every vacancy can be reached from the Vacancies page", () => {
    afterEach(cleanup);

    it("reaches a vacancy beyond the newest 20", async () => {
        givenVacancies(25);
        openList();
        await screen.findByText("Vacancy 1");

        const next = screen.queryByRole("button", { name: /next/i });
        if (next) fireEvent.click(next);

        await vi.waitFor(() =>
            expect(screen.queryByText("Vacancy 21"), "the 21st vacancy can't be reached from the page").not.toBeNull()
        );
    });

    it("shows a short list in full, with no page controls (control)", async () => {
        givenVacancies(3);
        openList();

        expect(await screen.findByText("Vacancy 3")).toBeTruthy();
        expect(screen.queryByRole("button", { name: /next/i })).toBeNull();
    });
});
