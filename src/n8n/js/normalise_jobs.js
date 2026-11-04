// Normalise Himalayas postings into our JobPosting shape (Data Contract, stage 1).
// Rules: description_text = HTML removed + spaces collapsed; dates -> ISO 8601 UTC; unknown -> null (never guess).
const body = $input.first().json;
const jobs = Array.isArray(body.jobs) ? body.jobs : [];

const decode = s => s
  .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"').replace(/&#39;|&#x27;/g, "'").replace(/&amp;/g, '&');

const clean = html => decode(String(html || '')
    .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<[^>]+>/g, ' '))
  .replace(/\s+/g, ' ')
  .trim();

// Himalayas sends Unix timestamps in milliseconds; accept seconds too, just in case.
const toIso = v => (typeof v === 'number' && v > 0) ? new Date(v < 1e12 ? v * 1000 : v).toISOString() : null;

// Countries the company can hire in (Himalayas "locationRestrictions"). Empty list = open worldwide.
// Accepts plain strings or objects like { name: "Germany" }.
const places = v => (Array.isArray(v) ? v : [])
  .map(x => (typeof x === 'string' ? x : (x && (x.name || x.country || x.label)) || ''))
  .map(x => String(x).trim()).filter(Boolean);

const out = jobs.map(j => ({
  external_id: j.guid ?? null,
  url: j.applicationLink ?? null,
  title: (j.title || '').trim(),
  company_name: (j.companyName || '').trim(),
  description_raw: j.description || '',
  description_text: clean(j.description),
  posted_at: toIso(j.pubDate),
  expires_at: toIso(j.expiryDate),
  location_restrictions: places(j.locationRestrictions),
}));

return [{ json: { run_id: $('Start Run').first().json.run_id, count: out.length, jobs: out } }];
