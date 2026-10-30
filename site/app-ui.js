/*
 * The recreated Binky windows on the homepage (app-ui.css): the organizer counts through a Quick Sort
 * when it scrolls into view and ends with a toast, the watch status pauses and resumes, the Routines
 * pane picks and switches routines, and the Review sheet moves files to their suggested folders.
 * Guided feature rows open a scene per step. Every file name is made up. Everything honors Reduced Motion.
 */
(function () {
  'use strict';
  var mq = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
  function still() { return document.documentElement.classList.contains('fmb-still') || !!(mq && mq.matches); }
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
    var digest = $('[data-sort-digest]', win);
    var sortNow = $('[data-sort-now]', win);
    var toast = $('[data-sort-toast]', win);
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

    // After the run, Sort Now again: nothing left, so the app says so in a toast that leaves on its own (3 s).
    function sortAgain(me) {
      wait(1800).then(function () {
        if (me !== run || !toast) return;
        if (sortNow) { sortNow.classList.add('is-press'); setTimeout(function () { sortNow.classList.remove('is-press'); }, 180); }
        return wait(260).then(function () {
          if (me !== run) return;
          toast.classList.add('is-on');
          return wait(3000).then(function () { if (me === run) toast.classList.remove('is-on'); });
        });
      });
    }

    function reset() {
      win.classList.remove('is-done');
      if (toast) toast.classList.remove('is-on');
      if (replay) replay.hidden = true;
      if (hint) hint.hidden = false;
      if (latest) latest.hidden = true;
      if (digest) digest.hidden = true;
      if (badge) badge.textContent = '91';
      if (card) { card.getAnimations && card.getAnimations().forEach(function (a) { a.cancel(); }); card.style.opacity = '0'; }
      show(0);
    }

    function finish(me) {
      win.classList.add('is-done');
      clearInterval(tagTimer);
      if (hint) hint.hidden = true;
      if (latest) latest.hidden = false;
      if (digest) digest.hidden = false;
      if (badge) badge.textContent = '99';
      if (replay) replay.hidden = false;
      sortAgain(me);
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
          wait(800).then(function () { if (me === run) finish(me); });
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
    // Opening its step starts the pane fresh.
    var scene = win.closest('[data-scene]');
    if (scene) scene.addEventListener('scene:show', function () {
      sel = 0;
      routines.forEach(function (r) { r.on = true; });
      if (list && top) list.scrollTop = top.offsetTop - 6;
      render();
    });
    render();
  }

  /* ---------- The organizer's watch status: pause and resume, keep the routines ---------- */
  function watchDemo(win) {
    var row = $('[data-watch]', win);
    var label = $('[data-watch-label]', win);
    var btn = $('[data-watch-toggle]', win);
    if (!row || !btn) return;
    var use = btn.querySelector('use');
    function set(watching) {
      row.classList.toggle('is-watching', watching);
      if (label) label.textContent = watching ? 'Watching 2 folders' : 'Paused';
      btn.setAttribute('aria-label', watching ? 'Pause watching' : 'Resume watching');
      if (use) use.setAttribute('href', watching ? '#sf-pause-circle' : '#sf-play-circle');
    }
    btn.addEventListener('click', function () { set(!row.classList.contains('is-watching')); });
    var scene = win.closest('[data-scene]');
    if (scene) scene.addEventListener('scene:show', function () { set(true); });
  }

  /* ---------- Guided feature rows: each step opens its scene on the desktop ----------
   * While the row is at least 45% on screen the steps advance every 6.5 seconds; a mouse over the row
   * holds the current step, a click or the arrow keys take over, and Reduce Motion turns advancing off.
   * On touch, tapping a step stops advancing for good (there is no hover to hold it). When the steps
   * stack above the desktop (phones, tablets), scrolling holds advancing too, and the steps keep the
   * height of their tallest step so the desktop below never jumps while someone is reading or scrolling.
   * Opening a scene sends it "scene:show" so a demo inside can start again. */
  function guided(row) {
    var DUR = 6500;
    var steps = $$('[data-step]', row);
    var scenes = $$('[data-scene]', row);
    var list = $('.g-steps', row);
    var stacked = window.matchMedia ? window.matchMedia('(max-width: 900px)') : null;
    var at = 0, timer = 0, inView = false, hover = false, manual = false, scrolling = false, idle = 0;
    row.style.setProperty('--g-dur', DUR + 'ms');
    function schedule() {
      clearTimeout(timer);
      var playing = inView && !hover && !manual && !scrolling && !still();
      row.classList.toggle('is-playing', playing);
      if (playing) timer = setTimeout(function () { open((at + 1) % steps.length); }, DUR);
    }
    // Reserve the tallest open step's height, so opening a shorter one doesn't pull the desktop up.
    function holdHeight() {
      if (!list) return;
      list.style.minHeight = '';
      if (!stacked || !stacked.matches) return;
      var gap = parseFloat(getComputedStyle(list).rowGap) || 0, total = gap * (steps.length - 1), tallest = 0;
      steps.forEach(function (s) {
        var text = s.querySelector('.g-step__text');
        var h = s.getBoundingClientRect().height;
        if (!text) { total += h; return; }
        total += h - text.getBoundingClientRect().height;
        tallest = Math.max(tallest, text.scrollHeight - (parseFloat(getComputedStyle(text).paddingTop) || 0));
      });
      list.style.minHeight = Math.ceil(total + tallest + 6) + 1 + 'px';
    }
    function open(n, focus) {
      at = n;
      steps.forEach(function (s, k) {
        var on = k === n;
        s.classList.toggle('is-on', on);
        s.setAttribute('aria-selected', String(on));
        s.tabIndex = on ? 0 : -1;
        // Restart the progress line.
        var bar = s.querySelector('.g-step__bar');
        if (bar) { bar.style.animation = 'none'; void bar.offsetWidth; bar.style.animation = ''; }
      });
      scenes.forEach(function (sc, k) {
        var on = k === n;
        sc.classList.toggle('is-on', on);
        sc.hidden = !on;
        if (on) sc.dispatchEvent(new CustomEvent('scene:show'));
      });
      if (focus) steps[n].focus();
      schedule();
    }
    steps.forEach(function (s, k) {
      var touched = false;
      s.addEventListener('pointerdown', function (e) { touched = e.pointerType !== 'mouse'; });
      s.addEventListener('click', function () {
        if (touched) manual = true;
        touched = false;
        open(k);
      });
      s.addEventListener('keydown', function (e) {
        var d = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return;
        e.preventDefault();
        open((at + d + steps.length) % steps.length, true);
      });
    });
    row.addEventListener('pointerenter', function (e) { if (e.pointerType === 'mouse') { hover = true; schedule(); } });
    row.addEventListener('pointerleave', function (e) { if (e.pointerType === 'mouse') { hover = false; schedule(); } });
    window.addEventListener('scroll', function () {
      if (!inView || !stacked || !stacked.matches) return;
      if (!scrolling) { scrolling = true; schedule(); }
      clearTimeout(idle);
      idle = setTimeout(function () { scrolling = false; schedule(); }, 900);
    }, { passive: true });
    var resizeTimer = 0;
    window.addEventListener('resize', function () { clearTimeout(resizeTimer); resizeTimer = setTimeout(holdHeight, 150); });
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(holdHeight);
    holdHeight();
    if (mq && mq.addEventListener) mq.addEventListener('change', schedule);
    if (!('IntersectionObserver' in window)) return;
    new IntersectionObserver(function (entries) {
      inView = entries[0].isIntersecting;
      schedule();
    }, { threshold: 0.45 }).observe(row);
  }

  /* ---------- Review: move a file to its suggested folder, or wave off the habit ---------- */
  function triageDemo(scene) {
    var list = $('[data-triage-list]', scene);
    var empty = $('[data-triage-empty]', scene);
    var badge = $('[data-triage-badge]', scene);
    var habit = $('[data-triage-habit]', scene);
    var dismiss = $('[data-triage-dismiss]', scene);
    function left() { return $$('[data-triage-row]', list).length; }
    function settle() {
      var n = left();
      if (badge) { badge.textContent = String(n); badge.hidden = n === 0; }
      if (!n) { list.hidden = true; if (empty) empty.hidden = false; }
    }
    // The app reloads the list after a move; here the row fades and closes up.
    $$('[data-triage-move]', scene).forEach(function (btn) {
      btn.addEventListener('click', function () {
        var row = btn.closest('[data-triage-row]');
        if (!row || row.classList.contains('is-gone')) return;
        if (still() || !row.animate) { row.remove(); settle(); return; }
        row.classList.add('is-gone');
        var h = row.offsetHeight;
        row.animate([{ height: h + 'px', paddingTop: '12px', paddingBottom: '12px' }, { height: '0px', paddingTop: '0px', paddingBottom: '0px' }],
          { duration: 300, delay: 120, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', fill: 'forwards' })
          .finished.then(function () { row.remove(); settle(); });
      });
    });
    if (dismiss && habit) dismiss.addEventListener('click', function () { habit.hidden = true; });
  }

  function init() {
    $$('[data-bk-sort]').forEach(sortDemo);
    $$('[data-bk-routines]').forEach(routinesDemo);
    $$('[data-bk-triage]').forEach(triageDemo);
    $$('[data-bk-watch]').forEach(watchDemo);
    $$('[data-guided]').forEach(guided);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
