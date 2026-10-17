// Cloudflare Pages Function for "/": serve homepage.md to clients that prefer Markdown
// (Accept: text/markdown). Same behavior as netlify/edge-functions/markdown-home.js.
function prefersMarkdown(accept) {
  if (!accept) return false;
  const types = accept.split(',').map((part) => {
    const [type, ...params] = part.trim().split(';');
    const q = params.map((p) => p.trim()).find((p) => p.startsWith('q='));
    return { type: type.trim().toLowerCase(), q: q ? Number(q.slice(2)) : 1 };
  });
  const md = types.find((t) => t.type === 'text/markdown');
  const html = types.find((t) => t.type === 'text/html');
  return !!md && md.q > 0 && (!html || md.q >= html.q);
}

export async function onRequestGet({ request, env, next }) {
  if (!prefersMarkdown(request.headers.get('accept'))) return next();
  const res = await env.ASSETS.fetch(new URL('/homepage.md', request.url).toString());
  if (!res.ok) return next();
  const text = await res.text();
  return new Response(text, {
    headers: {
      'content-type': 'text/markdown; charset=utf-8',
      'x-markdown-tokens': String(Math.max(1, Math.round(text.length / 4))),
      'cache-control': 'public, max-age=300',
      link: '</.well-known/api-catalog>; rel="api-catalog", </llms.txt>; rel="describedby", </openapi.yaml>; rel="service-desc", </homepage.md>; rel="alternate"; type="text/markdown"',
      vary: 'Accept',
    },
  });
}
