// Validate Gemini's fit score before saving: integer 0-100 and a non-empty reason (else rejected and logged).
const jobId = $('Validate Requirements').item.json.job_id;
const fail = detail => ({ valid: false, job_id: jobId, stage: 'fit_scoring', detail });

const text = ($json.candidates?.[0]?.content?.parts || []).map(p => p.text || '').join('').trim();
if (!text) return fail(`empty AI response (finishReason: ${$json.candidates?.[0]?.finishReason ?? 'none'})`);

let r;
try { r = JSON.parse(text); } catch (e) { return fail('AI response is not valid JSON'); }

if (!Number.isInteger(r.fit_score) || r.fit_score < 0 || r.fit_score > 100)
  return fail(`fit_score ${JSON.stringify(r.fit_score)} is not an integer between 0 and 100`);

const reason = String(r.fit_reason || '').trim();
if (!reason) return fail('fit_reason is empty');

const ids = Array.isArray(r.matching_candidate_ids) ? r.matching_candidate_ids.filter(Number.isInteger) : [];

// RULE (not AI): no extracted required skills = no evidence for a high score. Cap at 30.
// Found in human review: 95 and 85 were given to a per-task gig and an empty template posting.
const required = $('Validate Requirements').item.json.requirements?.required_skills || [];
let score = r.fit_score;
let finalReason = reason;
if (required.length === 0 && score > 30) {
  finalReason = `[capped from ${score} to 30: no required skills in the posting] ${reason}`;
  score = 30;
}

return {
  valid: true,
  job_id: jobId,
  fit_score: score,
  fit_reason: finalReason.slice(0, 300),
  matching_candidate_ids: ids,
};
