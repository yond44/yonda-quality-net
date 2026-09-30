// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, describe, expect, it, vi } from "vitest";

// Audit F25: if the interview page couldn't load the interview (server down, network
// error, rate limit), it showed "Interview Complete — the interview has been recorded".
// The candidate can't tell "finished" from "broken", and leaves.

const getCandidateInfo = vi.fn();
vi.mock("@/services/sessions", () => ({
    sessionsApi: { getCandidateInfo: (token: string) => getCandidateInfo(token), audioComplete: vi.fn() },
}));
// The hardware check uses camera, microphone and network APIs a test browser doesn't have.
vi.mock("@/components/HardwareCheck", () => ({ default: () => <div>hardware check</div> }));

import InterviewPage from "./InterviewPage";

function openInviteLink() {
    render(
        <MemoryRouter initialEntries={["/interview/invite-token"]}>
            <Routes>
                <Route path="/interview/:token" element={<InterviewPage />} />
            </Routes>
        </MemoryRouter>
    );
}

describe("F25: an interview page that can't load is not shown as a finished interview", () => {
    afterEach(() => {
        cleanup();
        getCandidateInfo.mockReset();
    });

    it("does not say 'Interview Complete' when the interview can't be loaded", async () => {
        getCandidateInfo.mockRejectedValue(new Error("Network Error"));

        openInviteLink();
        await vi.waitFor(() => expect(getCandidateInfo).toHaveBeenCalled());
        await new Promise((r) => setTimeout(r, 0)); // let the failed request settle

        expect(screen.queryByText("Interview Complete")).toBeNull();
    });

    it("still says 'Interview Complete' for an interview that really ended (control)", async () => {
        getCandidateInfo.mockResolvedValue({
            data: { session_id: 7, role_title: "Role", time_limit_min: 30, session_status: "ended" },
        });

        openInviteLink();

        expect(await screen.findByText("Interview Complete")).toBeTruthy();
    });
});
