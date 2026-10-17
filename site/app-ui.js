/*
 * The recreated Binky windows on the homepage (app-ui.css): the organizer counts through a Quick Sort
 * when it scrolls into view, the Routines pane picks and switches routines, and the Currently sorting
 * sheet counts up and pauses. Every file name is made up. Everything honors Reduced Motion.
 */
(function () {
  'use strict';
  var mq = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
  function still() { return !!(mq && mq.matches); }
  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function onVisible(el, fn, threshold) {
    if (!('IntersectionObserver' in window)) { fn(); return; }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { io.disconnect(); fn(); } });
    }, { threshold: threshold || 0.4 });
    io.observe(el);
  }

  // Made-up Downloads, in the order the demo "sorts" them.
  var FILES = [
    'Invoice-0423.pdf', 'IMG_2041.HEIC', 'design-assets.zip', 'Screen Recording 2026-10-16 at 4.12.08 PM.mov',
    'Synth-Installer-2.4.dmg', 'Q3-report-EXAMPLE.pdf', 'IMG_2042.HEIC', 'boarding-pass.pdf', 'logo-v2.png',
    'meeting-notes.docx', 'Screenshot 2026-10-16 at 9.02.41 AM.png', 'podcast-ep12.m4a', 'receipt-0917.pdf',
    'fonts.zip', 'demo-take-3.mp4', 'Resume-2026.pdf', 'wallpaper-4k.jpg', 'Handbook-EXAMPLE.pdf',
    'IMG_2043.HEIC', 'archive-2025.tar.gz', 'sketch-03.png', 'lease-renewal.pdf', 'clip-0042.mov'
  ];
  function bucketFor(name) {
    var ext = name.split('.').pop().toLowerCase();
    if (/^(heic|jpe?g|png|gif|webp|tiff?)$/.test(ext)) return 'images';
    if (/^(mov|mp4|m4v)$/.test(ext)) return 'videos';
    return 'docs';
  }
  var CARD = { images: '#bk-file-jpg', videos: '#bk-file-mov', docs: '#bk-file-pdf' };
  var TAGLINES = [
    'Fussy folder. Meet Binky.', 'Files acting up? Pop in a Binky.', 'Quiets the mess right down.',
    'Files were screaming. Binky helped.', 'The pacifier for your folders.', "Sh. Binky's handling it."
  ];

  /* ---------- The organizer: a Quick Sort of Downloads, start to finish ---------- */
  function sortDemo(win) {
    var stage = win.closest('.desktop__stage');
    var caption = $('[data-sort-caption]', win);
    var fill = $('[data-sort-fill]', win);
    var pct = $('[data-sort-pct]', win);
    var card = $('[data-sort-card]', win);
    var cardUse = card && card.querySelector('use');
    var badge = $('[data-review-count]', win);
    var hint = $('[data-sort-hint]', win);
    var latest = $('[data-sort-latest]', win);
    var tagline = $('[data-sort-tagline]', win);
    var replay = stage && $('[data-sort-replay]', stage);
    var buckets = {};
    $$('[data-bucket]', win).forEach(function (b) { buckets[b.getAttribute('data-bucket')] = b; });
    var TOTAL = 215, DURATION = 7600, run = 0, tagIndex = 3, tagTimer = 0;

    function show(done) {
      var shown = Math.min(done + 1, TOTAL);
      caption.textContent = shown + ' of ' + TOTAL + ' — ' + FILES[Math.min(done, TOTAL - 1) % FILES.length];
      fill.style.width = (done / TOTAL * 100) + '%';
      pct.textContent = Math.floor(done / TOTAL * 100) + '%';
    }

    function bump(name) {
      var b = buckets[name];
      if (!b) return;
      b.classList.add('is-bump');
      setTimeout(function () { b.classList.remove('is-bump'); }, 260);
    }

    // The slow-mode flight from OrganizerEmptyStateView: appear, glide to the bucket, drop in.
    function fly(name) {
      if (!card || !card.animate) return;
      if (cardUse) cardUse.setAttribute('href', CARD[name]);
      var x = name === 'images' ? -120 : name === 'docs' ? 120 : 0;
      var lean = name === 'videos' ? 0 : name === 'images' ? -8 : 8;
      var tilt = Math.round(Math.random() * 20 - 10);
      card.animate([
        { transform: 'translate(0, -50px) scale(0.55) rotate(' + tilt + 'deg)', opacity: 0, offset: 0 },
        { transform: 'translate(0, -20px) scale(1) rotate(0deg)', opacity: 1, offset: 0.38, easing: 'cubic-bezier(0.4, 0, 0.2, 1)' },
        { transform: 'translate(' + x + 'px, 56px) scale(1) rotate(' + lean + 'deg)', opacity: 1, offset: 0.8, easing: 'ease-in' },
        { transform: 'translate(' + x + 'px, 80px) scale(0.3) rotate(' + lean + 'deg)', opacity: 0, offset: 1 }
      ], { duration: 1250, fill: 'forwards' });
      setTimeout(function () { bump(name); }, 1000);
    }

    function rotateTagline() {
      clearInterval(tagTimer);
      if (still() || !tagline) return;
      tagTimer = setInterval(function () {
        tagline.style.opacity = '0';
        setTimeout(function () {
          tagIndex = (tagIndex + 1) % TAGLINES.length;
          tagline.textContent = TAGLINES[tagIndex];
          tagline.style.opacity = '';
        }, 350);
      }, 8000);
    }

    function reset() {
      win.classList.remove('is-done');
      if (replay) replay.hidden = true;
      if (hint) hint.hidden = false;
      if (latest) latest.hidden = true;
      if (badge) badge.textContent = '91';
      if (card) { card.getAnimations && card.getAnimations().forEach(function (a) { a.cancel(); }); card.style.opacity = '0'; }
      show(0);
    }

    function finish() {
      win.classList.add('is-done');
      clearInterval(tagTimer);
      if (hint) hint.hidden = true;
      if (latest) latest.hidden = false;
      if (badge) badge.textContent = '99';
      if (replay) replay.hidden = false;
    }

    function play() {
      var me = ++run;
      reset();
      rotateTagline();
      var start = 0, lastFlight = -1e9, flown = 0;
      wait(500).then(function () {
        if (me !== run) return;
        requestAnimationFrame(function frame(now) {
          if (me !== run) return;
          if (!start) start = now;
          var t = Math.min(1, (now - start) / DURATION);
          var done = Math.round(TOTAL * (1 - Math.pow(1 - t, 1.4)));
          show(done);
          if (now - lastFlight > 1350 && t < 0.86) {
            lastFlight = now;
            fly(bucketFor(FILES[(done + flown++) % FILES.length]));
          }
          if (t < 1) { requestAnimationFrame(frame); return; }
          caption.textContent = TOTAL + ' of ' + TOTAL + ' — ' + FILES[(TOTAL - 1) % FILES.length];
          wait(800).then(function () { if (me === run) finish(); });
        });
      });
    }

    // Reduced Motion keeps the still from the app: mid-run, 71 of 215.
    if (still()) return;
    onVisible(win, play, 0.45);
    if (replay) replay.addEventListener('click', function () { play(); win.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); });
  }

  /* ---------- Settings › Routines: pick a routine, switch it on or off ---------- */
  function routinesDemo(win) {
    var list = $('[data-prefs-list]', win);
    var top = $('[data-prefs-top]', win);
    // Scroll the sidebar like the screenshot, so Routines sits in view.
    if (list && top) list.scrollTop = top.offsetTop - 6;

    var routines = [
      { name: 'Sort my Downloads', folder: 'Downloads', rules: '', on: true },
      { name: 'Auto-install DMGs', folder: 'Downloads', rules: ' · 1 rule', on: true }
    ];
    var rows = $$('[data-routine]', win);
    var nameField = $('[data-routine-name]', win);
    var toggle = $('[data-routine-enable]', win);
    var sel = 0;
    function subtitle(r) { return (r.on ? r.folder : 'Off') + r.rules; }
    function render() {
      rows.forEach(function (row, i) {
        row.setAttribute('aria-pressed', String(i === sel));
        var sub = $('[data-routine-sub]', row);
        if (sub) sub.textContent = subtitle(routines[i]);
      });
      if (nameField) nameField.textContent = routines[sel].name;
      if (toggle) toggle.setAttribute('aria-checked', String(routines[sel].on));
    }
    rows.forEach(function (row, i) { row.addEventListener('click', function () { sel = i; render(); }); });
    if (toggle) toggle.addEventListener('click', function () { routines[sel].on = !routines[sel].on; render(); });
    render();
  }

  /* ---------- Currently sorting: the count climbs, Pause holds it ---------- */
  function sheetDemo(scene) {
    var sheet = $('[data-sheet]', scene);
    var caption = $('[data-sheet-caption]', scene);
    var fill = $('[data-sheet-fill]', scene);
    var pct = $('[data-sheet-pct]', scene);
    var pause = $('[data-sheet-pause]', scene);
    var items = $$('[data-sheet-list] b', scene);
    var TOTAL = 650, TARGET = 96, done = still() ? TARGET - 1 : 0, paused = false, ticker = 0, offset = 0;

    // The caption names the first file in Working on, as the app does.
    function name() { return FILES[(offset + 1) % FILES.length]; }
    function render() {
      var base = (done + 1) + ' of ' + TOTAL;
      caption.textContent = paused ? 'Paused — ' + base : base + ' — ' + name();
      fill.style.width = (done / TOTAL * 100) + '%';
      pct.textContent = Math.floor(done / TOTAL * 100) + '%';
    }
    function shiftRows() {
      offset++;
      items.forEach(function (b, i) { b.textContent = FILES[(offset + i + 1) % FILES.length]; });
    }
    function tick() {
      if (paused || done >= TOTAL - 1) return;
      done++;
      render();
      shiftRows();
    }
    function countUp() {
      var start = 0, from = done;
      requestAnimationFrame(function frame(now) {
        if (!start) start = now;
        var t = Math.min(1, (now - start) / 1600);
        if (!paused) { done = Math.round(from + (TARGET - 1 - from) * (1 - Math.pow(1 - t, 3))); render(); }
        if (t < 1) { requestAnimationFrame(frame); return; }
        ticker = setInterval(tick, 1400);
      });
    }

    if (pause) pause.addEventListener('click', function () {
      paused = !paused;
      sheet.classList.toggle('is-paused', paused);
      pause.querySelector('span').textContent = paused ? 'Resume' : 'Pause';
      pause.querySelector('use').setAttribute('href', paused ? '#sf-play' : '#sf-pause');
      render();
    });

    render();
    if (still()) return;
    onVisible(scene, countUp, 0.4);
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) { clearInterval(ticker); ticker = 0; }
      else if (!ticker && done >= TARGET - 1) ticker = setInterval(tick, 1400);
    });
  }

  function init() {
    $$('[data-bk-sort]').forEach(sortDemo);
    $$('[data-bk-routines]').forEach(routinesDemo);
    $$('[data-bk-sheet]').forEach(sheetDemo);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
