// POST /api/ask: answers a question about this app, from this site's own words only.
// One file, copied to all three Testament Made app sites (Dinky, Binky, Slinky). Needs a Workers AI binding
// named AI on the Pages project. Knowledge is the site's /ask.json (FAQ with anchors, app name, voice),
// /homepage.md and /llms.txt, plus the site's comparisons with other apps (ask.json's `compare`). Sources are picked here, by plain word overlap, so the links under an answer
// always point at real FAQ entries; the model only writes the short answer.
//
// Streams Server-Sent Events: `sources` (JSON list), then `t` events with text, then `done`.

const MODEL = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';
const MAX_Q = 280;
// Bump when the prompt or what answers are grounded in changes, so cached answers start over.
const ANSWERS = 3;

// Anything that looks like a key, token or private key. Never sent to the model, never cached.
const SECRET = /(sk[-_](?:live|test|proj|ant)[-_A-Za-z0-9]{12,}|\bgh[pousr]_[A-Za-z0-9]{20,}|\bxox[abprs]-[A-Za-z0-9-]{10,}|\bAKIA[0-9A-Z]{16}\b|\bAIza[0-9A-Za-z_-]{30,}|\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?=[A-Za-z0-9_\-+/=]*\d)(?=[A-Za-z0-9_\-+/=]*[A-Za-z])[A-Za-z0-9_\-+/=]{32,}\b)/;

const STOP = new Set('a an and are as at be but by can do does for from how i if in is it its me my of on or so that the this to was what when where which who why will with you your'.split(' '));
// Lowercase words, minus filler, with a plural 's' dropped so "password" meets "passwords".
const words = (s) => s.toLowerCase().replace(/[^a-z0-9.]+/g, ' ').split(' ').filter((w) => w.length > 2 && !STOP.has(w)).map((w) => (w.length > 3 ? w.replace(/s$/, '') : w));

let knowledge = null;
async function load(env, origin) {
  if (knowledge) return knowledge;
  const get = async (path) => {
    const r = await env.ASSETS.fetch(new URL(path, origin).toString());
    return r.ok ? r.text() : '';
  };
  const [askJson, home, llms] = await Promise.all([get('/ask.json'), get('/homepage.md'), get('/llms.txt')]);
  const site = JSON.parse(askJson || '{}');
  knowledge = { site, home, llms };
  return knowledge;
}

function pickSources(q, faq, app) {
  // The app's own name is in most questions and most answers, so it says nothing about which one fits.
  const want = new Set(words(q).filter((w) => w !== String(app).toLowerCase()));
  return faq
    .map((f) => ({ f, score: words(`${f.q} ${f.q} ${f.a}`).filter((w) => want.has(w)).length }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score)
    .filter((x, i, all) => i === 0 || x.score * 2 >= all[0].score)
    .slice(0, 2)
    .map(({ f }) => ({ id: f.id, q: f.q }));
}

const sse = (event, data) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;

function stream(parts) {
  const enc = new TextEncoder();
  return new Response(new ReadableStream({ start(c) { for (const p of parts) c.enqueue(enc.encode(p)); c.close(); } }), {
    headers: { 'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'no-store' },
  });
}

export async function onRequestPost({ request, env, waitUntil }) {
  // Only this site's own pages may ask (and localhost while developing).
  const origin = request.headers.get('origin');
  const self = new URL(request.url);
  if (origin && new URL(origin).host !== self.host && !/^localhost(:\d+)?$/.test(new URL(origin).host)) {
    return new Response('Not allowed', { status: 403 });
  }
  let q = '';
  try { q = String((await request.json()).q || '').replace(/\s+/g, ' ').trim(); } catch { /* empty */ }
  if (q.length < 2 || q.length > MAX_Q) return new Response('Ask a question of up to 280 characters.', { status: 400 });

  const { site, home, llms } = await load(env, self.origin);
  const app = site.app || 'this app';

  if (SECRET.test(q)) {
    return stream([
      sse('sources', []),
      sse('t', { t: `That looks like a key or token, so I didn't send it anywhere. Please don't paste secrets into websites, this one included.${app === 'Slinky' ? ' Keep it in Slinky.' : ''}` }),
      sse('done', {}),
    ]);
  }

  const sources = pickSources(q, site.faq || [], app);

  // Repeat questions come from the cache.
  const key = new Request(`https://ask.cache/${encodeURIComponent(app)}/${site.version || ''}/a${ANSWERS}/${encodeURIComponent(q.toLowerCase())}`);
  const cache = caches.default;
  const hit = await cache.match(key);
  if (hit) {
    const text = await hit.text();
    return stream([sse('sources', sources), sse('t', { t: text }), sse('done', {})]);
  }

  if (!env.AI) return stream([sse('sources', sources), sse('t', { t: 'Answers are switched off right now. The FAQ below should help.' }), sse('done', {})]);

  const faqText = (site.faq || []).map((f) => `Q: ${f.q}\nA: ${f.a}`).join('\n\n');
  const compareText = (site.compare || []).map((c) => `${c.name}:\n${c.text}`).join('\n\n');
  const system = [
    `You answer questions in the Spotlight search bar on the ${app} website (${site.line || ''}). ${app} is a free Mac app by Testament Made, LLC.`,
    `Answer ONLY from the CONTEXT below. If the context doesn't cover it, say you don't know and suggest emailing ${site.email || 'derek@testamentmade.com'}.`,
    `For "how does it compare" questions, use COMPARISONS. With no app named, sum up what sets ${app} apart (from the context) and name a couple of the apps compared. For an app that isn't in COMPARISONS, say what ${app} does differently from the context, without guessing about the other app. Be fair to other apps.`,
    'Keep answers to one to three short sentences of plain text. No markdown, no lists, no headings. Never invent features, prices, versions or promises.',
    `Voice: ${site.voice || 'plain and friendly'}`,
    `If the question has nothing to do with ${app}, reply with one short, playful line (a light joke is welcome) that steers back to what ${app} does.`,
    'Never ask for, repeat or store keys, passwords or recovery codes.',
    `\nCONTEXT\n\nFAQ:\n${faqText}\n\nHOMEPAGE:\n${home}${compareText ? `\n\nCOMPARISONS:\n${compareText}` : ''}\n\nMORE:\n${llms}${site.more ? `\n\nHELP:\n${site.more}` : ''}`,
  ].join('\n');

  let ai;
  try {
    ai = await env.AI.run(MODEL, { messages: [{ role: 'system', content: system }, { role: 'user', content: q }], stream: true, max_tokens: 220, temperature: 0.3 });
  } catch {
    return stream([sse('sources', sources), sse('t', { t: `I couldn't answer just now. Try again in a moment, or email ${site.email}.` }), sse('done', {})]);
  }

  // Re-emit the model's stream as our own small events, and keep the full text for the cache.
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  let full = '';
  let buf = '';
  const out = new ReadableStream({
    async start(c) {
      c.enqueue(enc.encode(sse('sources', sources)));
      const reader = ai.getReader();
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        let i;
        while ((i = buf.indexOf('\n\n')) >= 0) {
          const line = buf.slice(0, i).trim();
          buf = buf.slice(i + 2);
          if (!line.startsWith('data:')) continue;
          const data = line.slice(5).trim();
          if (data === '[DONE]') continue;
          try {
            const j = JSON.parse(data);
            const t = typeof j.response === 'string' ? j.response : j.choices?.[0]?.delta?.content || '';
            if (t) { full += t; c.enqueue(enc.encode(sse('t', { t }))); }
          } catch { /* partial line */ }
        }
      }
      c.enqueue(enc.encode(sse('done', {})));
      c.close();
      if (full.trim()) {
        waitUntil(cache.put(key, new Response(full.trim(), { headers: { 'cache-control': 'public, max-age=604800' } })));
      }
    },
  });
  return new Response(out, { headers: { 'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'no-store' } });
}
