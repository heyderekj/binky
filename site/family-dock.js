// The family Dock (Dinky, Binky, Slinky), behaving like the macOS Dock: icons grow with the pointer's
// distance and push apart, the name shows above, and clicking another app bounces it before going.
(() => {
  const dock = document.querySelector('.dock');
  if (!dock) return;
  const apps = Array.from(dock.querySelectorAll('.dock__app'));
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
  apps.forEach((a) => a.addEventListener('click', (e) => {
    if (a.classList.contains('is-current') || still() || e.metaKey || e.ctrlKey || e.shiftKey) return;
    e.preventDefault();
    a.classList.add('is-launching');
    setTimeout(() => { location.href = a.href; }, 700);
  }));
})();
