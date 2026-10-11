// POST /api/plan
// Body: { "snapshot": { numbers from the app } }
// Returns the written plan. The model explains the app's numbers and never changes them.

const { endpoint, generate, fail } = require("./_gemini");

const SYSTEM = `You are outrunn's recovery coach. Inputs are numbers only (a phone camera scan plus Apple Health). Never video.

The ages (biologicalAge, cardiacAge, pulmonaryAge) and the factors list come from outrunn's engine and are final. Each factor is that input's contribution to biologicalAge in years; negative is younger. Explain these numbers. Never output an age of your own and never say the real number should be different.

Any field that is missing was not measured. Say there is not enough data for it. Do not guess it. If cardiacAge is missing, say Cardiac Age needs Apple Health heart rate data.

Compare TWO layers:
1) Scan (scanHeartRate, scanRespiratoryRate, heartRateRecovery, scanHrvRMSSD, stressIndex, scanPulseConfidence): camera physiology at this moment.
2) Apple Health (restingHeartRate, hrvSDNN, sleepHours, steps): last-day and last-week lifestyle.

scanHrvRMSSD and hrvSDNN are different HRV measures. Do not compare them to each other as if they were the same unit.

Use minutesSinceWorkout (set by the user, 0-240) as ground truth for the recovery phase:
- Under 15 min: elevated heart rate is expected; say the scan reflects incomplete recovery.
- 15-60 min: heart rate recovery is most meaningful.
- Hours later: heart rate should be near restingHeartRate; leftover elevation is recovery debt.
Always mention this window in recoveryWindow.

heartRateRecovery is the drop from the recent Apple Health peak to the scan heart rate. It is not a clinical one minute test. If sleep or steps are poor, attribute that part of an older age to lifestyle, not to the scan. If scanPulseConfidence is under 70, say the scan signal was weak.

Voice: warm, specific, plain. Short paragraphs. No diagnosis, no drugs, no supplements.

Return JSON:
headline (1 punchy sentence),
summary (2-4 readable sentences),
scanVsLifestyle (how the scan and Apple Health agree or disagree),
recoveryWindow (plain language about time since workout),
drivers (array of {factor, impact: helping|hurting|neutral, note}, max 4),
plan {
  today (2-4 bullets),
  thisWeek (2-4 bullets),
  training (2-4 bullets),
  recovery (2-4 bullets),
  longTerm (2-4 bullets about 8-12 week improvement: zone 2 consistency, VO2 work, sleep regularity, strength)
},
caution (string or null).`;

const REQUIRED = [
  "chronologicalAge",
  "biologicalAge",
  "pulmonaryAge",
  "scanCount",
  "minutesSinceWorkout",
  "scanHeartRate",
  "scanRespiratoryRate",
  "scanPulseConfidence",
];
const OPTIONAL = [
  "cardiacAge",
  "heartRateRecovery",
  "scanHrvRMSSD",
  "stressIndex",
  "sleepHours",
  "steps",
  "restingHeartRate",
  "hrvSDNN",
];

// Only known numeric fields and short factor names reach the model.
function cleanSnapshot(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw fail(400, "snapshot must be an object.");
  }
  const snapshot = {};
  for (const key of REQUIRED) {
    if (!Number.isFinite(input[key])) throw fail(400, `snapshot.${key} must be a number.`);
    snapshot[key] = input[key];
  }
  for (const key of OPTIONAL) {
    if (input[key] === undefined || input[key] === null) continue;
    if (!Number.isFinite(input[key])) throw fail(400, `snapshot.${key} must be a number.`);
    snapshot[key] = input[key];
  }
  const factors = input.factors === undefined ? [] : input.factors;
  if (!Array.isArray(factors) || factors.length > 10) {
    throw fail(400, "snapshot.factors must be a short list.");
  }
  snapshot.factors = factors.map((factor) => {
    const valid =
      factor &&
      typeof factor.name === "string" &&
      /^[A-Za-z ]{1,40}$/.test(factor.name) &&
      Number.isFinite(factor.years);
    if (!valid) throw fail(400, "snapshot.factors is not valid.");
    return { name: factor.name, years: factor.years };
  });
  return snapshot;
}

function text(value, max) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function bullets(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => text(item, 400))
    .filter(Boolean)
    .slice(0, 6);
}

function drivers(value) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => item && typeof item === "object")
    .map((item) => ({
      factor: text(item.factor, 80),
      impact: ["helping", "hurting"].includes(item.impact) ? item.impact : "neutral",
      note: text(item.note, 400),
    }))
    .filter((item) => item.factor)
    .slice(0, 4);
}

module.exports = endpoint(async (body) => {
  const snapshot = cleanSnapshot(body.snapshot);
  const raw = await generate({
    system: SYSTEM,
    user: `Explain this outrunn snapshot and return JSON only:\n${JSON.stringify(snapshot)}`,
    temperature: 0.4,
    json: true,
  });

  let parsed;
  try {
    parsed = JSON.parse(raw.replace(/```json|```/g, "").trim());
  } catch {
    throw fail(502, "The coach returned an unreadable plan.");
  }
  const summary = text(parsed && parsed.summary, 1200);
  if (!summary) throw fail(502, "The coach returned an unreadable plan.");
  const sections = (parsed.plan && typeof parsed.plan === "object" && parsed.plan) || {};

  return {
    headline: text(parsed.headline, 200) || summary,
    summary,
    scanVsLifestyle: text(parsed.scanVsLifestyle, 1200),
    recoveryWindow: text(parsed.recoveryWindow, 600),
    drivers: drivers(parsed.drivers),
    today: bullets(sections.today),
    thisWeek: bullets(sections.thisWeek),
    training: bullets(sections.training),
    recovery: bullets(sections.recovery),
    longTerm: bullets(sections.longTerm),
    caution: text(parsed.caution, 600) || null,
  };
});
