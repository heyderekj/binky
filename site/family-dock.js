// The family Dock (Dinky, Binky, Slinky), behaving like the macOS Dock: icons grow with the pointer's
// distance and push apart, the name shows above, and clicking another app bounces it as the next site opens.
(() => {
  const dock = document.querySelector('.dock');
  if (!dock) return;
  const apps = Array.from(dock.querySelectorAll('.dock__app'));
  // On this Mac the Dock opens the other sites' local servers, so switching can be tried before they're live.
  if (location.hostname === 'localhost') {
    const ports = { dinky: 4343, binky: 4342, slinky: 4329 };
    apps.forEach((a) => {
      const m = a.hostname.match(/^(dinky|binky|slinky)files\.com$/);
      if (m) a.href = 'http://localhost:' + ports[m[1]] + '/';
    });
  }
  const still = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  const set = (a, m) => a.style.setProperty('--mag', m.toFixed(3));
  let centers = [];
  if (matchMedia('(hover: hover)').matches) {
    dock.addEventListener('pointerenter', () => {
      apps.forEach((a) => set(a, 1));
      centers = apps.map((a) => { const r = a.getBoundingClientRect(); return r.left + r.width / 2; });
    });
    dock.addEventListener('pointermove', (e) => {
      if (still() || !centers.length) return;
      dock.classList.add('is-tracking');
      apps.forEach((a, i) => {
        const t = Math.max(0, 1 - Math.abs(e.clientX - centers[i]) / 150);
        set(a, 1 + 0.62 * Math.pow(Math.sin((t * Math.PI) / 2), 1.8));
      });
    });
    dock.addEventListener('pointerleave', () => { dock.classList.remove('is-tracking'); apps.forEach((a) => set(a, 1)); });
  }
  // Switching apps should feel like turning a page: connect to the other sites early, fetch them as the
  // pointer reaches the Dock, and go the moment one is clicked. The bounce plays while the next page loads.
  const others = apps.filter((a) => !a.classList.contains('is-current'));
  others.forEach((a) => {
    const origin = new URL(a.href).origin;
    if (document.querySelector('link[rel="preconnect"][href^="' + origin + '"]')) return;
    const l = document.createElement('link');
    l.rel = 'preconnect';
    l.href = origin;
    document.head.append(l);
  });
  if (HTMLScriptElement.supports && HTMLScriptElement.supports('speculationrules')) {
    // Chrome: prefetch on hover or press of a Dock icon.
    const s = document.createElement('script');
    s.type = 'speculationrules';
    s.textContent = JSON.stringify({ prefetch: [{ where: { selector_matches: '.dock__app:not(.is-current)' }, eagerness: 'moderate' }] });
    document.head.append(s);
  } else {
    // Firefox honours prefetch links. (Safari has neither yet, so it gets the early connection only.)
    let warmed = false;
    const warm = () => {
      if (warmed) return;
      warmed = true;
      others.forEach((a) => {
        const l = document.createElement('link');
        l.rel = 'prefetch';
        l.href = a.href;
        document.head.append(l);
      });
    };
    dock.addEventListener('pointerenter', warm);
    dock.addEventListener('focusin', warm);
    dock.addEventListener('touchstart', warm, { passive: true });
  }
  others.forEach((a) => a.addEventListener('click', (e) => {
    if (still() || e.metaKey || e.ctrlKey || e.shiftKey) return;
    a.classList.add('is-launching');
  }));
  // Coming back with the Back button restores this page as it was left; settle the bounce.
  addEventListener('pageshow', (e) => { if (e.persisted) others.forEach((a) => a.classList.remove('is-launching')); });
})();
