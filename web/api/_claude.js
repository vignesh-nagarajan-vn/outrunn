// Shared by the two coach endpoints. Files starting with "_" are not routed by Vercel.
// The SDK reads ANTHROPIC_API_KEY from the environment. The key never leaves the server.

const sdk = require("@anthropic-ai/sdk");
const Anthropic = sdk.default || sdk;

const MODEL = process.env.CLAUDE_MODEL || "claude-sonnet-5-5";
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

// One request, one answer. Thinking is adaptive on this model; effort sets its depth.
// If the model declines on policy grounds, the API retries on its recommended fallback.
async function generate({ system, user, effort }) {
  if (!process.env.ANTHROPIC_API_KEY) throw fail(500, "The coach is not configured.");
  const client = new Anthropic();

  let response;
  try {
    response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      system,
      messages: [{ role: "user", content: user }],
      output_config: { effort },
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
    });
  } catch (error) {
    if (error instanceof Anthropic.AuthenticationError) {
      console.error("Claude rejected the API key");
      throw fail(500, "The coach is not configured.");
    }
    if (error instanceof Anthropic.RateLimitError) {
      throw fail(429, "The coach is busy. Try again in a minute.");
    }
    if (error instanceof Anthropic.APIError) {
      console.error("Claude request failed", error.status, error.message);
      throw fail(502, "The coach is unavailable right now.");
    }
    throw error;
  }

  if (response.stop_reason === "refusal") {
    throw fail(502, "The coach declined to answer that.");
  }
  const text = response.content
    .filter((block) => block.type === "text")
    .map((block) => block.text)
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
