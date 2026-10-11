// Shared by the two coach endpoints. Files starting with "_" are not routed by Vercel.
// The Gemini key is read from the environment and never leaves the server.

const MODEL = process.env.GEMINI_MODEL || "gemini-3.6-flash";
const MAX_BODY_BYTES = 8 * 1024;

// Best effort rate limit. This memory belongs to one warm function instance,
// so it slows a single noisy client but is not a real quota. A durable limit
// needs a shared store (follow up).
const WINDOW_MS = 60 * 1000;
const MAX_REQUESTS_PER_WINDOW = 10;
const hits = new Map();

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function clientAddress(req) {
  const forwarded = req.headers["x-forwarded-for"];
  const first = Array.isArray(forwarded) ? forwarded[0] : forwarded || "";
  return first.split(",")[0].trim() || "unknown";
}

function isRateLimited(address) {
  const now = Date.now();
  if (hits.size > 5000) hits.clear();
  const recent = (hits.get(address) || []).filter((time) => now - time < WINDOW_MS);
  if (recent.length >= MAX_REQUESTS_PER_WINDOW) {
    hits.set(address, recent);
    return true;
  }
  recent.push(now);
  hits.set(address, recent);
  return false;
}

function readBody(req) {
  if (Number(req.headers["content-length"] || 0) > MAX_BODY_BYTES) {
    throw fail(413, "Request is too large.");
  }
  let body = req.body;
  if (typeof body === "string") {
    if (Buffer.byteLength(body) > MAX_BODY_BYTES) throw fail(413, "Request is too large.");
    try {
      body = JSON.parse(body);
    } catch {
      throw fail(400, "Body must be JSON.");
    }
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw fail(400, "Body must be a JSON object.");
  }
  if (Buffer.byteLength(JSON.stringify(body)) > MAX_BODY_BYTES) {
    throw fail(413, "Request is too large.");
  }
  return body;
}

async function generate({ system, user, temperature, json }) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw fail(500, "The coach is not configured.");

  const generationConfig = { temperature };
  if (json) generationConfig.responseMimeType = "application/json";

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ role: "user", parts: [{ text: user }] }],
        generationConfig,
      }),
    }
  );
  if (!response.ok) {
    console.error("Gemini request failed", response.status);
    throw fail(502, "The coach is unavailable right now.");
  }

  const data = await response.json();
  const candidate = data && data.candidates && data.candidates[0];
  const parts = (candidate && candidate.content && candidate.content.parts) || [];
  const text = parts
    .filter((part) => !part.thought && typeof part.text === "string")
    .map((part) => part.text)
    .join("");
  if (!text) throw fail(502, "The coach returned nothing.");
  return text;
}

// Wraps an endpoint: POST only, rate limit, size check, JSON in, JSON out.
function endpoint(run) {
  return async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    if (req.method !== "POST") {
      res.setHeader("Allow", "POST");
      return res.status(405).json({ error: "Use POST." });
    }
    if (isRateLimited(clientAddress(req))) {
      return res.status(429).json({ error: "Too many requests. Try again in a minute." });
    }
    try {
      return res.status(200).json(await run(readBody(req)));
    } catch (error) {
      if (!error.status) console.error(error);
      return res
        .status(error.status || 500)
        .json({ error: error.status ? error.message : "Something went wrong." });
    }
  };
}

module.exports = { endpoint, generate, fail };
