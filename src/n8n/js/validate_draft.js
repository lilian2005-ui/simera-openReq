// Check the AI draft before it is saved for human review. Any failed rule -> rejected and logged, nothing saved.
const lead = $('Build Draft Prompt').item.json;
const fail = detail => ({ valid: false, lead_id: lead.lead_id, stage: 'outreach_draft', detail });

const text = ($json.candidates?.[0]?.content?.parts || []).map(p => p.text || '').join('').trim();
if (!text) return fail(`empty AI response (finishReason: ${$json.candidates?.[0]?.finishReason ?? 'none'})`);

let r;
try { r = JSON.parse(text); } catch (e) { return fail('AI response is not valid JSON'); }

const reason = String(r.lead_reason || '').trim();
const subject = String(r.subject || '').trim();
const body = String(r.body || '').replace(/\r/g, '').trim();
if (!reason || !subject || !body) return fail('lead_reason, subject and body are all required');
if (subject.length > 100) return fail(`subject is ${subject.length} characters (max 100)`);

const words = body.split(/\s+/).filter(Boolean).length;
if (words < 120 || words > 180) return fail(`body has ${words} words (allowed 120-180)`);

// Facts check: no invented contact details or links, and at least one real role named.
if (/[\w.+-]+@[\w-]+\.[\w.]+/.test(body)) return fail('body contains an email address (contacts are never generated)');
if (/https?:\/\/|www\./i.test(body)) return fail('body contains a link');
const norm = s => s.toLowerCase().replace(/\(.*?\)/g, ' ').replace(/[^a-z0-9+#.]+/g, ' ').trim();
const named = lead.role_titles.some(t => {
  const core = norm(t).split(' ').slice(0, 3).join(' ');
  return core && norm(body + ' ' + subject).includes(core);
});
if (!named) return fail('draft does not name any of the open roles');
if (/\b(ai|artificial intelligence|talent pool|fit score|himalayas)\b/i.test(body)) return fail('draft mentions internal terms (AI, talent pool, score or source)');

// v2 rule checks: claims the data can never support (found in v1 human review).
const UNSUPPORTED = /\b(immediately|right away|available now|start tomorrow|guarantee[sd]?|perfect(ly)?|ensures?|top \d+%|rigorous(ly)? vetted|best[- ]in[- ]class)\b/i;
const claim = body.match(UNSUPPORTED);
if (claim) return fail(`draft makes an unsupported claim: "${claim[0]}"`);
const GAPS = /\b(lack(s|ing)?|differ(s|ent)? from your|do(es)? not have|don't have|missing|gap)\b/i;
const gap = body.match(GAPS);
if (gap) return fail(`draft mentions a gap or weakness to the client: "${gap[0]}"`);

return { valid: true, lead_id: lead.lead_id, lead_reason: reason.slice(0, 300), subject, body, word_count: words };
