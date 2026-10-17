// The hero menu bar on the Testament Made app sites (Dinky, Binky, Slinky), made to work like the Mac's.
// Menus open with each app's real items; the Apple menu, Spotlight and Control Center work; and each app
// has its own small surprise. One file, copied to all three sites. Mouse only: the menu bar is decoration
// (aria-hidden), and everything here is also reachable on the page itself.
//
// Hooks in the page: a `.menubar[data-menubar="<App>"]` with items tagged data-mb="apple|app|file|edit|
// view|window|help|extra|battery|wifi|spotlight|cc|clock". The window that Minimize and Hide act on is
// tagged data-mb-window. App-specific actions are sent to the page as a `menubar:action` event.
(() => {
  const bar = document.querySelector('.menubar[data-menubar]');
  if (!bar) return;
  const app = bar.dataset.menubar;
  const desk = bar.closest('.desktop') || bar.parentElement;
  const still = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const emit = (action) => document.dispatchEvent(new CustomEvent('menubar:action', { detail: { app, action } }));

  // ---------- Menus: each app's real items. [label, shortcut, action] or '-' for a separator. ----------
  const apple = [
    ['About This Mac', '', 'aboutMac'], '-',
    ['System Settings…'], ['App Store'], '-',
    ['Force Quit…', '⌥⌘⎋'], '-',
    ['Sleep', '', 'sleep'], ['Restart…'], ['Shut Down…'], '-',
    ['Lock Screen', '⌃⌘Q', 'sleep'], ['Log Out…', '⇧⌘Q'],
  ];
  const edit = [['Undo', '⌘Z', null, true], ['Redo', '⇧⌘Z', null, true], '-', ['Cut', '⌘X'], ['Copy', '⌘C'], ['Paste', '⌘V'], ['Select All', '⌘A'], '-', ['Find…', '⌘F', 'spotlight']];
  const windowMenu = [['Minimize', '⌘M', 'minimize'], ['Zoom', '', 'fullscreen'], '-', ['Bring All to Front', '', 'restore']];
  const MENUS = {
    Slinky: {
      app: [['About Slinky', '', 'about'], ['Check for Updates…', '', 'upToDate'], '-', ['Lock Slinky', '⌃⌘L', 'lock'], '-', ['Settings…', '⌘,'], '-', ['Hide Slinky', '⌘H', 'hide'], ['Quit Slinky', '⌘Q']],
      file: [['Add Item…', '⌘N', 'add-item'], ['New Project…', '⇧⌘N', 'new-project'], ['Import…', '⇧⌘I', 'import'], '-', ['Quick Access', '⌥⌘K', 'quick-access'], '-', ['Close Window', '⌘W', 'minimize']],
      view: [['Show Sidebar', '⌃⌘S', 'toggle-sidebar'], '-', ['Enter Full Screen', '⌃⌘F', 'fullscreen']],
      help: [['Slinky Help', '', 'help']],
      extra: [['Open Slinky', '', 'restore'], ['Quick Access', '⌥⌘K', 'quick-access'], '-', ['Recently Copied', '', null, true], ['  STRIPE_SECRET_KEY'], ['  GITHUB_TOKEN'], '-', ['Lock Slinky', '⌃⌘L', 'lock']],
    },
    Dinky: {
      app: [['About Dinky', '', 'about'], ['Check for Updates…', '', 'upToDate'], '-', ['Settings…', '⌘,'], '-', ['Hide Dinky', '⌘H', 'hide'], ['Quit Dinky', '⌘Q']],
      file: [['Open…', '⌘O'], ['Compress Clipboard', '⇧⌘V'], '-', ['Close Window', '⌘W', 'minimize']],
      view: [['Show Sidebar', '⌃⌘S'], '-', ['Enter Full Screen', '⌃⌘F', 'fullscreen']],
      help: [['Dinky Help', '', 'help']],
      extra: [['Open Dinky', '', 'restore'], ['Settings…'], '-', ['Quit Dinky', '', 'wave']],
    },
    Binky: {
      app: [['About Binky', '', 'about'], ['Check for Updates…', '', 'upToDate'], '-', ['Settings…', '⌘,'], '-', ['Hide Binky', '⌘H', 'hide'], ['Quit Binky', '⌘Q']],
      file: [['Sort Now', '⌘R', 'sort'], ['Choose Folder…', '⌘O'], '-', ['Close Window', '⌘W', 'minimize']],
      view: [['Quick Sort', '⌘1'], ['Routines', '⌘2'], '-', ['Enter Full Screen', '⌃⌘F', 'fullscreen']],
      help: [['Binky Help', '', 'help']],
      extra: [['Sort Now', '', 'sort'], ['Open Binky', '', 'restore'], '-', ['Pause Routines'], '-', ['Quit Binky']],
    },
  };
  const menus = MENUS[app] || MENUS.Slinky;
  const menuFor = { apple, app: menus.app, file: menus.file, edit, view: menus.view, window: windowMenu, help: menus.help, extra: menus.extra };

  // ---------- Menu rendering ----------
  let open = null; // { key, el }
  const clearOn = () => bar.querySelectorAll('.fmb-on').forEach((el) => el.classList.remove('fmb-on'));
  const close = () => { if (open) { open.el.remove(); open = null; } clearOn(); };
  const place = (el, anchor) => {
    const d = desk.getBoundingClientRect();
    const a = anchor.getBoundingClientRect();
    el.style.top = `${a.bottom - d.top + 4}px`;
    const left = Math.min(a.left - d.left, d.width - el.offsetWidth - 8);
    el.style.left = `${Math.max(8, left)}px`;
  };
  const openMenu = (key, anchor) => {
    const items = menuFor[key];
    if (!items) return;
    close();
    const el = document.createElement('div');
    el.className = 'fmb-menu';
    for (const it of items) {
      if (it === '-') { el.append(Object.assign(document.createElement('hr'), { className: 'fmb-sep' })); continue; }
      const [label, keys = '', action = null, disabled = false] = it;
      const row = document.createElement('div');
      row.className = 'fmb-item' + (disabled ? ' is-off' : '');
      row.innerHTML = `<span></span><kbd></kbd>`;
      row.firstChild.textContent = label;
      row.lastChild.textContent = keys;
      if (!disabled) row.addEventListener('click', (e) => { e.stopPropagation(); close(); run(action); });
      el.append(row);
    }
    desk.append(el);
    place(el, anchor);
    anchor.classList.add('fmb-on');
    open = { key, el };
  };

  // ---------- Panels (About, Spotlight, Control Center) ----------
  let panel = null;
  const closePanel = () => { panel?.remove(); panel = null; clearOn(); };
  const showPanel = (html, cls, anchor) => {
    close(); closePanel();
    panel = document.createElement('div');
    panel.className = `fmb-panel ${cls}`;
    panel.innerHTML = html;
    panel.addEventListener('click', (e) => e.stopPropagation());
    desk.append(panel);
    if (anchor) { place(panel, anchor); anchor.classList.add('fmb-on'); }
    return panel;
  };
  const icon = () => $('.dock__app.is-current img')?.getAttribute('src') || '';
  const version = () => (($('.hero') || document.body).textContent.match(/\bv(\d+\.\d+(?:\.\d+)?)\b/) || [])[1] || '';
  const about = () => {
    const p = showPanel(`
      <img src="${icon()}" alt="" width="72" height="72" />
      <b>${app}</b><span>Version ${version()}</span>
      <small>© 2026 Testament Made, LLC</small>
      <button type="button" class="fmb-btn">OK</button>`, 'fmb-about');
    p.querySelector('button').addEventListener('click', closePanel);
  };
  const aboutMac = () => {
    const p = showPanel(`
      <svg viewBox="0 0 120 76" width="120" height="76" aria-hidden="true"><rect x="16" y="4" width="88" height="58" rx="5" fill="none" stroke="currentColor" stroke-width="3"/><rect x="22" y="10" width="76" height="46" rx="2" fill="var(--fmb-accent)" opacity=".85"/><path d="M4 64h112l-6 8H10z" fill="currentColor"/></svg>
      <b>MacBook Pro</b><span>14-inch, 2026</span>
      <dl><dt>Chip</dt><dd>Apple M5 Pro</dd><dt>Memory</dt><dd>24 GB</dd><dt>macOS</dt><dd>Tahoe 26</dd><dt>Apps</dt><dd>Dinky, Binky, Slinky</dd></dl>
      <button type="button" class="fmb-btn">More Info…</button>`, 'fmb-about');
    p.querySelector('button').addEventListener('click', closePanel);
  };
  const spotlight = (anchor) => {
    // Headlines (with their small label above, like "Recovery") and FAQ questions on this page.
    const clean = (t) => t.replace(/\s+/g, ' ').trim();
    const words = (el) => clean(el.innerText || el.textContent);
    const sections = [
      ...$$('main h2').filter((h) => h.textContent.trim() && !h.closest('.desktop')).map((h) => {
        const host = h.closest('section, .g-row, .ss-row, [class*="row"]') || h;
        const label = h.previousElementSibling?.matches('.eyebrow, [class*="eyebrow"], [class*="label"]') ? clean(h.previousElementSibling.textContent) : '';
        return { el: host, text: words(h), find: `${label} ${words(h)}` };
      }),
      ...$$('main summary').filter((q) => !q.closest('.desktop')).map((q) => ({ el: q.closest('details') || q, text: clean(q.textContent), find: clean(q.textContent) })),
    ];
    // Tahoe's Spotlight: a large glass, large placeholder, and the four modes (Applications, Files, Actions, Clipboard) on the right.
    const modes = [
      '<rect x="2.5" y="2.5" width="5" height="5" rx="1.4"/><rect x="10.5" y="2.5" width="5" height="5" rx="1.4"/><rect x="2.5" y="10.5" width="5" height="5" rx="1.4"/><rect x="10.5" y="10.5" width="5" height="5" rx="1.4"/>',
      '<path d="M4 2.5h6.2L14 6.3v9.2H4z"/><path d="M10 2.6V6.5h3.9"/>',
      '<rect x="2.5" y="2.5" width="13" height="13" rx="3.5"/><path d="M9.5 5 6.8 9.4h3.4L8.6 13"/>',
      '<rect x="3.5" y="3.5" width="11" height="12" rx="2"/><path d="M6.5 2.5h5v2.4h-5z"/>',
    ].map((d) => `<span class="fmb-mode"><svg viewBox="0 0 18 18" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" aria-hidden="true">${d}</svg></span>`).join('');
    const p = showPanel(`<label class="fmb-search"><svg class="fmb-glass" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><circle cx="10.2" cy="10.2" r="7" fill="none" stroke="currentColor" stroke-width="2.1"/><path d="m15.4 15.4 5.6 5.6" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"/></svg><input type="text" placeholder="Spotlight Search" aria-label="Search this page" autocomplete="off" spellcheck="false" /><span class="fmb-modes" aria-hidden="true">${modes}</span></label><div class="fmb-results"></div>`, 'fmb-spot');
    p.style.left = '50%'; p.style.top = '44px'; p.style.translate = '-50% 0';
    const input = p.querySelector('input');
    const list = p.querySelector('.fmb-results');
    let sel = 0; let shown = [];
    const render = () => {
      const q = input.value.trim().toLowerCase();
      shown = q ? sections.filter((s) => s.find.toLowerCase().includes(q)).slice(0, 6) : [];
      sel = Math.min(sel, Math.max(0, shown.length - 1));
      list.innerHTML = '';
      shown.forEach((s, i) => {
        const r = document.createElement('div');
        r.className = 'fmb-result' + (i === sel ? ' is-on' : '');
        r.innerHTML = `<img src="${icon()}" alt="" width="20" height="20" /><span></span>`;
        r.lastChild.textContent = s.text;
        r.addEventListener('click', () => go(s.el));
        list.append(r);
      });
      p.classList.toggle('has-results', shown.length > 0);
    };
    const go = (el) => { closePanel(); if (el.tagName === 'DETAILS') el.open = true; el.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'center' }); };
    input.addEventListener('input', () => { sel = 0; render(); });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown') { sel = Math.min(sel + 1, shown.length - 1); render(); e.preventDefault(); }
      if (e.key === 'ArrowUp') { sel = Math.max(sel - 1, 0); render(); e.preventDefault(); }
      if (e.key === 'Enter' && shown[sel]) go(shown[sel].el);
    });
    if (anchor) anchor.classList.add('fmb-on');
    input.focus({ preventScroll: true });
  };

  // Dark Mode for the whole page: flip every prefers-color-scheme rule, the way the system setting would.
  const sysDark = () => matchMedia('(prefers-color-scheme: dark)').matches;
  let forced = null; // null = follow the system, true = dark, false = light
  const originals = new Map();
  const flip = (dark) => {
    forced = dark === sysDark() ? null : dark;
    const walk = (rules) => {
      for (const r of rules) {
        if (r.media && (originals.has(r) || /prefers-color-scheme/.test(r.media.mediaText))) {
          if (!originals.has(r)) originals.set(r, r.media.mediaText);
          let t = originals.get(r);
          if (forced !== null) {
            t = t.replace(/\(\s*prefers-color-scheme:\s*dark\s*\)/g, forced ? '(min-width: 0px)' : '(max-width: 0px)')
                 .replace(/\(\s*prefers-color-scheme:\s*light\s*\)/g, forced ? '(max-width: 0px)' : '(min-width: 0px)');
          }
          r.media.mediaText = t;
        }
        if (r.cssRules) walk(r.cssRules);
      }
    };
    for (const sheet of document.styleSheets) { try { walk(sheet.cssRules); } catch { /* another site's sheet */ } }
    const meta = $('meta[name="color-scheme"]');
    if (meta) meta.content = forced === null ? 'light dark' : forced ? 'dark' : 'light';
    $$('picture source[media*="prefers-color-scheme"]').forEach((s) => {
      if (!s.dataset.media) s.dataset.media = s.media;
      s.media = forced === null ? s.dataset.media : (forced ? 'all' : 'not all');
    });
  };
  const isDark = () => (forced === null ? sysDark() : forced);
  let wifiOn = true; let bright = 100; let routinesOn = true;
  const SUN = '<svg viewBox="0 0 20 20" width="14" height="14" aria-hidden="true"><circle cx="10" cy="10" r="3.6" fill="currentColor"/><g stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M10 1.8v2M10 16.2v2M1.8 10h2M16.2 10h2M4.2 4.2l1.4 1.4M14.4 14.4l1.4 1.4M4.2 15.8l1.4-1.4M14.4 5.6l1.4-1.4"/></g></svg>';
  // Each app's own Control Center tile: [title, icon, subtitle(), press()].
  const appTile = {
    Slinky: () => {
      const locked = () => !!$('[data-mb-window].is-locked');
      return ['Lock Slinky', '<svg viewBox="0 0 20 20" width="15" height="15" aria-hidden="true"><path d="M10 2a4.2 4.2 0 0 1 4.2 4.2V8h.6A1.7 1.7 0 0 1 16.5 9.7v6.6a1.7 1.7 0 0 1-1.7 1.7H5.2a1.7 1.7 0 0 1-1.7-1.7V9.7A1.7 1.7 0 0 1 5.2 8h.6V6.2A4.2 4.2 0 0 1 10 2Zm0 1.8a2.4 2.4 0 0 0-2.4 2.4V8h4.8V6.2A2.4 2.4 0 0 0 10 3.8Z" fill="currentColor"/></svg>',
        () => (locked() ? 'Locked' : 'Unlocked'), locked, () => { if (!locked()) emit('lock'); }];
    },
    Dinky: () => ['Clipboard Compress', '<svg viewBox="0 0 20 20" width="15" height="15" aria-hidden="true"><rect x="4" y="3.5" width="12" height="14" rx="2.4" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="7" y="2" width="6" height="3.4" rx="1.2" fill="currentColor"/><path d="M10 8v6m-2.6-2.6L10 14l2.6-2.6" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
      () => '⇧⌘V', () => false, () => { closePanel(); toast('Compressed the clipboard image: 1.4 MB → 212 KB.'); }],
    Binky: () => ['Routines', '<svg viewBox="0 0 20 20" width="15" height="15" aria-hidden="true"><path d="M3 6.5a1.5 1.5 0 0 1 1.5-1.5h3.6l1.5 1.6h5.9A1.5 1.5 0 0 1 17 8.1v6.4a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 3 14.5z" fill="currentColor"/></svg>',
      () => (routinesOn ? 'Watching 2 folders' : 'Paused'), () => routinesOn, () => { routinesOn = !routinesOn; }],
  };
  const control = (anchor) => {
    const [tTitle, tIcon, tSub, tOn, tPress] = (appTile[app] || appTile.Slinky)();
    const family = $$('.dock__app').map((a) => ({ href: a.getAttribute('href'), img: a.querySelector('img')?.getAttribute('src'), name: a.querySelector('.dock__name')?.textContent || '', on: a.classList.contains('is-current') }));
    const p = showPanel(`
      <div class="fmb-cc">
        <button type="button" class="fmb-tile" data-t="wifi"><i>${bar.querySelector('[data-mb="wifi"] svg')?.outerHTML || ''}</i><span><b>Wi-Fi</b><small></small></span></button>
        <button type="button" class="fmb-tile" data-t="dark"><i><svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true"><circle cx="10" cy="10" r="7" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M10 3a7 7 0 0 1 0 14z" fill="currentColor"/></svg></i><span><b>Dark Mode</b><small></small></span></button>
        <button type="button" class="fmb-tile fmb-tile--wide" data-t="app"><i>${tIcon}</i><span><b>${tTitle}</b><small></small></span></button>
        <label class="fmb-slider"><b>Display</b><span class="fmb-track">${SUN}<input type="range" min="35" max="100" value="${bright}" aria-label="Display brightness" /></span></label>
        <div class="fmb-family">
          <a class="fmb-family__head" href="https://testamentmade.com" target="_blank" rel="noopener">Testament Made</a>
          <div class="fmb-family__apps">${family.map((f) => `<a href="${f.href}"${f.on ? ' class="is-on" aria-current="page"' : ''}><img src="${f.img}" alt="" width="36" height="36" /><span>${f.name}</span></a>`).join('')}</div>
        </div>
      </div>`, 'fmb-ccp', anchor);
    p.style.left = 'auto'; p.style.right = '8px';
    const sync = () => {
      const w = p.querySelector('[data-t="wifi"]'); w.classList.toggle('is-on', wifiOn); w.querySelector('small').textContent = wifiOn ? 'Home' : 'Off';
      const d = p.querySelector('[data-t="dark"]'); d.classList.toggle('is-on', isDark()); d.querySelector('small').textContent = isDark() ? 'On' : 'Off';
      const t = p.querySelector('[data-t="app"]'); t.classList.toggle('is-on', !!tOn()); t.querySelector('small').textContent = tSub();
    };
    p.querySelector('[data-t="wifi"]').addEventListener('click', () => { wifiOn = !wifiOn; bar.querySelector('[data-mb="wifi"]')?.classList.toggle('fmb-dim', !wifiOn); sync(); });
    p.querySelector('[data-t="dark"]').addEventListener('click', () => { flip(!isDark()); sync(); });
    p.querySelector('[data-t="app"]').addEventListener('click', () => { tPress(); if (panel === p) setTimeout(sync, 60); });
    const track = p.querySelector('.fmb-track');
    p.querySelector('input').addEventListener('input', (e) => {
      bright = +e.target.value;
      track.style.setProperty('--v', String((bright - 35) / 65));
      desk.style.filter = bright < 100 ? `brightness(${bright / 100})` : '';
    });
    track.style.setProperty('--v', String((bright - 35) / 65));
    sync();
  };

  // ---------- Window: minimize into the Dock, hide, full screen, sleep ----------
  const win = () => $('[data-mb-window]', desk);
  let away = false;
  const minimize = (fade) => {
    const w = win(); if (!w || away) return;
    const dockIcon = $('.dock__app.is-current');
    const a = w.getBoundingClientRect(); const b = dockIcon ? dockIcon.getBoundingClientRect() : { left: a.left + a.width / 2, top: innerHeight, width: 0, height: 0 };
    const dx = b.left + b.width / 2 - (a.left + a.width / 2); const dy = b.top + b.height / 2 - (a.top + a.height / 2);
    away = true;
    if (still() || fade) { w.style.visibility = 'hidden'; return; }
    w.animate([{ transform: 'none', opacity: 1 }, { transform: `translate(${dx * 0.5}px, ${dy * 0.35}px) scale(0.5, 0.3)`, opacity: 0.8, offset: 0.55 }, { transform: `translate(${dx}px, ${dy}px) scale(0.04)`, opacity: 0 }],
      { duration: 560, easing: 'cubic-bezier(.5,0,.75,0)' }).finished.then(() => { w.style.visibility = 'hidden'; });
  };
  const restore = () => {
    const w = win(); if (!w || !away) return;
    away = false;
    w.style.visibility = '';
    if (!still()) w.animate([{ transform: 'translateY(30px) scale(0.92)', opacity: 0 }, { transform: 'none', opacity: 1 }], { duration: 420, easing: 'cubic-bezier(.22,1,.36,1)' });
    const d = $('.dock__app.is-current');
    if (d && !still()) { d.classList.remove('is-launching'); void d.offsetWidth; d.classList.add('is-launching'); setTimeout(() => d.classList.remove('is-launching'), 900); }
  };
  // While the window is in the Dock, the app's own Dock icon brings it back.
  $('.dock__app.is-current')?.addEventListener('click', (e) => { if (away) { e.preventDefault(); restore(); desk.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'center' }); } });
  const sleepNow = () => {
    close(); closePanel();
    const veil = document.createElement('div');
    veil.className = 'fmb-sleep';
    desk.append(veil);
    requestAnimationFrame(() => veil.classList.add('is-on'));
    emit('lock');
    const wake = () => { veil.classList.remove('is-on'); setTimeout(() => veil.remove(), 500); };
    veil.addEventListener('click', wake);
  };
  const toast = (text) => {
    const t = document.createElement('div');
    t.className = 'fmb-toast';
    t.innerHTML = `<img src="${icon()}" alt="" width="34" height="34" /><span><b>${app}<time>now</time></b><small></small></span>`;
    t.querySelector('small').textContent = text;
    desk.append(t);
    requestAnimationFrame(() => t.classList.add('is-on'));
    setTimeout(() => { t.classList.remove('is-on'); setTimeout(() => t.remove(), 500); }, 3600);
  };

  // ---------- Actions ----------
  function run(action) {
    switch (action) {
      case null: case undefined: return;
      case 'about': return about();
      case 'aboutMac': return aboutMac();
      case 'upToDate': return toast(`${app} ${version()} is the newest version.`);
      case 'sleep': return sleepNow();
      case 'spotlight': return spotlight(bar.querySelector('[data-mb="spotlight"]'));
      case 'minimize': return minimize(false);
      case 'hide': return minimize(true);
      case 'restore': return restore();
      case 'fullscreen': return document.fullscreenElement ? document.exitFullscreen() : desk.requestFullscreen?.().catch(() => {});
      case 'help': return ($('#faq') || $('footer'))?.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'start' });
      default: return emit(action);
    }
  }

  // ---------- Wiring ----------
  bar.addEventListener('click', (e) => {
    const item = e.target.closest('[data-mb]');
    if (!item) return;
    e.stopPropagation();
    const key = item.dataset.mb;
    if (open?.key === key || (panel && item.classList.contains('fmb-on'))) { close(); closePanel(); return; }
    closePanel();
    if (key === 'spotlight') return spotlight(item);
    if (key === 'cc') return control(item);
    if (key === 'clock' || key === 'battery' || key === 'wifi') return control(bar.querySelector('[data-mb="cc"]') || item);
    openMenu(key, item);
  });
  // Like the Mac: once a menu is open, moving across the bar opens the others.
  bar.addEventListener('pointerover', (e) => {
    const item = e.target.closest('[data-mb]');
    if (open && item && menuFor[item.dataset.mb] && open.key !== item.dataset.mb) openMenu(item.dataset.mb, item);
  });
  document.addEventListener('click', () => { close(); closePanel(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { close(); closePanel(); } });
  addEventListener('resize', close);
  bar.classList.add('fmb-live');

  // ---------- Each app's own surprise ----------
  if (app === 'Dinky') {
    // Drop any picture on the page onto Dinky's menu bar icon and it gets dinky.
    const target = bar.querySelector('[data-mb="extra"]');
    let dragged = null;
    document.addEventListener('dragstart', (e) => { if (e.target instanceof HTMLImageElement) dragged = e.target; });
    document.addEventListener('dragend', () => { dragged = null; target?.classList.remove('fmb-drop'); });
    target?.addEventListener('dragover', (e) => { if (dragged) { e.preventDefault(); target.classList.add('fmb-drop'); } });
    target?.addEventListener('dragleave', () => target.classList.remove('fmb-drop'));
    target?.addEventListener('drop', (e) => {
      e.preventDefault(); target.classList.remove('fmb-drop');
      const img = dragged; if (!img) return;
      const before = Math.max(48, Math.round((img.naturalWidth * img.naturalHeight * 3) / 1024 / 6));
      const saved = 0.62 + ((img.naturalWidth % 17) / 100);
      const after = Math.max(6, Math.round(before * (1 - saved)));
      if (!still()) img.animate([{ transform: 'scale(1)' }, { transform: 'scale(0.82)' }, { transform: 'scale(0.9)' }], { duration: 700, easing: 'cubic-bezier(.22,1,.36,1)', fill: 'forwards' });
      const name = (img.getAttribute('src') || 'image').split('/').pop().split('?')[0];
      toast(`${name}: ${before} KB → ${after} KB. ${Math.round(saved * 100)}% smaller.`);
    });
    document.addEventListener('menubar:action', (e) => {
      if (e.detail.action !== 'wave' || !target) return;
      if (!still()) target.animate([{ rotate: '0deg' }, { rotate: '-18deg' }, { rotate: '14deg' }, { rotate: '-12deg' }, { rotate: '8deg' }, { rotate: '0deg' }], { duration: 1100, easing: 'ease-in-out' });
      toast('Bye for now. Drop a picture on this hand to shrink it.');
    });
  }
  if (app === 'Binky') {
    // A few loose files on the hero desktop; Sort Now tucks them into folders.
    const files = [['IMG_2041.HEIC', 'img', 0], ['Invoice-0423.pdf', 'doc', 1], ['design-assets.zip', 'zip', 2], ['Screenshot 2026-10-17.png', 'img', 0], ['contract-final.pdf', 'doc', 1]];
    const folders = ['Images', 'Documents', 'Archives'];
    const layer = document.createElement('div');
    layer.className = 'fmb-files';
    layer.setAttribute('aria-hidden', 'true');
    const fileIcon = (k) => k === 'img' ? '<svg viewBox="0 0 32 40" width="30" height="38"><path d="M3 1h18l8 8v28a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V3a2 2 0 0 1 2-2z" fill="#fff" stroke="#c8c8cc"/><rect x="5" y="14" width="22" height="16" rx="2" fill="#7cc4f2"/><path d="M5 30l7-8 5 5 4-3 6 6z" fill="#3f9b5f"/></svg>'
      : k === 'doc' ? '<svg viewBox="0 0 32 40" width="30" height="38"><path d="M3 1h18l8 8v28a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V3a2 2 0 0 1 2-2z" fill="#fff" stroke="#c8c8cc"/><rect x="6" y="26" width="20" height="8" rx="1.5" fill="#e5484d"/><path d="M7 14h18M7 18h18M7 22h12" stroke="#c8c8cc" stroke-width="1.6"/></svg>'
      : '<svg viewBox="0 0 32 40" width="30" height="38"><path d="M3 1h18l8 8v28a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V3a2 2 0 0 1 2-2z" fill="#fff" stroke="#c8c8cc"/><path d="M15 3v24" stroke="#8a8a8e" stroke-width="3" stroke-dasharray="2 2"/><rect x="12" y="26" width="6" height="7" rx="1.5" fill="#8a8a8e"/></svg>';
    const folderIcon = '<svg viewBox="0 0 44 36" width="44" height="36"><path d="M2 6a3 3 0 0 1 3-3h11l4 4h19a3 3 0 0 1 3 3v21a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z" fill="#5ab2ee"/><path d="M2 12h40v19a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3z" fill="#7dc6f6"/></svg>';
    layer.innerHTML = files.map(([n, k], i) => `<div class="fmb-file" style="--i:${i}">${fileIcon(k)}<span>${n}</span></div>`).join('')
      + folders.map((n, i) => `<div class="fmb-folder" style="--i:${i}">${folderIcon}<span>${n}</span></div>`).join('');
    desk.append(layer);
    let sorted = false;
    const sort = async () => {
      if (sorted) { toast('Nothing new to sort. The desktop is tidy.'); return; }
      sorted = true;
      layer.classList.add('is-sorting');
      const fileEls = $$('.fmb-file', layer); const folderEls = $$('.fmb-folder', layer);
      for (let i = 0; i < fileEls.length; i++) {
        const f = fileEls[i]; const to = folderEls[files[i][2]];
        const a = f.getBoundingClientRect(); const b = to.getBoundingClientRect();
        const dx = b.left + b.width / 2 - (a.left + a.width / 2); const dy = b.top + b.height / 2 - (a.top + a.height / 2);
        if (still()) { f.style.opacity = '0'; continue; }
        await f.animate([{ transform: 'none', opacity: 1 }, { transform: `translate(${dx * 0.5}px, ${dy * 0.5 - 40}px) scale(0.8)`, opacity: 1 }, { transform: `translate(${dx}px, ${dy}px) scale(0.3)`, opacity: 0 }],
          { duration: 620, easing: 'cubic-bezier(.4,0,.2,1)', fill: 'forwards' }).finished;
        to.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.12)' }, { transform: 'scale(1)' }], { duration: 260 });
      }
      toast('Sorted 5 files: 2 into Images, 2 into Documents, 1 into Archives.');
    };
    document.addEventListener('menubar:action', (e) => { if (e.detail.action === 'sort') sort(); });
  }
})();
