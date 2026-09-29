import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Audit F24: the pre-interview internet check blocked candidates whose connection
// easily carries the voice interview (reported: 129 Mbps down, 2.96 Mbps up, 22 ms,
// "Failed"). It timed uploads against public echo servers, ran every measurement at
// once, and invented numbers when a measurement failed.
//
// These tests run the real check against a simulated network: every request takes
// the time the given speed and ping would really need, on a fake clock.

const API = "http://api.test/api/v1";

type Network = {
    downMbps: number;
    upMbps: number;
    pingMs: number;
    upload?: "network-error" | "http-500";
};

function bodyBytes(body: unknown): number {
    if (body instanceof Blob) return body.size;
    if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) return body.byteLength;
    if (body instanceof FormData) {
        let bytes = 0;
        body.forEach((v) => (bytes += typeof v === "string" ? v.length : v.size));
        return bytes;
    }
    return 0;
}

function simulateNetwork(net: Network) {
    let clock = 0;
    let inFlight = 0;
    const seen = { uploadUrls: [] as string[], maxInFlight: 0 };
    const transferMs = (bytes: number, mbps: number) => ((bytes * 8) / (mbps * 1e6)) * 1000;

    vi.spyOn(performance, "now").mockImplementation(() => clock);
    vi.stubGlobal("fetch", async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input);
        inFlight++;
        seen.maxInFlight = Math.max(seen.maxInFlight, inFlight);
        await new Promise((r) => setTimeout(r, 0)); // let other pending requests start, as on a real network
        try {
            if ((init?.method ?? "GET").toUpperCase() === "POST") {
                seen.uploadUrls.push(url);
                if (net.upload === "network-error") throw new TypeError("Failed to fetch");
                if (net.upload === "http-500") {
                    clock += 1;
                    return new Response("server error", { status: 500 });
                }
                clock += net.pingMs + transferMs(bodyBytes(init?.body), net.upMbps);
                return new Response('{"received_bytes":0}', { status: 200 });
            }
            const isFile = /\.(css|js)$/.test(new URL(url).pathname);
            const size = isFile ? 500_000 : 20;
            clock += net.pingMs + transferMs(size, net.downMbps);
            return new Response(new Uint8Array(size), { status: 200 });
        } finally {
            inFlight--;
        }
    });
    return seen;
}

async function loadCheck() {
    vi.resetModules(); // the module reads its settings when it loads
    return import("./internetSpeedTest");
}

describe("F24: the internet check passes a connection that can carry the interview", () => {
    beforeEach(() => {
        vi.stubEnv("VITE_API_BASE_URL", API);
        vi.stubEnv("VITE_SPEED_TEST_UPLOAD_URL", "");
        vi.stubEnv("VITE_SPEED_TEST_PING_URL", "");
    });
    afterEach(() => {
        vi.unstubAllEnvs();
        vi.unstubAllGlobals();
        vi.restoreAllMocks();
    });

    it("passes the connection from the bug report (129 Mbps down, 2.96 Mbps up, 22 ms)", async () => {
        const { testInternetSpeed } = await loadCheck();
        simulateNetwork({ downMbps: 129, upMbps: 2.96, pingMs: 22 });

        expect((await testInternetSpeed()).passed).toBe(true);
    });

    it("still fails a connection too slow for the interview audio (control: not a blanket pass)", async () => {
        const { testInternetSpeed } = await loadCheck();
        simulateNetwork({ downMbps: 129, upMbps: 0.2, pingMs: 22 });

        expect((await testInternetSpeed()).passed).toBe(false);
    });

    it("measures the upload on the path the interview uses (our own backend)", async () => {
        const { testInternetSpeed } = await loadCheck();
        const seen = simulateNetwork({ downMbps: 129, upMbps: 2.96, pingMs: 22 });

        await testInternetSpeed();

        expect(seen.uploadUrls.length).toBeGreaterThan(0);
        expect(seen.uploadUrls.every((u) => u.startsWith(API))).toBe(true);
    });

    it("never passes a candidate when the upload cannot be measured", async () => {
        const { testInternetSpeed } = await loadCheck();
        simulateNetwork({ downMbps: 129, upMbps: 2.96, pingMs: 22, upload: "network-error" });

        expect((await testInternetSpeed()).passed).toBe(false);
    });

    it("does not count an error page as a fast upload", async () => {
        const { testInternetSpeed } = await loadCheck();
        simulateNetwork({ downMbps: 129, upMbps: 2.96, pingMs: 22, upload: "http-500" });

        expect((await testInternetSpeed()).passed).toBe(false);
    });

    it("measures one thing at a time, so the measurements don't slow each other down", async () => {
        const { testInternetSpeed } = await loadCheck();
        const seen = simulateNetwork({ downMbps: 129, upMbps: 2.96, pingMs: 22 });

        await testInternetSpeed();

        expect(seen.maxInFlight).toBe(1);
    });
});
