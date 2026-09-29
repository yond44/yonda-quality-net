// Internet check before the interview (audit F24).
//
// It answers one question: can this connection carry the interview? So it measures
// the path the interview really uses (our own backend) where it can, one measurement
// at a time, and never invents a number: a measurement that fails means "couldn't
// check", which is not a pass.

export interface InternetSpeedResult {
    download: number;
    upload: number;
    ping: number;
    passed: boolean;
    /** false when download, upload or ping couldn't be measured at all; the numbers then mean nothing */
    measured: boolean;
    downloadTests: number[];
    uploadTests: number[];
    pingTests: number[];
}

export interface SpeedThresholds {
    minDownloadMbps: number;
    minUploadMbps: number;
    maxPingMs: number;
}

// The interview is voice only (no video is sent). The browser sends 16 kHz 16-bit mono
// audio, about 0.26 Mbps (useAudioCapture), and receives 24 kHz audio, about 0.38 Mbps
// (useAudioPlayback). The limits are those rates with about 4x headroom for WebSocket
// framing, transcripts and jitter. No spec defines them: this is an assumption (audit M10).
export const DEFAULT_THRESHOLDS: SpeedThresholds = {
    minDownloadMbps: 1.5,
    minUploadMbps: 1,
    maxPingMs: 300,
};

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:3000/api/v1";
// Our own backend: the same place the interview audio goes. Overridable for special setups.
const PING_URL = import.meta.env.VITE_SPEED_TEST_PING_URL || `${API_BASE_URL}/health`;
const UPLOAD_URL = import.meta.env.VITE_SPEED_TEST_UPLOAD_URL || `${API_BASE_URL}/speed_test`;
// The backend has no download endpoint, so download is timed on public CDN files.
const DOWNLOAD_URLS = [
    "https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css",
    "https://unpkg.com/react@18/umd/react.development.js",
    "https://cdn.jsdelivr.net/npm/jquery@3.6.0/dist/jquery.min.js",
];
const UPLOAD_BYTES = 256 * 1024;
const RUNS = 3;

const toMbps = (bytes: number, ms: number) => (bytes * 8) / 1e6 / (ms / 1000);

// Each measurement returns null when it couldn't be taken. An HTTP error is a failure,
// not a very fast answer.
async function measurePing(): Promise<number | null> {
    try {
        const start = performance.now();
        const res = await fetch(PING_URL, { cache: "no-store" });
        const ms = performance.now() - start;
        return res.ok ? ms : null;
    } catch {
        return null;
    }
}

async function measureDownloadSpeed(): Promise<number | null> {
    for (const url of DOWNLOAD_URLS) {
        try {
            const start = performance.now();
            const res = await fetch(url, { cache: "no-store" });
            if (!res.ok) continue;
            const bytes = (await res.arrayBuffer()).byteLength;
            return toMbps(bytes, performance.now() - start);
        } catch {
            continue;
        }
    }
    return null;
}

async function measureUploadSpeed(): Promise<number | null> {
    try {
        const body = new Blob([new ArrayBuffer(UPLOAD_BYTES)], { type: "application/octet-stream" });
        const start = performance.now();
        const res = await fetch(UPLOAD_URL, { method: "POST", body, cache: "no-store" });
        const ms = performance.now() - start;
        return res.ok ? toMbps(UPLOAD_BYTES, ms) : null;
    } catch {
        return null;
    }
}

// One run after another: parallel runs would compete for the same connection.
async function runInSequence(measure: () => Promise<number | null>, count = RUNS): Promise<number[]> {
    const results: number[] = [];
    for (let i = 0; i < count; i++) {
        const value = await measure();
        if (value !== null) results.push(value);
    }
    return results;
}

function average(values: number[]): number {
    if (values.length === 0) return 0;
    if (values.length <= 2) return values.reduce((a, b) => a + b, 0) / values.length;
    const sorted = [...values].sort((a, b) => a - b);
    const trimmed = sorted.slice(1, -1);
    return trimmed.reduce((a, b) => a + b, 0) / trimmed.length;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

export async function testInternetSpeed(
    thresholds: SpeedThresholds = DEFAULT_THRESHOLDS
): Promise<InternetSpeedResult> {
    const pingTests = await runInSequence(measurePing);
    const downloadTests = await runInSequence(measureDownloadSpeed);
    const uploadTests = await runInSequence(measureUploadSpeed);

    const measured = pingTests.length > 0 && downloadTests.length > 0 && uploadTests.length > 0;
    const download = average(downloadTests);
    const upload = average(uploadTests);
    const ping = average(pingTests);

    const passed =
        measured &&
        download >= thresholds.minDownloadMbps &&
        upload >= thresholds.minUploadMbps &&
        ping <= thresholds.maxPingMs;

    return {
        download: round2(download),
        upload: round2(upload),
        ping: Math.round(ping),
        passed,
        measured,
        downloadTests: downloadTests.map(round2),
        uploadTests: uploadTests.map(round2),
        pingTests: pingTests.map((v) => Math.round(v)),
    };
}
