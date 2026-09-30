// @vitest-environment jsdom
import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useAudioWebSocket } from "./useAudioWebSocket";

// Audit F25: when the live connection dropped and the reconnect attempts ran out, the
// candidate was shown "Interview Complete — the interview has been recorded", although
// nothing was recorded. Only a real end from the server may be reported as complete.

class FakeWebSocket {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;
    static opened: FakeWebSocket[] = [];

    readyState = FakeWebSocket.CONNECTING;
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
    // helpers for the test
    serverSends(message: object) {
        this.onmessage?.({ data: JSON.stringify(message) });
    }
    drops() {
        this.readyState = FakeWebSocket.CLOSED;
        this.onclose?.();
    }
}

const last = <T,>(items: T[]): T => items[items.length - 1];

function renderInterviewConnection() {
    const states: string[] = [];
    const { result } = renderHook(() =>
        useAudioWebSocket({
            sessionId: 7,
            token: "invite-token",
            onAudioChunk: () => {},
            onTranscript: () => {},
            onStateChange: (s) => states.push(s),
            onSpeakerChange: () => {},
        })
    );
    act(() => result.current.connect());
    return states;
}

describe("F25: a lost connection is never shown to the candidate as a finished interview", () => {
    beforeEach(() => {
        FakeWebSocket.opened = [];
        vi.useFakeTimers();
        vi.stubGlobal("WebSocket", FakeWebSocket);
    });
    afterEach(() => {
        vi.useRealTimers();
        vi.unstubAllGlobals();
    });

    it("does not report 'complete' when the connection drops and every reconnect fails", () => {
        const states = renderInterviewConnection();

        // The first connection and every reconnect attempt drop.
        for (let i = 0; i < 10; i++) {
            const socket = last(FakeWebSocket.opened);
            act(() => socket.drops());
            act(() => vi.advanceTimersByTime(10_000));
        }

        expect(states).toContain("reconnecting");
        expect(states).not.toContain("complete");
    });

    it("still reports 'complete' when the server ends the interview (control)", () => {
        const states = renderInterviewConnection();
        const socket = last(FakeWebSocket.opened);

        act(() => socket.serverSends({ type: "session_ended", reason: "all_covered" }));

        expect(last(states)).toBe("complete");
    });
});
