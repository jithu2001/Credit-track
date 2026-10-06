// WholeFlow admin app: one page, hash routes, talks to /control/admin/*.
'use strict';

// ------------------------------------------------------------ helpers

const $app = document.getElementById('app');
const TOKEN = 'wf-admin-token';

function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'class') el.className = v;
    else if (k === 'value') el.value = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    el.append(kid instanceof Node ? kid : String(kid));
  }
  return el;
}

// Material icons (Apache 2.0), inline so the page needs nothing from outside.
const ICONS = {
  store: 'M20 4H4v2h16V4zm1 10v-2l-1-5H4l-1 5v2h1v6h10v-6h4v6h2v-6h1zm-9 4H6v-4h6v4z',
  sell: 'M21.41 11.58l-9-9C12.05 2.22 11.55 2 11 2H4c-1.1 0-2 .9-2 2v7c0 .55.22 1.05.59 1.42l9 9c.36.36.86.58 1.41.58.55 0 1.05-.22 1.41-.59l7-7c.37-.36.59-.86.59-1.41 0-.55-.23-1.06-.59-1.42zM5.5 7C4.67 7 4 6.33 4 5.5S4.67 4 5.5 4 7 4.67 7 5.5 6.33 7 5.5 7z',
  settings: 'M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.488.488 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 0 0-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z',
  logout: 'M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z',
  add: 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
  back: 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
  copy: 'M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z',
  download: 'M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z',
  pay: 'M20 4H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V6c0-1.11-.89-2-2-2zm0 14H4v-6h16v6zm0-10H4V6h16v2z',
  pc: 'M20 18c1.1 0 1.99-.9 1.99-2L22 6c0-1.1-.9-2-2-2H4c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2H0v2h24v-2h-4zM4 6h16v10H4V6z',
  delete: 'M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
  warning: 'M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z',
  inbox: 'M19 3H4.99C3.88 3 3.01 3.9 3.01 5L3 19c0 1.1.88 2 1.99 2H19c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 12h-4c0 1.66-1.35 3-3 3s-3-1.34-3-3H4.99V5H19v10z',
  call: 'M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.33.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z',
  mail: 'M20 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4l-8 5-8-5V6l8 5 8-5v2z',
  chat: 'M20 2H4c-1.1 0-1.99.9-1.99 2L2 22l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zM6 9h12v2H6V9zm8 5H6v-2h8v2zm4-6H6V6h12v2z',
  key: 'M12.65 10A5.99 5.99 0 0 0 7 6c-3.31 0-6 2.69-6 6s2.69 6 6 6a5.99 5.99 0 0 0 5.65-4H17v4h4v-4h2v-4H12.65zM7 14c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z',
};

function icon(name, small) {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('class', 'icon' + (small ? ' s' : ''));
  svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS(ns, 'path');
  path.setAttribute('d', ICONS[name]);
  svg.append(path);
  return svg;
}

function toast(msg, error) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'show' + (error ? ' error' : '');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.className = ''), error ? 6000 : 2500);
}

class ApiError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}

async function api(method, path, body) {
  const headers = {};
  const tok = sessionStorage.getItem(TOKEN);
  if (tok) headers.Authorization = 'Bearer ' + tok;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  let res;
  try {
    res = await fetch('/control/admin' + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  } catch {
    throw new ApiError(0, 'NETWORK', 'Cannot reach the server. Check the connection.');
  }
  const data = await res.json().catch(() => null);
  if (res.status === 401 && path !== '/login') {
    sessionStorage.removeItem(TOKEN);
    render();
    throw new ApiError(401, 'UNAUTHENTICATED', 'Sign in again.');
  }
  if (!res.ok && !(data && 'output' in data)) {
    const e = (data && data.error) || {};
    throw new ApiError(res.status, e.code || 'ERROR', e.message || 'Something went wrong.');
  }
  return data;
}

// run: disable the button while an action runs and report errors.
async function run(btn, fn) {
  if (btn) btn.disabled = true;
  try { return await fn(); }
  catch (e) { if (e.status !== 401) toast(e.message, true); }
  finally { if (btn) btn.disabled = false; }
}

function formData(form) {
  const out = {};
  for (const el of form.elements) if (el.name) out[el.name] = el.type === 'number' ? (el.value === '' ? null : Number(el.value)) : el.value.trim();
  return out;
}

const rupees = n => '₹' + Number(n || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const today = () => new Date(Date.now() + 330 * 60000).toISOString().slice(0, 10); // India date
function date(s) {
  if (!s) return '—';
  const d = new Date(s.length === 10 ? s + 'T00:00:00' : s);
  return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}
function when(s) {
  if (!s) return '—';
  const d = new Date(s), mins = (Date.now() - d) / 60000;
  if (mins < 2) return 'just now';
  if (mins < 60) return Math.round(mins) + ' min ago';
  if (mins < 1440) return Math.round(mins / 60) + ' h ago';
  return d.toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}
function daysUntil(s) { return Math.round((new Date(s + 'T00:00:00Z') - new Date(today() + 'T00:00:00Z')) / 86400000); }

const STATES = { active: 'Active', renewal_due: 'Renewal due', grace: 'Grace period', ended: 'Blocked' };
const badge = (cls, text) => h('span', { class: 'badge b-' + cls }, text);
function stateBadge(b) {
  if (b.status !== 'active') return badge(b.status, b.status === 'closed' ? 'Closed' : 'Suspended');
  return badge(b.state, STATES[b.state] || b.state);
}

function copyable(value, label) {
  return h('div', { class: 'secret' },
    h('span', { class: 'mono' }, value),
    h('button', { type: 'button', onclick: () => navigator.clipboard.writeText(value).then(() => toast((label || 'Value') + ' copied')) }, icon('copy', true), 'Copy'));
}

// QR code of a reference key, for the phone apps' "Scan QR code".
function qrImage(text) {
  const qr = qrcode(0, 'M');
  qr.addData(text);
  qr.make();
  return h('img', { class: 'qr', src: qr.createDataURL(6, 4), alt: 'QR code for ' + text, width: qr.getModuleCount() * 6 + 48 });
}

function field(label, input, hint) {
  return h('div', { class: 'field' }, h('label', {}, h('span', {}, label), input), hint && h('div', { class: 'hint' }, hint));
}

function confirmTyped(message, expected) {
  const got = prompt(message + `\n\nType "${expected}" to confirm.`);
  return got != null && got.trim().toLowerCase() === expected.toLowerCase();
}

// ------------------------------------------------------------ shell and routing

let me = null;

async function render() {
  if (!sessionStorage.getItem(TOKEN)) { me = null; return showLogin(); }
  if (!me) {
    try { me = await api('GET', '/me'); }
    catch { return; }
  }
  const [, page, id] = (location.hash || '#/').split('/');
  const routes = { '': pageBusinesses, new: pageNew, b: () => pageBusiness(id), plans: pagePlans, leads: pageLeads, settings: pageSettings };
  const main = h('main', {}, h('p', { class: 'muted' }, 'Loading…'));
  const item = (href, ic, text, on) =>
    h('a', { href, class: 'rail-item' + (on ? ' on' : ''), 'aria-current': on ? 'page' : null }, h('span', { class: 'ind' }, icon(ic)), text);
  $app.replaceChildren(
    h('div', { class: 'shell' },
      h('aside', { class: 'rail' },
        h('div', { class: 'logo', title: 'WholeFlow Admin' }, 'W'),
        h('nav', {},
          item('#/', 'store', 'Businesses', page === '' || page === 'b' || page === 'new'),
          item('#/plans', 'sell', 'Plans', page === 'plans'),
          leadsItem(page === 'leads'),
          item('#/settings', 'settings', 'Settings', page === 'settings'),
          h('button', { class: 'rail-item', onclick: logout, title: 'Sign out ' + me.email }, h('span', { class: 'ind' }, icon('logout')), 'Sign out')),
        h('div', { class: 'spacer' }),
        h('div', { class: 'who', title: [me.name, me.email].filter(Boolean).join(' · ') }, (me.name || me.email || '?').trim().charAt(0).toUpperCase())),
      h('div', { class: 'content' }, main)));
  try { main.replaceChildren(...[await (routes[page] || pageBusinesses)()].flat()); }
  catch (e) { if (e.status !== 401) main.replaceChildren(h('div', { class: 'notice bad' }, e.message)); }
}

window.addEventListener('hashchange', render);
document.addEventListener('DOMContentLoaded', render);

async function logout() {
  await api('POST', '/logout').catch(() => {});
  sessionStorage.removeItem(TOKEN);
  me = null;
  location.hash = '#/';
  render();
}

function showLogin() {
  const err = h('div', { class: 'notice bad', hidden: true });
  const form = h('form', { class: 'card login', onsubmit: async ev => {
    ev.preventDefault();
    const btn = form.querySelector('button');
    btn.disabled = true;
    err.hidden = true;
    try {
      const r = await api('POST', '/login', formData(form));
      sessionStorage.setItem(TOKEN, r.token);
      me = null;
      render();
    } catch (e) {
      err.textContent = e.message;
      err.hidden = false;
      btn.disabled = false;
    }
  } },
    h('div', { class: 'logo' }, 'W'),
    h('h1', {}, 'WholeFlow Admin'),
    h('p', { class: 'muted' }, 'Sign in to manage businesses and subscriptions.'),
    err,
    field('Email', h('input', { name: 'email', type: 'email', autocomplete: 'username', required: true, autofocus: true })),
    field('Password', h('input', { name: 'password', type: 'password', autocomplete: 'current-password', required: true })),
    h('button', { class: 'primary', type: 'submit' }, 'Sign in'));
  $app.replaceChildren(h('div', { class: 'login-wrap' }, form));
}

// ------------------------------------------------------------ businesses

let plansCache = null;
async function plans() { return plansCache || (plansCache = await api('GET', '/plans')); }

async function pageBusinesses() {
  const [list, ps] = await Promise.all([api('GET', '/businesses'), plans()]);
  const price = Object.fromEntries(ps.map(p => [p.code, p.price_month]));
  const live = list.filter(b => b.status === 'active');
  const count = s => live.filter(b => b.state === s).length;
  const monthly = live.filter(b => b.state !== 'ended').reduce((sum, b) => sum + (price[b.plan_code] || 0), 0);

  const search = h('input', { type: 'search', placeholder: 'Search name, short name, phone…', oninput: () => fill() });
  const body = h('tbody');
  const fill = () => {
    const q = search.value.trim().toLowerCase();
    const rows = list.filter(b => !q || [b.name, b.slug, b.phone, b.email, b.contact_name].some(v => (v || '').toLowerCase().includes(q)));
    body.replaceChildren(...rows.map(b => {
      const d = daysUntil(b.paid_until);
      return h('tr', { class: 'click', onclick: () => (location.hash = '#/b/' + b.id) },
        h('td', {}, h('div', {}, b.name), h('div', { class: 'muted small mono' }, b.slug)),
        h('td', {}, b.plan_name),
        h('td', {}, date(b.paid_until), h('div', { class: 'muted small' }, d >= 0 ? `in ${d} days` : `${-d} days ago`)),
        h('td', {}, stateBadge(b)),
        h('td', {}, b.devices),
        h('td', {}, when(b.last_seen_at)),
        h('td', {}, b.contact_name || '', h('div', { class: 'muted small' }, b.phone || '')));
    }));
    if (!rows.length) body.append(h('tr', {}, h('td', { colspan: 7, class: 'muted' }, list.length ? 'No match.' : 'No businesses yet.')));
  };
  fill();

  const stat = (n, l) => h('div', { class: 'card stat' }, h('div', { class: 'n' }, n), h('div', { class: 'l' }, l));
  return [
    h('h1', {}, 'Businesses'),
    h('div', { class: 'stats' },
      stat(live.length, 'Active businesses'),
      stat(count('renewal_due'), 'Renewal due soon'),
      stat(count('grace'), 'In grace period'),
      stat(count('ended') + list.filter(b => b.status === 'suspended').length, 'Blocked or suspended'),
      stat(rupees(monthly), 'Monthly value (paying)')),
    h('div', { class: 'card' }, search, h('div', { class: 'scroll' }, h('table', {},
      h('thead', {}, h('tr', {}, ...['Business', 'Plan', 'Paid until', 'State', 'PCs', 'Last sync', 'Contact'].map(t => h('th', {}, t)))),
      body))),
    h('button', { class: 'fab', onclick: () => (location.hash = '#/new') }, icon('add'), 'New business'),
  ].map(wrapGap);
}

const wrapGap = el => { el.classList.add('gap'); return el; };

async function pageNew() {
  const ps = (await plans()).filter(p => p.active);
  const out = h('div');
  const slug = h('input', { name: 'slug', required: true, pattern: '[a-z][a-z0-9]{1,19}', maxlength: 20, placeholder: 'jmj' });
  let slugTouched = false;
  slug.addEventListener('input', () => (slugTouched = true));
  const name = h('input', { name: 'name', required: true, placeholder: 'JMJ Marketing', oninput: () => {
    if (!slugTouched) slug.value = name.value.toLowerCase().replace(/[^a-z0-9]/g, '').replace(/^[0-9]+/, '').slice(0, 20);
  } });
  const form = h('form', { class: 'card', onsubmit: async ev => {
    ev.preventDefault();
    const btn = form.querySelector('button[type=submit]');
    const data = formData(form);
    btn.textContent = 'Creating… (about 20 seconds)';
    await run(btn, async () => {
      const r = await api('POST', '/businesses', data);
      form.remove();
      out.replaceChildren(created(r, data));
    });
    btn.textContent = 'Create business';
  } },
    h('h2', {}, 'Business'),
    h('div', { class: 'two' },
      field('Business name', name),
      field('Short name', slug, 'Used in its web address and keys. 2–20 lowercase letters or digits. Cannot change later.')),
    h('div', { class: 'two' },
      field('Plan', h('select', { name: 'plan_code' }, ...ps.map(p => h('option', { value: p.code }, `${p.name} — ${rupees(p.price_month)}/month, ${p.max_companies} ${p.max_companies === 1 ? 'company' : 'companies'}`)))),
      field('Paid until', h('input', { name: 'paid_until', type: 'date' }), 'Leave empty for a 14-day trial.')),
    h('div', { class: 'two' },
      field('Contact person', h('input', { name: 'contact_name' })),
      field('Phone', h('input', { name: 'phone', type: 'tel' }))),
    field('Business email', h('input', { name: 'email', type: 'email' })),
    h('h2', {}, 'Owner login'),
    h('div', { class: 'two' },
      field("Owner's name", h('input', { name: 'owner_name' })),
      field("Owner's email", h('input', { name: 'owner_email', type: 'email', required: true }), 'Their login for the Owner app. A temporary password is made for them.')),
    h('div', { class: 'row' }, h('button', { class: 'primary', type: 'submit' }, 'Create business'), h('a', { href: '#/' }, 'Cancel')));
  return [h('a', { href: '#/', class: 'back' }, icon('back', true), 'Businesses'), h('h1', {}, 'New business'), form, out].map(wrapGap);
}

function created(r, data) {
  return h('div', { class: 'card' },
    h('h2', {}, `${data.name} is ready`),
    h('div', { class: 'notice warn' }, 'Note the temporary password and the activation code now: they are not shown again.'),
    h('label', {}, 'Reference key (phone apps and Tally PC)'), copyable(r.reference_key, 'Reference key'),
    qrImage(r.reference_key),
    h('label', {}, 'Tally PC activation code (single use, valid 48 hours)'), copyable(r.activation_code, 'Activation code'),
    h('label', {}, 'Owner login'), copyable(r.owner_email, 'Email'),
    h('label', {}, 'Temporary password (they must change it at first sign-in)'), copyable(r.owner_password, 'Password'),
    h('p', { class: 'muted' }, 'Paid until ', date(r.paid_until), '.'),
    h('div', { class: 'row' },
      h('button', { type: 'button', onclick: () => navigator.clipboard.writeText(handover(r, data)).then(() => toast('Message copied')) }, 'Copy message for the owner'),
      h('a', { href: '#/b/' + r.id }, h('button', { class: 'primary', type: 'button' }, 'Open business'))));
}

function handover(r, data) {
  return `WholeFlow for ${data.name}

1. Install the WholeFlow Owner app.
2. Connect with reference key: ${r.reference_key}
3. Sign in: ${r.owner_email}
   Temporary password: ${r.owner_password} (you will be asked to change it)

Tally PC: install WholeFlow, open Cloud Sync and enter
the reference key above and activation code ${r.activation_code} (valid 48 hours).`;
}

// ------------------------------------------------------------ one business

async function pageBusiness(id) {
  const [d, ps, companies] = await Promise.all([api('GET', '/businesses/' + id), plans(),
    api('GET', `/businesses/${id}/companies`).catch(() => null)]);
  const b = d.business;
  const plan = ps.find(p => p.code === b.plan_code) || { price_month: 0 };
  const reload = () => render();
  const days = daysUntil(b.paid_until);

  // Subscription and payment.
  const months = h('input', { name: 'months', type: 'number', min: 1, max: 36, value: 1, required: true });
  const amount = h('input', { name: 'amount', type: 'number', min: 1, step: '0.01', value: plan.price_month, required: true });
  months.addEventListener('input', () => (amount.value = (Number(months.value) || 0) * plan.price_month));
  const payForm = h('form', { onsubmit: async ev => {
    ev.preventDefault();
    await run(payForm.querySelector('button'), async () => {
      const r = await api('POST', `/businesses/${id}/payments`, formData(payForm));
      toast('Payment recorded. Paid until ' + date(r.paid_until));
      reload();
    });
  } },
    h('div', { class: 'two' }, field('Months', months), field('Amount (₹)', amount)),
    h('div', { class: 'two' },
      field('Mode', h('select', { name: 'mode' }, ...[['upi', 'UPI'], ['cash', 'Cash'], ['bank', 'Bank transfer'], ['other', 'Other']].map(([v, t]) => h('option', { value: v }, t)))),
      field('Paid on', h('input', { name: 'paid_on', type: 'date', value: today(), max: today() }))),
    field('Reference', h('input', { name: 'reference', placeholder: 'UPI ref / cheque no.' })),
    field('Note', h('input', { name: 'note' })),
    h('button', { class: 'primary', type: 'submit' }, icon('pay', true), 'Record payment'));

  const subForm = h('form', { onsubmit: async ev => {
    ev.preventDefault();
    await run(subForm.querySelector('button'), async () => {
      await api('PATCH', '/businesses/' + id, formData(subForm));
      toast('Saved');
      reload();
    });
  } },
    field('Plan', h('select', { name: 'plan_code' }, ...ps.filter(p => p.active || p.code === b.plan_code).map(p =>
      h('option', { value: p.code, selected: p.code === b.plan_code }, `${p.name} — ${rupees(p.price_month)}/month, ${p.max_companies} companies`)))),
    h('div', { class: 'two' },
      field('Grace days', h('input', { name: 'grace_days', type: 'number', min: 0, max: 60, value: b.grace_days }), 'Apps keep working this long after the paid date.'),
      field('Reminder days', h('input', { name: 'remind_days', type: 'number', min: 0, max: 60, value: b.remind_days }), 'Owners see “renew soon” this long before.')),
    h('button', { type: 'submit' }, 'Save'));

  // Details.
  const infoForm = h('form', { onsubmit: async ev => {
    ev.preventDefault();
    await run(infoForm.querySelector('button'), async () => {
      await api('PATCH', '/businesses/' + id, formData(infoForm));
      toast('Saved');
      reload();
    });
  } },
    field('Business name', h('input', { name: 'name', value: b.name, required: true })),
    h('div', { class: 'two' },
      field('Contact person', h('input', { name: 'contact_name', value: b.contact_name || '' })),
      field('Phone', h('input', { name: 'phone', type: 'tel', value: b.phone || '' }))),
    field('Email', h('input', { name: 'email', type: 'email', value: b.email || '' })),
    h('button', { type: 'submit' }, 'Save'));

  // Keys and PCs.
  const codeOut = h('div');
  const keys = h('div', {},
    h('label', {}, 'Reference key'),
    b.reference_key ? copyable(b.reference_key, 'Reference key') : h('p', { class: 'muted' }, 'None'),
    b.reference_key ? h('details', {}, h('summary', {}, 'QR code for the phone apps'), qrImage(b.reference_key)) : null,
    h('div', { class: 'row' },
      h('button', { onclick: ev => run(ev.currentTarget, async () => {
        const r = await api('POST', `/businesses/${id}/activation-codes`, {});
        codeOut.replaceChildren(h('label', {}, 'Activation code (single use, valid 48 hours — not shown again)'), copyable(r.activation_code, 'Activation code'));
      }) }, icon('pc', true), 'Add a Tally PC'),
      h('button', { onclick: ev => {
        if (!confirm('Make a new reference key? Phones already connected keep working; new phones and PCs need the new key.')) return;
        run(ev.currentTarget, async () => { await api('POST', `/businesses/${id}/reference-key`, {}); toast('New reference key made'); reload(); });
      } }, icon('key', true), 'New reference key')),
    codeOut);

  const pcs = d.devices.length ? h('div', { class: 'scroll' }, h('table', {},
    h('thead', {}, h('tr', {}, ...['PC', 'App', 'Activated', 'Last seen', ''].map(t => h('th', {}, t)))),
    h('tbody', {}, ...d.devices.map(pc => h('tr', {},
      h('td', {}, pc.machine || 'PC', h('div', { class: 'muted small' }, pc.windows_user || '')),
      h('td', {}, pc.app_version || '—'),
      h('td', {}, date(pc.activated_at)),
      h('td', {}, when(pc.last_seen_at)),
      h('td', {}, pc.revoked_at ? badge('revoked', 'Revoked') : h('button', { class: 'danger', onclick: ev => {
        if (!confirm(`Revoke ${pc.machine || 'this PC'}? It stops syncing at once. Other PCs keep working.`)) return;
        run(ev.currentTarget, async () => { await api('POST', `/devices/${pc.id}/revoke`, {}); toast('PC revoked'); reload(); });
      } }, 'Revoke'))))))) : h('p', { class: 'muted' }, 'No PC activated yet.');

  // Status.
  const setStatus = (status, msg, btn) => {
    if (msg && !msg()) return;
    run(btn, async () => { await api('POST', `/businesses/${id}/status`, { status }); toast('Status: ' + status); reload(); });
  };
  const statusCard = h('div', { class: 'card' },
    h('h2', {}, 'Access'),
    b.status === 'active'
      ? h('div', { class: 'row' },
        h('button', { class: 'danger', onclick: ev => setStatus('suspended', () => confirm(`Suspend ${b.name}? The owner, staff and Tally PCs are blocked until you resume.`), ev.currentTarget) }, 'Suspend'),
        h('button', { class: 'danger', onclick: ev => setStatus('closed', () => confirmTyped(`Close ${b.name}? It is blocked and its reference key stops working. Its data stays until you delete it on the server.`, b.slug), ev.currentTarget) }, 'Close'))
      : h('div', { class: 'row' },
        h('span', {}, 'This business is ', stateBadge(b), '.'),
        h('button', { class: 'primary', onclick: ev => setStatus('active', () => confirm(`Resume ${b.name}?`), ev.currentTarget) }, 'Resume')),
    h('p', { class: 'hint' }, 'Unpaid businesses block themselves after the grace period; you only need Suspend for other reasons.'));

  const backupBtn = h('button', { onclick: ev => run(ev.currentTarget, () => download(`/businesses/${id}/backup`)) }, icon('download', true), 'Download backup');

  const payments = d.payments.length ? h('div', { class: 'scroll' }, h('table', {},
    h('thead', {}, h('tr', {}, ...['Paid on', 'Amount', 'Mode', 'Period', 'Reference', 'By'].map(t => h('th', {}, t)))),
    h('tbody', {}, ...d.payments.map(p => h('tr', {},
      h('td', {}, date(p.paid_on)),
      h('td', {}, rupees(p.amount), h('div', { class: 'muted small' }, `${p.months} month${p.months > 1 ? 's' : ''}`)),
      h('td', {}, p.mode.toUpperCase()),
      h('td', {}, date(p.period_from), ' – ', date(p.period_to)),
      h('td', {}, p.reference || '', p.note ? h('div', { class: 'muted small' }, p.note) : null),
      h('td', {}, p.recorded_by || '—')))))) : h('p', { class: 'muted' }, 'No payments yet.');

  const history = d.events.length ? h('div', { class: 'scroll' }, h('table', {},
    h('tbody', {}, ...d.events.map(e => h('tr', {},
      h('td', { class: 'small' }, when(e.at)),
      h('td', {}, eventText(e)),
      h('td', { class: 'muted small' }, e.admin || 'system')))))) : h('p', { class: 'muted' }, 'Nothing yet.');

  return [
    h('div', {}, h('a', { href: '#/', class: 'back' }, icon('back', true), 'Businesses')),
    h('div', { class: 'row spread' },
      h('div', {}, h('h1', {}, b.name, ' ', stateBadge(b)), h('div', { class: 'muted mono small' }, b.slug, ' · ', b.base_url)),
      backupBtn),
    h('div', { class: 'card' }, h('div', { class: 'stats' },
      h('div', { class: 'stat' }, h('div', { class: 'n' }, date(b.paid_until)), h('div', { class: 'l' }, 'Paid until', days >= 0 ? ` (in ${days} days)` : ` (${-days} days ago)`)),
      h('div', { class: 'stat' }, h('div', { class: 'n' }, b.plan_name), h('div', { class: 'l' }, rupees(plan.price_month) + ' / month')),
      h('div', { class: 'stat' }, h('div', { class: 'n' }, b.devices), h('div', { class: 'l' }, 'Active PCs')),
      h('div', { class: 'stat' }, h('div', { class: 'n' }, when(b.last_seen_at)), h('div', { class: 'l' }, 'Last sync')))),
    h('div', { class: 'grid' },
      h('div', { class: 'card' }, h('h2', {}, 'Record a payment'), payForm),
      h('div', { class: 'stack' },
        h('div', { class: 'card' }, h('h2', {}, 'Subscription'), subForm),
        statusCard)),
    h('div', { class: 'card' }, h('h2', {}, 'Payments'), payments),
    h('div', { class: 'grid' },
      h('div', { class: 'card' }, h('h2', {}, 'Keys'), keys),
      h('div', { class: 'card' }, h('h2', {}, 'Details'), infoForm)),
    h('div', { class: 'card' }, h('h2', {}, 'Tally PCs'), pcs),
    companiesCard(b, plan, companies),
    h('div', { class: 'card' }, h('h2', {}, 'History'), history),
    dangerZone(b),
  ].map(wrapGap);
}

// ------------------------------------------------------------ deleting data

// Tally companies stored in the business database, each deletable.
function companiesCard(b, plan, companies) {
  const card = h('div', { class: 'card' }, h('h2', {}, 'Tally companies'));
  if (!companies) return (card.append(h('p', { class: 'muted' }, 'Could not read the companies of this business.')), card);
  if (!companies.length) return (card.append(h('p', { class: 'muted' }, 'No company synced yet.')), card);
  if (plan.max_companies && companies.length > plan.max_companies) {
    card.append(h('div', { class: 'notice warn' },
      `${companies.length} companies are stored but the ${b.plan_name} plan allows ${plan.max_companies}. ` +
      'Delete the ones the business no longer pays for (untick them on the Tally PC first).'));
  }
  card.append(h('div', { class: 'scroll' }, h('table', {},
    h('thead', {}, h('tr', {}, ...['Company', 'Last sync', 'Shops', 'Transactions', ''].map(t => h('th', {}, t)))),
    h('tbody', {}, ...companies.map(c => h('tr', {},
      h('td', {}, c.name, h('div', { class: 'muted small' }, c.sync_status)),
      h('td', {}, when(c.last_sync_at)),
      h('td', {}, c.shops.toLocaleString('en-IN')),
      h('td', {}, c.transactions.toLocaleString('en-IN')),
      h('td', {}, h('button', { class: 'danger', onclick: () => dangerDialog({
        title: `Delete ${c.name}?`,
        lines: [
          `Everything stored for this company in ${b.name} is deleted permanently: ` +
          `${c.shops.toLocaleString('en-IN')} shops, ${c.transactions.toLocaleString('en-IN')} transactions, suppliers, purchases, stock, sites, visits and staff access to it.`,
          'If the Tally PC still has this company ticked, the next sync uploads it again. Untick it on the PC first.',
        ],
        expected: c.name, expectedLabel: 'company name',
        action: 'Delete company',
        run: body => api('POST', `/businesses/${b.id}/companies/${c.id}/delete`, body),
        done: () => { toast(`${c.name} deleted`); render(); },
      }) }, icon('delete', true), 'Delete'))))))));
  return card;
}

function dangerZone(b) {
  return h('div', { class: 'card danger-zone' },
    h('h2', {}, 'Danger zone'),
    h('p', {}, 'Delete this business and all its data: database, logins, keys, Tally PCs, payments. This cannot be undone.'),
    h('p', { class: 'hint' }, 'Tip: use “Download backup” first if the customer may want their data.'),
    h('button', { class: 'danger filled', onclick: () => dangerDialog({
      title: `Delete ${b.name} completely?`,
      lines: [
        `The business database (biz_${b.slug}) with every company, shop, transaction, staff account, site and visit is dropped.`,
        'Its login and data API are removed, the reference key and every Tally PC stop working, and its subscription and payment records are deleted.',
        'The admin history keeps one line saying it was deleted.',
      ],
      expected: b.slug, expectedLabel: 'short name',
      extra: { name: 'delete_backups', label: 'Also delete its nightly backup files on the server (otherwise they are removed after 14 days)', checked: true },
      action: 'Delete business',
      run: body => api('POST', `/businesses/${b.id}/delete`, body),
      done: () => { toast(`${b.name} deleted`); plansCache = null; location.hash = '#/'; },
    }) }, icon('delete', true), 'Delete business'));
}

// dangerDialog asks to type the exact name and the admin's own password, then
// asks once more; the server checks both again.
function dangerDialog({ title, lines, expected, expectedLabel, extra, action, run, done }) {
  const typed = h('input', { autocomplete: 'off', spellcheck: 'false', placeholder: expected });
  const pw = h('input', { type: 'password', autocomplete: 'current-password' });
  const box = extra ? h('input', { type: 'checkbox', checked: extra.checked }) : null;
  if (box) box.checked = !!extra.checked;
  const err = h('div', { class: 'notice bad', hidden: true });
  const go = h('button', { class: 'danger filled', disabled: true }, icon('delete', true), action);
  const norm = v => v.trim().replace(/\s+/g, ' ').toLowerCase();
  const update = () => (go.disabled = norm(typed.value) !== norm(expected) || !pw.value);
  typed.addEventListener('input', update);
  pw.addEventListener('input', update);
  const close = () => { scrim.remove(); document.removeEventListener('keydown', onKey); };
  const onKey = ev => { if (ev.key === 'Escape') close(); };
  go.addEventListener('click', async () => {
    if (!confirm(`Last check: ${action.toLowerCase()} “${expected}”? This cannot be undone.`)) return;
    err.hidden = true;
    go.disabled = true;
    go.lastChild.textContent = 'Deleting…';
    try {
      const body = { confirm: typed.value, password: pw.value };
      if (box) body[extra.name] = box.checked;
      await run(body);
      close();
      done();
    } catch (e) {
      if (e.status === 401) return close(); // signed out: the page shows the login
      err.textContent = e.message;
      err.hidden = false;
      go.lastChild.textContent = action;
      pw.value = '';
      update();
      pw.focus();
    }
  });
  const scrim = h('div', { class: 'scrim', onclick: ev => { if (ev.target === scrim) close(); } },
    h('div', { class: 'dialog', role: 'alertdialog', 'aria-modal': 'true', 'aria-label': title },
      h('div', { class: 'dialog-icon' }, icon('warning')),
      h('h2', {}, title),
      ...lines.map(t => h('p', {}, t)),
      err,
      field(`Type the ${expectedLabel} “${expected}” to confirm`, typed),
      field('Your admin password', pw),
      box ? h('label', { class: 'check' }, box, h('span', {}, extra.label)) : null,
      h('div', { class: 'dialog-actions' }, h('button', { class: 'link', onclick: close }, 'Cancel'), go)));
  document.body.append(scrim);
  document.addEventListener('keydown', onKey);
  typed.focus();
}

function eventText(e) {
  const x = e.details || {};
  switch (e.action) {
    case 'business.create': return 'Business created';
    case 'business.update': return 'Details changed';
    case 'business.status': return 'Status → ' + x.status;
    case 'business.backup': return 'Backup downloaded';
    case 'company.delete': return `Company deleted: ${x.company} (${x.shops} shops, ${x.transactions} transactions)`;
    case 'payment.record': return `Payment ${x.amount != null ? rupees(x.amount) : ''} recorded${x.paid_until ? ' — paid until ' + date(x.paid_until) : ''}`;
    case 'subscription.update': return `Subscription: plan ${x.plan}, grace ${x.grace_days} d, reminder ${x.remind_days} d`;
    case 'activation_code.create': return 'PC activation code made';
    case 'reference_key.rotate': return 'New reference key';
    case 'device.activate': return `PC activated${x.machine ? ': ' + x.machine : ''}`;
    case 'device.revoke': return 'PC revoked';
    default: return e.action;
  }
}

async function download(path) {
  const res = await fetch('/control/admin' + path, { headers: { Authorization: 'Bearer ' + sessionStorage.getItem(TOKEN) } });
  if (!res.ok) {
    const data = await res.json().catch(() => null);
    throw new ApiError(res.status, 'ERROR', (data && data.error && data.error.message) || 'Download failed.');
  }
  const name = (/filename="([^"]+)"/.exec(res.headers.get('Content-Disposition') || '') || [])[1] || 'backup.dump';
  const url = URL.createObjectURL(await res.blob());
  const a = h('a', { href: url, download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
  toast('Backup downloaded');
}

// ------------------------------------------------------------ plans

async function pagePlans() {
  plansCache = null;
  const ps = await plans();
  const rowFor = p => {
    const isNew = !p;
    p = p || { code: '', name: '', max_companies: 1, price_month: 500, active: true };
    const code = h('input', { value: p.code, disabled: !isNew, pattern: '[a-z0-9]{2,20}', placeholder: 'code', required: true });
    const name = h('input', { value: p.name, required: true });
    const max = h('input', { type: 'number', min: 1, max: 100, value: p.max_companies, required: true });
    const price = h('input', { type: 'number', min: 0, step: '0.01', value: p.price_month, required: true });
    const active = h('input', { type: 'checkbox', checked: p.active });
    active.checked = p.active;
    const save = h('button', { type: 'button', onclick: ev => run(ev.currentTarget, async () => {
      await api('PUT', '/plans/' + encodeURIComponent(code.value.trim()), { name: name.value, max_companies: Number(max.value), price_month: Number(price.value), active: active.checked });
      plansCache = null;
      toast('Plan saved. Businesses on it see the change.');
      render();
    }) }, isNew ? 'Add' : 'Save');
    return h('tr', {}, h('td', {}, code), h('td', {}, name), h('td', {}, max), h('td', {}, price), h('td', {}, active), h('td', {}, save));
  };
  return [
    h('h1', {}, 'Plans'),
    h('div', { class: 'card' },
      h('p', { class: 'hint' }, 'Price and company limit apply to every business on the plan. Inactive plans cannot be chosen for new businesses.'),
      h('div', { class: 'scroll' }, h('table', {},
        h('thead', {}, h('tr', {}, ...['Code', 'Name', 'Max companies', '₹ / month', 'Active', ''].map(t => h('th', {}, t)))),
        h('tbody', {}, ...ps.map(rowFor), rowFor(null))))),
  ].map(wrapGap);
}

// ------------------------------------------------------------ settings

// ------------------------------------------------------------ enquiries (website contact form)

const LEAD_STATES = [['new', 'New'], ['contacted', 'Contacted'], ['won', 'Became a customer'], ['lost', 'Not interested']];

// Rail item with the number of new enquiries (filled in after the page draws).
function leadsItem(on) {
  const badge = h('span', { class: 'rail-badge', hidden: true });
  const a = h('a', { href: '#/leads', class: 'rail-item' + (on ? ' on' : ''), 'aria-current': on ? 'page' : null },
    h('span', { class: 'ind' }, icon('inbox'), badge), 'Enquiries');
  api('GET', '/leads').then(list => {
    const n = list.filter(l => l.status === 'new').length;
    if (n) { badge.textContent = n > 99 ? '99+' : n; badge.hidden = false; a.title = `${n} new enquir${n === 1 ? 'y' : 'ies'}`; }
  }).catch(() => {});
  return a;
}

const LEAD_COMPANIES = { '1': '1 company', '2-3': '2–3 companies', '4-5': '4–5 companies', '6+': '6 or more' };

async function pageLeads() {
  const list = await api('GET', '/leads');
  let filter = 'open';
  const body = h('div');
  const counts = h('div', { class: 'stats stats-plain' });
  const fill = () => {
    const shown = list.filter(l => filter === 'all' || (filter === 'open' ? (l.status === 'new' || l.status === 'contacted') : l.status === filter));
    const n = s => list.filter(l => l.status === s).length;
    counts.replaceChildren(
      ...[['new', 'New'], ['contacted', 'Contacted'], ['won', 'Became customers'], ['lost', 'Not interested']].map(([k, label]) =>
        h('div', { class: 'card stat' + (k === 'new' && n('new') ? ' stat-hot' : '') }, h('div', { class: 'n' }, n(k)), h('div', { class: 'l' }, label))));
    body.replaceChildren(...(shown.length ? shown.map(leadCard) : [h('div', { class: 'card' }, h('p', { class: 'muted' }, list.length ? 'Nothing in this view.' : 'No enquiries yet. They arrive here from the contact form on wholeflow.jitsuji.xyz.'))]));
  };
  const leadCard = l => {
    const wa = '91' + l.phone;
    const status = h('select', { 'aria-label': 'Status', onchange: () => save({ status: status.value }) },
      ...LEAD_STATES.map(([v, t]) => h('option', { value: v, selected: l.status === v }, t)));
    status.value = l.status;
    const note = h('textarea', { rows: 2, placeholder: 'Your notes (only you see these)', value: l.note });
    const saveNote = h('button', { class: 'text', type: 'button', onclick: ev => run(ev.currentTarget, () => save({ note: note.value })) }, 'Save note');
    const save = async patch => {
      await api('PATCH', '/leads/' + l.id, patch);
      Object.assign(l, patch);
      toast('Saved');
      fill();
    };
    return h('article', { class: 'card lead' + (l.status === 'new' ? ' lead-new' : '') },
      h('div', { class: 'lead-head' },
        h('div', {},
          h('h2', {}, l.name, l.business ? h('span', { class: 'muted' }, ' · ' + l.business) : null),
          h('div', { class: 'muted small' }, when(l.created_at), l.city ? ' · ' + l.city : '', l.companies ? ' · ' + (LEAD_COMPANIES[l.companies] || l.companies) : '')),
        status),
      l.message ? h('p', { class: 'lead-msg' }, l.message) : null,
      h('div', { class: 'row lead-actions' },
        h('a', { class: 'chip', href: 'tel:+' + wa }, icon('call', true), '+91 ' + l.phone.slice(0, 5) + ' ' + l.phone.slice(5)),
        h('a', { class: 'chip', href: 'https://wa.me/' + wa, target: '_blank', rel: 'noopener' }, icon('chat', true), 'WhatsApp'),
        h('a', { class: 'chip', href: 'mailto:' + l.email }, icon('mail', true), l.email)),
      h('div', { class: 'lead-note' }, note, saveNote, h('button', { class: 'text danger-text', type: 'button', onclick: ev => {
        if (!confirm(`Delete the enquiry from ${l.name}?`)) return;
        run(ev.currentTarget, async () => { await api('DELETE', '/leads/' + l.id); list.splice(list.indexOf(l), 1); toast('Deleted'); fill(); });
      } }, 'Delete')));
  };
  const tabs = h('div', { class: 'seg' }, ...[['open', 'Open'], ['won', 'Customers'], ['lost', 'Not interested'], ['all', 'All']].map(([k, t]) =>
    h('button', { type: 'button', class: k === filter ? 'on' : '', onclick: ev => { filter = k; tabs.querySelectorAll('button').forEach(b => b.classList.toggle('on', b === ev.currentTarget)); fill(); } }, t)));
  fill();
  return [
    h('h1', {}, 'Enquiries'),
    h('p', { class: 'muted' }, 'From the contact form on wholeflow.jitsuji.xyz. Everything here was typed by the visitor.'),
    counts, tabs, body,
  ].map(wrapGap);
}

async function pageSettings() {
  const [s, admins] = await Promise.all([api('GET', '/settings'), api('GET', '/admins')]);

  const msgForm = h('form', { onsubmit: async ev => {
    ev.preventDefault();
    await run(msgForm.querySelector('button'), async () => { await api('PUT', '/settings', formData(msgForm)); toast('Saved. Every business shows the new text.'); });
  } },
    field('Renewal message', h('textarea', { name: 'renew_message', value: s.renew_message }), 'Shown to owners when renewal is due or the app is blocked. {plan} and {price} are filled in.'),
    field('Contact', h('input', { name: 'contact', value: s.contact }), 'Phone or WhatsApp number shown with the message.'),
    h('button', { type: 'submit' }, 'Save'));

  const migOut = h('div');
  const migrate = h('button', { onclick: ev => {
    if (!confirm('Apply new database updates to every business now?')) return;
    run(ev.currentTarget, async () => {
      migOut.replaceChildren(h('p', { class: 'muted' }, 'Running…'));
      const r = await api('POST', '/migrate-all', {});
      migOut.replaceChildren(h('div', { class: 'notice ' + (r.ok ? 'ok' : 'bad') }, r.ok ? 'All businesses are up to date.' : 'Some updates failed — see the output.'), h('pre', { class: 'out' }, r.output || ''));
    });
  } }, 'Update all businesses');

  const adminRows = admins.map(a => h('tr', {},
    h('td', {}, a.name || '—', h('div', { class: 'muted small' }, a.email)),
    h('td', {}, when(a.last_login_at)),
    h('td', {}, a.disabled ? badge('suspended', 'Disabled') : badge('active', 'Active')),
    h('td', {}, a.id === me.id ? h('span', { class: 'muted small' }, 'you') : h('button', { onclick: ev => run(ev.currentTarget, async () => {
      await api('POST', `/admins/${a.id}/disabled`, { disabled: !a.disabled });
      render();
    }) }, a.disabled ? 'Enable' : 'Disable'))));

  const addForm = h('form', { onsubmit: async ev => {
    ev.preventDefault();
    await run(addForm.querySelector('button'), async () => { await api('POST', '/admins', formData(addForm)); toast('Admin saved'); render(); });
  } },
    h('div', { class: 'two' }, field('Name', h('input', { name: 'name' })), field('Email', h('input', { name: 'email', type: 'email', required: true }))),
    field('Password', h('input', { name: 'password', type: 'password', minlength: 10, autocomplete: 'new-password', required: true }), 'At least 10 characters. Also used to sign in on customers’ Tally PCs.'),
    h('button', { type: 'submit' }, 'Add admin'));

  const pwForm = h('form', { onsubmit: async ev => {
    ev.preventDefault();
    const v = formData(pwForm);
    if (v.new !== v.again) return toast('The new passwords do not match.', true);
    await run(pwForm.querySelector('button'), async () => { await api('POST', '/password', { current: v.current, new: v.new }); pwForm.reset(); toast('Password changed'); });
  } },
    field('Current password', h('input', { name: 'current', type: 'password', autocomplete: 'current-password', required: true })),
    h('div', { class: 'two' },
      field('New password', h('input', { name: 'new', type: 'password', minlength: 10, autocomplete: 'new-password', required: true })),
      field('Again', h('input', { name: 'again', type: 'password', minlength: 10, autocomplete: 'new-password', required: true }))),
    h('button', { type: 'submit' }, 'Change password'));

  return [
    h('h1', {}, 'Settings'),
    h('div', { class: 'grid' },
      h('div', { class: 'card' }, h('h2', {}, 'Message to owners'), msgForm),
      h('div', { class: 'card' }, h('h2', {}, 'Database updates'),
        h('p', { class: 'hint' }, 'After installing a new WholeFlow version on the server, apply its database changes to every business.'),
        migrate, migOut)),
    h('div', { class: 'card' }, h('h2', {}, 'Admins'),
      h('div', { class: 'scroll' }, h('table', {}, h('tbody', {}, ...adminRows))),
      h('h2', { class: 'gap' }, 'Add an admin'), addForm),
    h('div', { class: 'card' }, h('h2', {}, 'My password'), pwForm),
  ].map(wrapGap);
}
