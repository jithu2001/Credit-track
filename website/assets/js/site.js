// WholeFlow product site: scroll-driven phone screens, count-up, small reveals.
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

  // Sections that animate once when they come into view.
  const once = new IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('in-view');
      once.unobserve(e.target);
    }
  }, { threshold: 0.35 });
  $$('.flow, .field, .reveal').forEach(el => once.observe(el));

  // The flow diagram's moving packets: SMIL animations, paused for reduced motion.
  const flowSvg = $('.flow-svg');
  if (flowSvg && reduce && flowSvg.pauseAnimations) flowSvg.pauseAnimations();

  // Feature steps switch the sticky phone's screen.
  const screens = $$('.screen');
  const steps = $$('.story-step');
  const show = name => {
    screens.forEach(s => s.classList.toggle('is-on', s.dataset.screen === name));
    steps.forEach(s => s.classList.toggle('is-on', s.dataset.screen === name));
  };
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
        $('#contactDone').hidden = false;
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
