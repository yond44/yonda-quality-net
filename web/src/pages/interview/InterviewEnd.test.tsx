// @vitest-environment jsdom
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Audit F31: a candidate who ended the interview (End Interview, or the time limit ran
// out) was shown "Connection lost — your interview has not ended. Reconnect", although
// the server had recorded it as finished. Found in the end-to-end browser test.

const getCandidateInfo = vi.fn();
vi.mock("@/services/sessions", () => ({
    sessionsApi: { getCandidateInfo: (token: string) => getCandidateInfo(token), audioComplete: vi.fn() },
}));
// Hardware, microphone and speakers aren't available in a test browser: stand-ins that
// let the real page logic run.
vi.mock("@/components/HardwareCheck", () => ({
    default: ({ onStart }: { onStart: () => void }) => <button onClick={onStart}>Start Interview</button>,
}));
vi.mock("@/hooks/useAudioCapture", () => ({
    useAudioCapture: () => ({ start: async () => {}, stop: () => {}, mute: () => {}, unmute: () => {} }),
}));
vi.mock("@/hooks/useAudioPlayback", () => ({
    useAudioPlayback: () => ({
        playChunk: () => {}, stop: () => {}, scheduleAfterPlayback: (fn: () => void) => fn(),
        waitForDrain: () => {}, cancelDrain: () => {},
    }),
}));
// The real timer counts down minutes; this one lets the test say "time is up".
vi.mock("@/components/interview/InterviewTimer", () => ({
    default: ({ onExpired }: { onExpired: () => void }) => <button onClick={onExpired}>time is up</button>,
}));

import InterviewPage from "./InterviewPage";

class FakeWebSocket {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;
    static opened: FakeWebSocket[] = [];

    readyState = FakeWebSocket.OPEN;
    binaryType = "blob";
    onopen: (() => void) | null = null;
    onmessage: ((e: { data: unknown }) => void) | null = null;
    onerror: (() => void) | null = null;
    onclose: (() => void) | null = null;

    constructor(public url: string) {
        FakeWebSocket.opened.push(this);
    }
    send() {}
    close() {
        this.readyState = FakeWebSocket.CLOSED;
    }
    serverSends(message: object) {
        this.onmessage?.({ data: JSON.stringify(message) });
    }
    browserReportsClosed() {
        this.readyState = FakeWebSocket.CLOSED;
        this.onclose?.();
    }
}

const last = <T,>(items: T[]): T => items[items.length - 1];

async function startInterview() {
    getCandidateInfo.mockResolvedValue({
        data: { session_id: 7, role_title: "Frontend Engineer", time_limit_min: 10, session_status: "pending" },
    });
    render(
        <MemoryRouter initialEntries={["/interview/invite-token"]}>
            <Routes>
                <Route path="/interview/:token" element={<InterviewPage />} />
            </Routes>
        </MemoryRouter>
    );
    fireEvent.click(await screen.findByRole("button", { name: "Start Interview" }));
    await act(async () => {});
    act(() => last(FakeWebSocket.opened).serverSends({ type: "session_started", session_id: 7 }));
    return last(FakeWebSocket.opened);
}

describe("F31: a candidate who ends the interview is told it's complete", () => {
    beforeEach(() => {
        FakeWebSocket.opened = [];
        vi.stubGlobal("WebSocket", FakeWebSocket);
    });
    afterEach(() => {
        cleanup();
        vi.unstubAllGlobals();
        getCandidateInfo.mockReset();
    });

    it("shows 'Interview Complete', not 'Connection lost', after End Interview", async () => {
        const socket = await startInterview();

        fireEvent.click(screen.getByRole("button", { name: "End Interview" }));
        fireEvent.click(await screen.findByRole("button", { name: "End interview" })); // confirm
        act(() => socket.browserReportsClosed());

        expect(screen.queryByText("Connection lost")).toBeNull();
        expect(screen.getByText("Interview Complete")).toBeTruthy();
    });

    it("shows 'Interview Complete', not 'Connection lost', when the time runs out", async () => {
        const socket = await startInterview();

        fireEvent.click(screen.getByRole("button", { name: "time is up" }));
        act(() => socket.browserReportsClosed());

        expect(screen.queryByText("Connection lost")).toBeNull();
        expect(screen.getByText("Interview Complete")).toBeTruthy();
    });

    it("still offers to reconnect when the connection really drops (control)", async () => {
        vi.useFakeTimers({ shouldAdvanceTime: true });
        try {
            await startInterview();

            for (let i = 0; i < 10; i++) {
                act(() => last(FakeWebSocket.opened).browserReportsClosed());
                act(() => vi.advanceTimersByTime(10_000));
            }

            expect(screen.getByText("Connection lost")).toBeTruthy();
            expect(screen.queryByText("Interview Complete")).toBeNull();
        } finally {
            vi.useRealTimers();
        }
    });
});
