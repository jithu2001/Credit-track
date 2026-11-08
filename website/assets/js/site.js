// WholeFlow product site: scroll-driven phone screens, count-up, small reveals,
// mobile menu and the price calculator.
(() => {
  'use strict';
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];

  // Header gets a hairline once the page scrolls.
  const top = $('.top');
  const onScroll = () => top.classList.toggle('scrolled', scrollY > 8);
  addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  // Mobile menu: the button only appears when the script runs, so without
  // JavaScript the header still has its "Talk to us" link.
  const menuBtn = $('.menu-btn');
  const nav = $('#menu');
  if (menuBtn && nav) {
    menuBtn.hidden = false;
    const setMenu = open => {
      top.classList.toggle('menu-open', open);
      menuBtn.setAttribute('aria-expanded', String(open));
      menuBtn.setAttribute('aria-label', open ? 'Close menu' : 'Menu');
    };
    menuBtn.addEventListener('click', () => setMenu(!top.classList.contains('menu-open')));
    nav.addEventListener('click', e => { if (e.target.closest('a')) setMenu(false); });
    addEventListener('keydown', e => {
      if (e.key === 'Escape' && top.classList.contains('menu-open')) { setMenu(false); menuBtn.focus(); }
    });
    document.addEventListener('click', e => { if (!top.contains(e.target)) setMenu(false); });
    matchMedia('(min-width: 861px)').addEventListener('change', e => { if (e.matches) setMenu(false); });
  }

  // The nav link of the section in the middle of the window is marked.
  const navLinks = $$('.nav a[href^="#"]');
  const spy = new IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      navLinks.forEach(a => a.classList.toggle('is-active', a.getAttribute('href') === '#' + e.target.id));
    }
  }, { rootMargin: '-45% 0px -50% 0px' });
  // Every section is watched, so sections without a link clear the mark.
  $$('main > section').forEach(s => spy.observe(s));

  // Sections that animate once when they come into view.
  const once = new IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('in-view');
      once.unobserve(e.target);
    }
  }, { threshold: 0.35 });
  $$('.flow, .field, .trust, .reveal').forEach(el => once.observe(el));
  // Groups can be taller than the window on phones, so they start earlier.
  const groups = new IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('in-view');
      groups.unobserve(e.target);
    }
  }, { threshold: 0.12 });
  $$('.reveal-group').forEach(el => groups.observe(el));

  // The flow diagram's moving packets: SMIL animations, paused for reduced motion.
  const flowSvg = $('.flow-svg');
  if (flowSvg && reduce && flowSvg.pauseAnimations) flowSvg.pauseAnimations();

  // Feature steps switch the sticky phone's screen.
  const screens = $$('.screen');
  const steps = $$('.story-step');
  const marks = [...screens, ...steps, ...$$('.story-dots span')];
  const show = name => marks.forEach(s => s.classList.toggle('is-on', s.dataset.screen === name));
  if (steps.length) {
    // The step nearest the middle of the window decides the screen.
    let queued = false;
    const pick = () => {
      queued = false;
      const mid = innerHeight / 2;
      let best = steps[0], bestDist = Infinity;
      for (const s of steps) {
        const r = s.getBoundingClientRect();
        const d = Math.abs(r.top + r.height / 2 - mid);
        if (d < bestDist) { best = s; bestDist = d; }
      }
      show(best.dataset.screen);
    };
    addEventListener('scroll', () => { if (!queued) { queued = true; requestAnimationFrame(pick); } }, { passive: true });
    addEventListener('resize', pick);
    pick();
  }

  // The hero's outstanding figure counts up in Indian grouping.
  const amount = $('[data-count]');
  if (amount && !reduce) {
    const target = Number(amount.dataset.count);
    const fmt = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', minimumFractionDigits: 2 });
    const start = performance.now() + 350;
    const dur = 1400;
    const tick = now => {
      const t = Math.min(1, Math.max(0, (now - start) / dur));
      const eased = 1 - Math.pow(1 - t, 3);
      amount.textContent = fmt.format(target * eased);
      if (t < 1) requestAnimationFrame(tick);
    };
    amount.textContent = fmt.format(0);
    requestAnimationFrame(tick);
  }

  // Price calculator: ₹600 for the first company, ₹200 for each one after.
  // Without JavaScript the table of examples shows instead.
  const calc = $('.calc');
  if (calc) {
    const n = $('#calcN'), total = $('#calcTotal'), bars = $$('.calc-bars span', calc);
    const [less, more] = $$('.step-btn', calc);
    const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });
    let count = 1;
    const render = () => {
      n.textContent = count;
      total.textContent = inr.format(600 + 200 * (count - 1));
      bars.forEach((b, i) => b.classList.toggle('on', i < count));
      less.disabled = count <= 1;
      more.disabled = count >= bars.length;
    };
    $$('.step-btn', calc).forEach(b => b.addEventListener('click', () => {
      count = Math.min(bars.length, Math.max(1, count + Number(b.dataset.step)));
      render();
      // A button that just reached its limit is disabled; keep focus usable.
      if (b.disabled) (b === less ? more : less).focus();
    }));
    $('.plan-eg').hidden = true;
    calc.hidden = false;
    render();
  }

  // Contact form: posts to /api/contact (nginx forwards it to the WholeFlow
  // server), shown to the team in the admin app under Enquiries.
  const form = $('#contactForm');
  if (form) {
    const err = $('.cf-error', form);
    const btn = $('button[type=submit]', form);
    const fail = msg => { err.textContent = msg; err.hidden = false; };
    // "Ask for a quote" and similar links can preselect the company count.
    $$('a[data-companies]').forEach(a => a.addEventListener('click', () => { form.companies.value = a.dataset.companies; }));
    form.addEventListener('submit', async ev => {
      ev.preventDefault();
      err.hidden = true;
      const data = Object.fromEntries(new FormData(form));
      const digits = (data.phone || '').replace(/\D/g, '').replace(/^(91|0)(?=\d{10}$)/, '');
      if (!data.name.trim()) return fail('Please enter your name.');
      if (!/^[6-9]\d{9}$/.test(digits)) return fail('Please enter a 10-digit mobile number.');
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.email.trim())) return fail('Please enter a valid email address.');
      btn.disabled = true;
      btn.textContent = 'Sending…';
      try {
        const res = await fetch('/api/contact', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
        const body = await res.json().catch(() => null);
        if (!res.ok) throw new Error(body?.error?.message || 'Something went wrong. Please try again.');
        form.hidden = true;
        const done = $('#contactDone');
        done.hidden = false;
        done.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        $('h2', done).focus({ preventScroll: true });
      } catch (e) {
        fail(e instanceof TypeError ? 'Could not send. Check your internet connection and try again.' : e.message);
        btn.disabled = false;
        btn.textContent = 'Send my details';
      }
    });
  }

  const year = $('#year');
  if (year) year.textContent = new Date().getFullYear();
})();
