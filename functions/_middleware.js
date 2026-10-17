// Every response: on a *.pages.dev address (the preview copies), ask search engines not to index it.
// The real domains are untouched.
export const onRequest = async ({ request, next }) => {
  const res = await next();
  if (!new URL(request.url).hostname.endsWith('.pages.dev')) return res;
  const out = new Response(res.body, res);
  out.headers.set('X-Robots-Tag', 'noindex, nofollow');
  return out;
};
