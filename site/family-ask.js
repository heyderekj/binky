// Ask a question about this app: the FAQ field, and the "Ask" row in the hero's Spotlight (family-menubar.js).
// One file, copied to all three Testament Made app sites. Talks to /api/ask (functions/api/ask.js), which
// answers from the site's own words and streams text back.
(() => {
  // Same check as the server: anything that looks like a key never leaves the page.
  const SECRET = /(sk[-_](?:live|test|proj|ant)[-_A-Za-z0-9]{12,}|\bgh[pousr]_[A-Za-z0-9]{20,}|\bxox[abprs]-[A-Za-z0-9-]{10,}|\bAKIA[0-9A-Z]{16}\b|\bAIza[0-9A-Za-z_-]{30,}|\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?=[A-Za-z0-9_\-+/=]*\d)(?=[A-Za-z0-9_\-+/=]*[A-Za-z])[A-Za-z0-9_\-+/=]{32,}\b)/;
  const app = document.querySelector('.menubar[data-menubar]')?.dataset.menubar || document.title.split(/[ ·]/)[0];

  /** ask(question, { onSources, onText, onDone }) → streams an answer. Returns an abort function. */
  function ask(q, { onSources = () => {}, onText = () => {}, onDone = () => {} } = {}) {
    const ctrl = new AbortController();
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; ctrl.abort(); }, 20000);
    q = String(q).replace(/\s+/g, ' ').trim().slice(0, 280);
    if (SECRET.test(q)) {
      onSources([]);
      onText(`That looks like a key or token, so I didn't send it anywhere. Please don't paste secrets into websites, this one included.${app === 'Slinky' ? ' Keep it in Slinky.' : ''}`);
      onDone();
      return () => {};
    }
    (async () => {
      try {
        const res = await fetch('/api/ask', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ q }), signal: ctrl.signal });
        if (!res.ok || !res.body) throw new Error(String(res.status));
        const reader = res.body.getReader();
        const dec = new TextDecoder();
        let buf = '';
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buf += dec.decode(value, { stream: true });
          let i;
          while ((i = buf.indexOf('\n\n')) >= 0) {
            const block = buf.slice(0, i); buf = buf.slice(i + 2);
            const ev = /^event: (.+)$/m.exec(block)?.[1];
            const data = /^data: (.*)$/m.exec(block)?.[1];
            if (!ev || data == null) continue;
            const j = JSON.parse(data);
            if (ev === 'sources') onSources(j);
            else if (ev === 't') onText(j.t);
          }
        }
        clearTimeout(timer);
        onDone();
      } catch (e) {
        clearTimeout(timer);
        if (e.name === 'AbortError' && !timedOut) return;
        onSources([]);
        onText(location.hostname === 'localhost' || location.protocol === 'file:'
          ? 'Answers work on the live site. The FAQ below has the common ones.'
          : "I couldn't answer just now. The FAQ below has the common ones.");
        onDone();
      }
    })();
    return () => ctrl.abort();
  }
  window.familyAsk = ask;

  // The FAQ shows a few core questions; the rest wait behind "Show all questions" (data-faq-collapsed on the
  // list, .faq-more on the extra items, [data-faq-all] on the button). Anything that jumps to a hidden one opens the list.
  const expand = (list) => {
    if (!list) return;
    list.removeAttribute('data-faq-collapsed');
    const btn = list.parentElement.querySelector('[data-faq-all]');
    if (btn) btn.hidden = true;
  };
  window.familyReveal = (el) => { if (el?.closest?.('.faq-more')) expand(el.closest('[data-faq-collapsed]')); };
  for (const btn of document.querySelectorAll('[data-faq-all]')) {
    btn.addEventListener('click', () => {
      const list = btn.parentElement.querySelector('[data-faq-collapsed]');
      const first = list?.querySelector('.faq-more');
      expand(list);
      first?.querySelector('summary, .faq-q, h3')?.setAttribute('tabindex', '-1');
      first?.querySelector('summary, .faq-q, h3')?.focus({ preventScroll: true });
    });
  }

  // Plain links to a hidden question (#faq-…), and arriving with one in the address, open the list too.
  const revealHash = (hash) => { try { window.familyReveal(document.querySelector(hash)); } catch { /* not an id */ } };
  document.addEventListener('click', (e) => {
    const a = e.target.closest?.('a[href^="#"]');
    if (a && a.getAttribute('href').length > 1) revealHash(a.getAttribute('href'));
  });
  if (location.hash.length > 1) revealHash(location.hash);

  /** Opens and scrolls to an FAQ entry by its id. */
  window.familyAskOpen = (id) => {
    const d = document.getElementById(id);
    if (!d) return;
    window.familyReveal(d);
    if (d.tagName === 'DETAILS') d.open = true;
    d.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'center' });
  };
  const sourceLinks = (el, sources) => {
    el.innerHTML = '';
    if (!sources.length) { el.hidden = true; return; }
    el.hidden = false;
    el.append('From the FAQ: ');
    sources.forEach((s, i) => {
      const a = document.createElement('a');
      a.href = `#${s.id}`; a.textContent = s.q;
      a.addEventListener('click', (e) => { e.preventDefault(); window.familyAskOpen(s.id); });
      if (i) el.append(' · ');
      el.append(a);
    });
  };
  window.familyAskSources = sourceLinks;

  // The FAQ field: <form data-ask> with an input[name=q], an [data-ask-answer] with [data-ask-text] and [data-ask-src].
  for (const form of document.querySelectorAll('[data-ask]')) {
    const input = form.querySelector('input[name="q"]');
    const box = form.parentElement.querySelector('[data-ask-answer]');
    const text = box?.querySelector('[data-ask-text]');
    const src = box?.querySelector('[data-ask-src]');
    let stop = () => {};
    // Clearing the field puts the answer away.
    input.addEventListener('input', () => {
      if (input.value.trim() || !box) return;
      stop(); box.hidden = true; form.classList.remove('is-thinking'); box.classList.remove('is-thinking');
    });
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const q = input.value.trim();
      if (q.length < 2 || !box) return;
      stop();
      box.hidden = false; text.textContent = ''; src.hidden = true;
      form.classList.add('is-thinking'); box.classList.add('is-thinking');
      stop = ask(q, {
        onSources: (s) => sourceLinks(src, s),
        onText: (t) => { text.textContent += t; },
        onDone: () => { form.classList.remove('is-thinking'); box.classList.remove('is-thinking'); },
      });
    });
  }
})();
