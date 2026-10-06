// Frontend for the Tally shop/outstanding app. Talks only to the JSON API.
"use strict";

const $ = (sel, root = document) => root.querySelector(sel);
const view = $("#view");
const state = { company: null, companies: [], fetchedAt: null };

// ------------------------------------------------------------ helpers

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const inr = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2, minimumFractionDigits: 0 });
const money = (n) => inr.format(n || 0);
const drcr = (t) => (t === "DR" ? "Dr" : t === "CR" ? "Cr" : "");
const bal = (b) => (b && b.amount ? `${money(b.amount)} <span class="tag ${b.type.toLowerCase()}">${drcr(b.type)}</span>` : `<span class="muted">${money(0)}</span>`);
const fmtDate = (iso) => (iso ? new Date(iso + "T00:00:00").toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" }) : "");
const fmtTime = (t) => (t ? new Date(t).toLocaleString("en-IN", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", second: "2-digit" }) : "");
const debounce = (fn, ms = 250) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

class ApiError extends Error {
  constructor(status, body) {
    super(body?.error?.message || `HTTP ${status}`);
    this.status = status; this.code = body?.error?.code; this.details = body?.error?.details;
  }
}

async function api(path, params = {}, opts = {}) {
  const url = new URL(path, location.origin);
  if (state.company && !params.noCompany) url.searchParams.set("company", state.company);
  for (const [k, v] of Object.entries(params)) if (k !== "noCompany" && v !== "" && v != null) url.searchParams.set(k, v);
  opts.headers = Object.assign({ "X-Requested-With": "WholeFlowSync" }, opts.headers || {});
  let res;
  try {
    res = await fetch(url, opts);
  } catch (e) {
    throw new ApiError(0, { error: { code: "APP_UNREACHABLE", message: "The application server is not responding. Is it still running?" } });
  }
  const body = await res.json().catch(() => null);
  if (res.status === 401) { showLogin(body?.error?.message); throw new ApiError(401, body); }
  if (!res.ok) throw new ApiError(res.status, body);
  if (body && body.fetchedAt) setAsOf(body.fetchedAt);
  return body;
}

function exportUrl(report, format, params) {
  const url = new URL(`/api/export/${report}`, location.origin);
  url.searchParams.set("format", format);
  if (state.company) url.searchParams.set("company", state.company);
  for (const [k, v] of Object.entries(params)) if (v) url.searchParams.set(k, v);
  return url.pathname + url.search;
}

function errorBox(err) {
  const hint = err.code === "NO_COMPANY_SELECTED" || err.code === "COMPANY_NOT_FOUND"
    ? ` <a href="#/status">Choose a company</a>.` : err.code === "TALLY_UNREACHABLE" ? ` <a href="#/status">See connection help</a>.` : "";
  return `<div class="alert error"><strong>${esc(err.message)}</strong>${hint}
    ${err.details ? `<div class="details">${esc(err.details)}</div>` : ""}</div>`;
}

function setAsOf(t) {
  state.fetchedAt = t;
  $("#asof").textContent = t ? `Data from Tally as of ${fmtTime(t)}${state.company ? " · " + state.company : ""}` : "";
}

// ------------------------------------------------------------ connection & company

async function loadStatus() {
  const pill = $("#conn");
  try {
    const st = await api("/api/tally/status", { noCompany: true });
    state.status = st;
    pill.textContent = st.connected ? `Tally connected · :${st.port}` : "Tally not connected";
    pill.className = "pill " + (st.connected ? "ok" : "bad");
    state.companies = st.companies || [];
    const saved = localStorage.getItem("company");
    const names = state.companies.map((c) => c.name);
    if (saved && names.includes(saved)) state.company = saved;
    else if (names.length === 1) state.company = names[0];
    else if (!names.includes(state.company)) state.company = null;
    renderCompanySelect();
    return st;
  } catch (e) {
    pill.textContent = "App offline"; pill.className = "pill bad";
    return null;
  }
}

function renderCompanySelect() {
  const sel = $("#company");
  sel.hidden = state.companies.length < 2;
  sel.innerHTML = `<option value="">Select company…</option>` +
    state.companies.map((c) => `<option value="${esc(c.name)}" ${c.name === state.company ? "selected" : ""}>${esc(c.name)}</option>`).join("");
}

function selectCompany(name) {
  state.company = name || null;
  if (name) localStorage.setItem("company", name); else localStorage.removeItem("company");
  renderCompanySelect();
  route();
}

$("#company").addEventListener("change", (e) => selectCompany(e.target.value));

$("#refresh").addEventListener("click", async () => {
  const btn = $("#refresh");
  btn.disabled = true; btn.textContent = "Refreshing…";
  try {
    await loadStatus();
    if (state.company) await api("/api/tally/refresh", {}, { method: "POST" });
    route();
  } catch (e) {
    view.insertAdjacentHTML("afterbegin", errorBox(e));
  } finally {
    btn.disabled = false; btn.textContent = "Refresh from Tally";
  }
});

function needCompany() {
  if (location.hash.startsWith("#/sync")) return false;
  if (state.company) return false;
  if (state.status && !state.status.connected) {
    view.innerHTML = errorBox({ code: "TALLY_UNREACHABLE", message: state.status.error?.message || "Unable to connect to TallyPrime.",
      details: `Tried ${state.status.endpoint} (port from ${state.status.portSource}).` });
    return true;
  }
  view.innerHTML = state.companies.length === 0
    ? `<div class="alert warn"><strong>No company available.</strong> Open a company in TallyPrime, then click <em>Refresh from Tally</em>. <a href="#/status">Tally status</a></div>`
    : `<div class="alert warn"><strong>No company selected.</strong> Several companies are open in TallyPrime — choose one on the <a href="#/status">Tally Status</a> page or from the selector above.</div>`;
  return true;
}

// ------------------------------------------------------------ dashboard

async function viewDashboard() {
  if (needCompany()) return;
  view.innerHTML = `<div class="loading">Loading from Tally…</div>`;
  let d;
  try { d = await api("/api/dashboard"); } catch (e) { view.innerHTML = errorBox(e); return; }
  const top = d.topOutstanding[0];
  const maxArea = Math.max(1, ...d.outstandingByArea.map((a) => a.outstanding));
  view.innerHTML = `
    <h1>Shop Outstanding Dashboard</h1>
    <div class="grid kpis">
      ${kpi("Total shops", d.totalShops, `${esc(d.company.name)}`)}
      ${kpi("Total outstanding", money(d.totalOutstanding), "Sum of all Dr balances", "dr")}
      ${kpi("Shops with dues", d.shopsWithDues, "Dr balance")}
      ${kpi("Shops with credit", d.shopsWithCredit, `${money(d.totalCredit)} Cr in total`, "")}
      ${kpi("Net receivable", `${money(d.netReceivable.amount)} ${drcr(d.netReceivable.type)}`, "Dues minus credits")}
      ${top ? kpi("Top outstanding", money(top.currentBalance.amount), `<a href="#/shops/${encodeURIComponent(top.id)}">${esc(top.name)}</a>`) : ""}
    </div>
    <div class="grid two">
      <section class="panel">
        <h2>Highest outstanding</h2>
        <div class="table-wrap"><table>
          <thead><tr><th>Shop</th><th>Area</th><th class="num">Balance</th></tr></thead>
          <tbody>${d.topOutstanding.map((c) => `<tr><td><a href="#/shops/${encodeURIComponent(c.id)}">${esc(c.name)}</a></td><td>${esc(c.area)}</td><td class="num">${bal(c.currentBalance)}</td></tr>`).join("") || `<tr><td colspan="3" class="empty">No outstanding dues.</td></tr>`}</tbody>
        </table></div>
        <p class="small"><a href="#/outstanding">Full outstanding report →</a></p>
      </section>
      <section class="panel">
        <h2>Outstanding by area <span class="muted small">(area taken from shop name)</span></h2>
        <table><tbody>${d.outstandingByArea.map((a) => `
          <tr><td style="width:34%"><a href="#/outstanding?q=${encodeURIComponent(a.area)}&field=area_exact">${esc(a.area)}</a> <span class="muted small">${a.shops} shop${a.shops === 1 ? "" : "s"}</span></td>
          <td><div class="bar"><span style="width:${(a.outstanding / maxArea) * 100}%"></span></div></td>
          <td class="num">${money(a.outstanding)}</td></tr>`).join("")}</tbody></table>
      </section>
    </div>`;
}

const kpi = (label, value, sub = "", cls = "") =>
  `<div class="kpi"><div class="label">${label}</div><div class="value ${cls}">${value}</div><div class="sub">${sub}</div></div>`;

// ------------------------------------------------------------ shops list

async function viewShops(params) {
  if (needCompany()) return;
  const q = { q: params.get("q") || "", field: params.get("field") || "all", type: params.get("type") || "",
              sort: params.get("sort") || "name_asc", page: +params.get("page") || 1, pageSize: +params.get("pageSize") || 25 };
  view.innerHTML = `
    <h1>Shops</h1>
    <div class="panel">
      <div class="toolbar">
        <input type="search" id="q" placeholder="Search shops…" value="${esc(q.q)}">
        <select id="field">${opts([["all", "All fields"], ["name", "Shop name"], ["phone", "Phone"], ["area", "Area / address"]], q.field)}</select>
        <select id="type">${opts([["", "All balances"], ["dr", "Dr (dues)"], ["cr", "Cr (credit)"], ["zero", "Zero balance"]], q.type)}</select>
        <select id="sort">${opts([["name_asc", "Name A→Z"], ["name_desc", "Name Z→A"], ["balance_desc", "Highest outstanding first"], ["balance_asc", "Lowest outstanding first"], ["area_asc", "Area"]], q.sort)}</select>
        <span class="spacer"></span>
        <a id="csv"><button>Export CSV</button></a>
        <a id="xlsx"><button>Export Excel</button></a>
      </div>
      <div id="results"><div class="loading">Loading from Tally…</div></div>
    </div>`;

  const load = async () => {
    const p = { q: $("#q").value.trim(), field: $("#field").value, type: $("#type").value, sort: $("#sort").value, page: q.page, pageSize: q.pageSize };
    history.replaceState(null, "", "#/shops?" + new URLSearchParams(Object.entries(p).filter(([, v]) => v)).toString());
    $("#csv").href = exportUrl("customers", "csv", p);
    $("#xlsx").href = exportUrl("customers", "xlsx", p);
    let r;
    try { r = await api("/api/customers", p); } catch (e) { $("#results").innerHTML = errorBox(e); return; }
    $("#results").innerHTML = `
      <div class="table-wrap"><table>
        <thead><tr><th>Shop</th><th>Phone</th><th>Area</th><th class="num">Balance</th><th>Type</th></tr></thead>
        <tbody>${r.items.map((c) => `<tr>
          <td><a href="#/shops/${encodeURIComponent(c.id)}">${esc(c.name)}</a></td>
          <td>${esc((c.phones || []).join(", "))}</td>
          <td>${esc(c.area)}</td>
          <td class="num ${c.currentBalance.type.toLowerCase()}">${money(c.currentBalance.amount)}</td>
          <td>${c.currentBalance.type ? `<span class="tag ${c.currentBalance.type.toLowerCase()}">${drcr(c.currentBalance.type)}</span>` : ""}</td>
        </tr>`).join("") || `<tr><td colspan="5" class="empty">No shops match.</td></tr>`}</tbody>
      </table></div>
      <div class="pager">
        <span class="muted">${r.total} shop${r.total === 1 ? "" : "s"} · page ${r.total ? r.page : 0} of ${r.pages}</span>
        <select id="pageSize">${opts([[25, "25 / page"], [50, "50 / page"], [100, "100 / page"], [500, "500 / page"]], String(r.pageSize))}</select>
        <button id="prev" ${r.page <= 1 ? "disabled" : ""}>‹ Prev</button>
        <button id="next" ${r.page >= r.pages ? "disabled" : ""}>Next ›</button>
      </div>`;
    $("#prev").onclick = () => { q.page--; load(); };
    $("#next").onclick = () => { q.page++; load(); };
    $("#pageSize").onchange = (e) => { q.pageSize = +e.target.value; q.page = 1; load(); };
  };
  const reset = () => { q.page = 1; load(); };
  $("#q").addEventListener("input", debounce(reset));
  for (const id of ["field", "type", "sort"]) $("#" + id).addEventListener("change", reset);
  load();
}

const opts = (list, cur) => list.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(cur) ? "selected" : ""}>${esc(l)}</option>`).join("");

// ------------------------------------------------------------ shop detail

const CATEGORY_LABEL = { sales: "Total Sales", receipts: "Total Receipts", returns: "Total Returns (Credit Notes)", adjustments: "Total Adjustments (Journal / Debit Note / other)" };

async function viewShop(id) {
  if (needCompany()) return;
  view.innerHTML = `<div class="loading">Loading from Tally…</div>`;
  let r;
  try { r = await api(`/api/customers/${encodeURIComponent(id)}`); } catch (e) { view.innerHTML = `<p><a href="#/shops">← Shops</a></p>` + errorBox(e); return; }
  const c = r.customer;
  const row = (k, v) => (v ? `<dt>${k}</dt><dd>${v}</dd>` : "");
  view.innerHTML = `
    <p><a href="javascript:history.back()">← Back</a></p>
    <h1>${esc(c.name)}</h1>
    ${c.parseWarnings ? `<div class="alert warn">Some values from Tally could not be read: ${esc(c.parseWarnings.join("; "))}</div>` : ""}
    <div class="grid two">
      <section class="panel"><h2>Contact</h2><dl class="kv">
        ${row("Phone", esc((c.phones || []).join(", ")) + (c.phoneSource === "address" ? ` <span class="muted small">(found in address)</span>` : ""))}
        ${row("Contact person", esc(c.contactPerson))}
        ${row("Email", esc(c.email))}
        ${row("Address", (c.address || []).map(esc).join("<br>"))}
        ${row("Area", c.area ? esc(c.area) + ` <span class="muted small">(from shop name)</span>` : "")}
        ${row("State", esc(c.state))}
        ${row("Pincode", esc(c.pincode))}
        ${row("GSTIN", esc(c.gstin))}
        ${row("GST registration", esc(c.gstRegistrationType))}
        ${row("Alias", esc((c.aliases || []).join(", ")))}
        ${row("Tally group", esc(c.group))}
      </dl></section>
      <section class="panel"><h2>Account summary <span class="muted small">live from Tally · ${fmtTime(r.fetchedAt)}</span></h2><dl class="kv">
        <dt>Opening balance</dt><dd>${bal(c.openingBalance)}</dd>
        <dt>Current balance</dt><dd style="font-size:18px;font-weight:650">${bal(c.currentBalance)}</dd>
        <dt>Balance type</dt><dd>${c.currentBalance.type === "DR" ? "Dr — amount receivable from the shop" : c.currentBalance.type === "CR" ? "Cr — credit balance (advance / payable to the shop)" : "Settled (zero balance)"}</dd>
      </dl></section>
    </div>
    <section class="panel" id="txn"><h2>Transaction summary</h2><div class="loading">Reading vouchers from Tally…</div></section>`;

  let t;
  try { t = await api(`/api/customers/${encodeURIComponent(id)}/transactions`); } catch (e) { $("#txn").innerHTML = `<h2>Transaction summary</h2>` + errorBox(e); return; }
  const ex = t.excluded, exN = ex.optional + ex.cancelled + ex.postDated;
  $("#txn").innerHTML = `
    <h2>Transaction summary <span class="muted small">${fmtDate(t.from)} – ${fmtDate(t.to)}</span></h2>
    ${t.reconciled
      ? `<div class="alert ok small">Checked: opening balance + these transactions = Tally's current balance (${bal(t.tallyClosing)}).</div>`
      : `<div class="alert warn small">These transactions do not add up to Tally's balance: opening ${bal(t.opening)} + movement ${bal(t.movement)} = ${bal(t.computedClosing)}, but Tally reports ${bal(t.tallyClosing)}. The <strong>current balance above is Tally's own figure</strong>; this summary may be incomplete.</div>`}
    <div class="table-wrap"><table>
      <thead><tr><th></th><th class="num">Vouchers</th><th class="num">Debit</th><th class="num">Credit</th><th class="num">Net</th></tr></thead>
      <tbody>${t.totals.map((x) => `<tr><td>${CATEGORY_LABEL[x.category]}</td><td class="num">${x.count}</td><td class="num">${money(x.debit)}</td><td class="num">${money(x.credit)}</td><td class="num">${bal(x.net)}</td></tr>`).join("")}</tbody>
    </table></div>
    ${exN ? `<p class="muted small">Not counted (as in Tally's balance): ${ex.optional} optional, ${ex.cancelled} cancelled, ${ex.postDated} post-dated voucher(s).</p>` : ""}
    <h2 style="margin-top:20px">Transactions (${t.transactions.length})</h2>
    <div class="table-wrap"><table>
      <thead><tr><th>Date</th><th>Voucher type</th><th>No.</th><th>Narration</th><th class="num">Amount</th></tr></thead>
      <tbody id="txrows"></tbody>
    </table></div>
    <div class="pager"><button id="more" hidden>Show all</button></div>`;
  const rows = t.transactions.map((x) => `<tr><td>${fmtDate(x.date)}</td><td>${esc(x.voucherType)}</td><td>${esc(x.number)}</td><td class="small">${esc(x.narration)}</td><td class="num">${bal(x.amount)}</td></tr>`);
  const show = (n) => { $("#txrows").innerHTML = rows.slice(0, n).join("") || `<tr><td colspan="5" class="empty">No transactions.</td></tr>`; $("#more").hidden = rows.length <= n; };
  show(25);
  $("#more").onclick = () => show(rows.length);
}

// ------------------------------------------------------------ outstanding report

async function viewOutstanding(params) {
  if (needCompany()) return;
  view.innerHTML = `
    <h1>Outstanding Customers</h1>
    <div class="panel">
      <div class="toolbar">
        <input type="search" id="q" placeholder="Search…" value="${esc(params.get("q") || "")}">
        <select id="field">${opts([["all", "All fields"], ["name", "Shop name"], ["phone", "Phone"], ["area", "Area / address"], ["area_exact", "Area (exact)"]], params.get("field") || "all")}</select>
        <select id="sort">${opts([["balance_desc", "Highest first"], ["balance_asc", "Lowest first"], ["name_asc", "Name A→Z"], ["area_asc", "Area"]], params.get("sort") || "balance_desc")}</select>
        <input type="number" id="min" placeholder="Min ₹" min="0" step="1000" style="width:110px" value="${esc(params.get("min") || "")}">
        <span class="spacer"></span>
        <a id="csv"><button>Export CSV</button></a>
        <a id="xlsx"><button>Export Excel</button></a>
      </div>
      <div id="results"><div class="loading">Loading from Tally…</div></div>
    </div>`;
  const load = async () => {
    const p = { q: $("#q").value.trim(), field: $("#field").value, sort: $("#sort").value, min: $("#min").value };
    history.replaceState(null, "", "#/outstanding?" + new URLSearchParams(Object.entries(p).filter(([, v]) => v)).toString());
    $("#csv").href = exportUrl("outstanding", "csv", p);
    $("#xlsx").href = exportUrl("outstanding", "xlsx", p);
    let r;
    try { r = await api("/api/reports/outstanding", p); } catch (e) { $("#results").innerHTML = errorBox(e); return; }
    $("#results").innerHTML = `
      <div class="table-wrap"><table>
        <thead><tr><th>#</th><th>Customer</th><th>Area</th><th>Phone</th><th class="num">Outstanding</th></tr></thead>
        <tbody>${r.items.map((c, i) => `<tr><td class="muted">${i + 1}</td><td><a href="#/shops/${encodeURIComponent(c.id)}">${esc(c.name)}</a></td><td>${esc(c.area)}</td><td>${esc((c.phones || []).join(", "))}</td><td class="num dr">${money(c.currentBalance.amount)}</td></tr>`).join("") || `<tr><td colspan="5" class="empty">No outstanding customers match.</td></tr>`}</tbody>
        <tfoot><tr><td></td><td>${r.count} customer${r.count === 1 ? "" : "s"}</td><td></td><td></td><td class="num dr">${money(r.totalOutstanding)}</td></tr></tfoot>
      </table></div>`;
  };
  $("#q").addEventListener("input", debounce(load));
  $("#min").addEventListener("input", debounce(load, 400));
  for (const id of ["field", "sort"]) $("#" + id).addEventListener("change", load);
  load();
}

// ------------------------------------------------------------ tally status

async function viewStatus() {
  view.innerHTML = `<div class="loading">Checking TallyPrime…</div>`;
  const st = await loadStatus();
  if (!st) { view.innerHTML = errorBox({ message: "The application server is not responding." }); return; }
  const lines = st.connected
    ? ["Tally Status", "-------------------------", "Connection: Connected", `Host: ${st.host}`, `Port: ${st.port}`,
       `Company: ${state.company || (st.companies.length ? "(select below)" : "(none open)")}`, `Status: ${st.state}`, `Response: ${st.responseMs} ms`]
    : ["Tally Status", "-------------------------", "Connection: Not Connected", `Host: ${st.host}`, `Port: ${st.port}`,
       st.processRunning === true ? "tally.exe: running" : st.processRunning === false ? "tally.exe: NOT running" : ""].filter(Boolean);
  view.innerHTML = `
    <h1>Tally Status</h1>
    ${st.error ? `<div class="alert error"><strong>${esc(st.error.message)}</strong><div class="details">Possible reasons:</div><ul>${(st.hints || []).map((h) => `<li>${esc(h)}</li>`).join("")}</ul></div>` : ""}
    ${(st.warnings || []).map((w) => `<div class="alert warn">${esc(w)}</div>`).join("")}
    <div class="grid two">
      <section class="panel"><div class="status-block">${esc(lines.join("\n"))}</div>
        <p class="small muted">Endpoint ${esc(st.endpoint)} · port taken from ${esc(st.portSource)} · checked ${fmtTime(st.checkedAt)}</p>
        <button id="recheck">Check again</button></section>
      <section class="panel"><h2>Configuration</h2><dl class="kv">
        <dt>Tally host</dt><dd>${esc(st.host)}</dd>
        <dt>Tally port</dt><dd>${st.port} <span class="muted small">(${esc(st.portSource)})</span></dd>
        ${st.tallyIni ? `<dt>tally.ini</dt><dd>${esc(st.tallyIni.path)}<br><span class="small muted">ServerPort=${st.tallyIni.serverPort || "?"} · Client Server=${esc(st.tallyIni.clientServer || "?")}</span></dd>` : ""}
        <dt>Shop groups</dt><dd>${esc(st.shopGroups.join(", "))} <span class="muted small">(SHOP_GROUPS)</span></dd>
      </dl></section>
    </div>
    ${st.connected ? `
    <section class="panel"><h2>Companies open in TallyPrime</h2>
      ${st.companies.length ? `<div class="table-wrap"><table>
        <thead><tr><th></th><th>Company</th><th>Company no.</th><th>Financial year from</th><th>Books from</th><th>Current period</th><th>Last voucher</th></tr></thead>
        <tbody>${st.companies.map((c) => `<tr>
          <td><input type="radio" name="cmp" value="${esc(c.name)}" ${c.name === state.company ? "checked" : ""}></td>
          <td><strong>${esc(c.name)}</strong><div class="small muted">${esc(c.guid)}</div></td>
          <td>${esc(c.number)}</td><td>${fmtDate(c.financialYearFrom)}</td><td>${fmtDate(c.booksFrom)}</td>
          <td>${fmtDate(c.currentPeriodFrom)} – ${fmtDate(c.currentPeriodTo)}</td><td>${fmtDate(c.lastVoucherDate)}</td></tr>`).join("")}</tbody>
      </table></div>` : `<div class="alert warn">TallyPrime is running but no company is open. Open the company in TallyPrime and check again.</div>`}
    </section>
    <section class="panel"><h2>How are shops stored in this company?</h2>
      <p class="small muted">Ledger count per Tally group. Shops are read from: <strong>${esc(st.shopGroups.join(", "))}</strong> (and its sub-groups).</p>
      <div id="groups"><button id="inspect" ${state.company ? "" : "disabled"}>Inspect ledger groups</button></div>
    </section>` : ""}`;
  $("#recheck").onclick = viewStatus;
  view.querySelectorAll("input[name=cmp]").forEach((el) => (el.onchange = () => { selectCompany(el.value); }));
  const insp = $("#inspect");
  if (insp) insp.onclick = async () => {
    $("#groups").innerHTML = `<div class="loading">Reading ledgers…</div>`;
    try {
      const r = await api("/api/ledgers");
      $("#groups").innerHTML = `<p class="small">${r.count} ledgers in total.</p><div class="table-wrap"><table>
        <thead><tr><th>Group</th><th class="num">Ledgers</th></tr></thead>
        <tbody>${r.groups.map((g) => `<tr><td>${esc(g.group)}${st.shopGroups.includes(g.group) ? ` <span class="tag cr">shops</span>` : ""}</td><td class="num">${g.count}</td></tr>`).join("")}</tbody></table></div>`;
    } catch (e) { $("#groups").innerHTML = errorBox(e); }
  };
}

// ------------------------------------------------------------ cloud sync (configuration page)
//
// Talks to /api/sync/*. Like every other page it needs the admin session;
// a 401 anywhere brings up the login screen (see the login section below).

const sync = { session: null, settings: null, status: null, timer: null };
const SYNC_STATE_CLASS = { SYNCED: "ok", CONNECTED: "ok", SYNCING: "warn", NOT_CONFIGURED: "warn", DISABLED: "neutral", PENDING: "neutral", OVER_PLAN_LIMIT: "warn" };
const syncCls = (s) => SYNC_STATE_CLASS[s] ?? "bad";
const syncTag = (s) => `<span class="tag ${syncCls(s)}">${esc(s)}</span>`;

async function syncApi(method, path, body) {
  const opts = { method, headers: { "X-Requested-With": "WholeFlowSync" } };
  if (body !== undefined) { opts.headers["Content-Type"] = "application/json"; opts.body = JSON.stringify(body); }
  let res;
  try { res = await fetch(path, opts); }
  catch { throw new ApiError(0, { error: { code: "APP_UNREACHABLE", message: "The application server is not responding. Is it still running?" } }); }
  const data = await res.json().catch(() => null);
  if (res.status === 401 && path !== "/api/sync/login") { showLogin(data?.error?.message); throw new ApiError(401, data); }
  if (!res.ok) throw new ApiError(res.status, data);
  return data;
}

// Header pill with the cloud sync state (needs the session like everything else).
async function loadSyncSummary() {
  const pill = $("#syncpill");
  try {
    const s = await syncApi("GET", "/api/sync/summary");
    const last = (s.companies || []).map((c) => c.lastSuccessAt).filter(Boolean).sort().pop();
    const what = s.state === "SUBSCRIPTION_ENDED" ? "Subscription ended — sync paused" : s.state === "DEVICE_REVOKED" ? "access revoked" : s.state;
    pill.textContent = `Cloud sync: ${what}${last ? " · " + fmtTime(last) : ""}`;
    pill.title = s.message || "";
    pill.className = "pill " + (syncCls(s.state) === "neutral" ? "" : syncCls(s.state));
    pill.hidden = false;
  } catch { pill.hidden = true; }
}

function stopSyncPolling() { clearInterval(sync.timer); sync.timer = null; }

async function viewSync() {
  stopSyncPolling();
  await renderSyncMain();
}

async function renderSyncMain() {
  view.innerHTML = `<div class="loading">Loading…</div>`;
  try { [sync.settings, sync.status] = await Promise.all([syncApi("GET", "/api/sync/settings"), syncApi("GET", "/api/sync/status")]); }
  catch (e) { if (e.status !== 401) view.innerHTML = errorBox(e); return; }
  const s = sync.settings;
  const env = s.envOverrides || [];
  const intervals = [60, 120, 300, 600, 900, 1800, 3600];
  view.innerHTML = `
    <h1>Cloud Sync <span class="muted small">Tally → cloud → mobile app</span></h1>
    <section class="panel" id="syncStatusPanel"></section>
    <div class="grid two">
      <section class="panel form"><h2><span class="step">1</span>Connect to WholeFlow</h2>${renderConnect(s, env)}</section>
      <section class="panel form"><h2><span class="step">2</span>Test the connection</h2>
        <p class="small muted">${s.link.connected ? `Checks that this PC can reach <strong>${esc(s.link.businessName || s.business.name)}</strong> on the WholeFlow server.` : "Connect first (step 1), then test."}</p>
        <div class="row"><button id="cloudTest">Test cloud connection</button><span id="cloudResult" class="small"></span></div>
        ${s.link.connected ? `<dl class="kv small">
          <dt>Reference key</dt><dd>${esc(s.link.referenceKey)}</dd>
          <dt>Plan</dt><dd>${s.link.maxCompanies ? `up to ${s.link.maxCompanies} compan${s.link.maxCompanies === 1 ? "y" : "ies"}` : "—"}</dd>
          <dt>Subscription</dt><dd>${esc(s.link.subscriptionState || "—")}</dd>
          <dt>This PC</dt><dd class="muted">${esc(s.link.deviceId)}</dd></dl>` : ""}
        <p class="small muted">The PC key is encrypted at rest (${esc(sync.status.secretScheme)}) and never shown.</p>
      </section>
    </div>
    <section class="panel"><h2><span class="step">3</span>TallyPrime companies to synchronise</h2>
      <div class="grid two">
        <div><div id="tallyBlock" class="status-block">Checking…</div>
          <div class="row"><button id="tallyTest">Test Tally &amp; discover companies</button></div>
          <p class="small muted">Endpoint ${esc(sync.status.tallyEndpoint)} · port from ${esc(sync.status.portSource)} · shop groups: ${esc((sync.status.shopGroups || []).join(", "))}</p></div>
        <div><p class="small muted">Tick the companies to synchronise. Only ticked companies are ever read.${s.link.connected && s.link.maxCompanies ? ` Your plan allows ${s.link.maxCompanies} compan${s.link.maxCompanies === 1 ? "y" : "ies"}.` : ""}</p><div id="companies"></div></div>
      </div>
    </section>
    <div class="grid two">
      <section class="panel form"><h2><span class="step">4</span>Sync settings</h2>
        <label><span class="l">Sync interval</span><select id="interval">${intervals.map((v) => `<option value="${v}" ${s.sync.intervalSeconds === v ? "selected" : ""}>${v < 3600 ? v / 60 + " min" : "1 hour"}</option>`).join("")}${intervals.includes(s.sync.intervalSeconds) ? "" : `<option value="${s.sync.intervalSeconds}" selected>${s.sync.intervalSeconds} s</option>`}</select></label>
        <label class="check"><input type="checkbox" checked disabled> Shops &amp; current balances (always)</label>
        <label class="check"><input type="checkbox" id="txns" ${s.sync.transactions ? "checked" : ""}> Transactions (vouchers, incremental)</label>
        <label class="check"><input type="checkbox" id="syncSuppliers" ${s.sync.suppliers ? "checked" : ""}> Suppliers &amp; payables (Sundry Creditors)</label>
        <label class="check"><input type="checkbox" id="syncPurchases" ${s.sync.purchases ? "checked" : ""}> Purchase bills with item lines (incremental)</label>
        <label class="check"><input type="checkbox" id="syncInventory" ${s.sync.inventory ? "checked" : ""}> Inventory (stock items, qty &amp; value)</label>
        <p class="small muted">Suppliers, purchases and inventory need the <code>0003_purchasing.sql</code> migration in Supabase. If it is missing, shops still sync and these show a warning.</p>
        <label><span class="l">Check for deleted vouchers every (hours)</span><input id="reconcile" type="number" min="1" max="720" value="${s.sync.fullReconcileHours}"></label>
        <label class="check"><input type="checkbox" id="enabled" ${s.sync.enabled ? "checked" : ""}> <strong>Background synchronisation enabled</strong></label>
        <div class="row"><button id="save" class="primary">Save settings</button><span id="saveResult" class="small"></span></div>
        ${env.length ? `<p class="small muted">Overridden by environment: ${esc(env.join(", "))} (changes to those fields are ignored).</p>` : ""}
        <p class="small muted">Config file: ${esc(s.path)}</p>
      </section>
      <section class="panel"><h2><span class="step">5</span>Run &amp; verify</h2>
        <p class="small muted">Save first. A manual run works even while background sync is disabled — use it for the initial synchronisation, then enable background sync and save.</p>
        <div class="row"><button id="syncNow" class="primary">Sync now</button><span id="syncResult" class="small"></span></div>
        <div id="lastRun"></div>
      </section>
    </div>
    <section class="panel form"><h2><span class="step">6</span>Business owner &amp; staff accounts <span class="muted small">logins for the mobile app</span></h2>
      <p class="small muted">These accounts belong to the connected business and are used in the mobile app, never in this app. Create the owner here; the owner can later add staff from the mobile app, or you can add them here.</p>
      <div id="users"><div class="loading">Loading…</div></div>
      <form id="userForm" class="grid two" style="margin-top:12px">
        <label><span class="l">Email</span><input name="email" type="email" autocomplete="off" required placeholder="owner@example.com"></label>
        <label><span class="l">Name</span><input name="name" autocomplete="off" placeholder="Owner's name"></label>
        <label><span class="l">Password (min 8 characters)</span><input name="password" type="password" autocomplete="new-password" required minlength="8"></label>
        <label><span class="l">Role</span><select name="role"><option value="OWNER">Owner</option><option value="STAFF">Staff</option></select></label>
        <div class="row"><button type="submit" class="primary">Create account</button><span id="userResult" class="small"></span></div>
      </form>
    </section>
    <section class="panel"><h2>Log <span class="muted small" id="logPath"></span></h2>
      <div class="row"><button id="logRefresh">Refresh</button><label class="small"><input type="checkbox" id="logAuto"> auto-refresh</label></div>
      <pre class="log" id="log">…</pre></section>`;

  renderSyncStatus();
  renderSyncCompanies(null);
  bindSyncActions();
  loadSyncLog();
  syncTallyTest(false);
  loadUsers();
  sync.timer = setInterval(refreshSyncStatus, 5000);
}

// Step 1: connected (business name, Disconnect) or the reference-key form.
// The older Supabase URL + key connection stays available under "Advanced".
function renderConnect(s, env) {
  const legacy = !s.link.connected && s.cloud.provider !== "wholeflow" && (s.cloud.supabaseUrl || s.business.id || s.cloud.provider === "memory");
  const revoked = s.link.revoked ? errorBox({ message: "This PC's access was revoked. Connect again with a new activation code." }) : "";
  if (s.link.connected && !s.link.revoked) {
    return `<p><span class="tag ok">connected</span> Connected to <strong>${esc(s.link.businessName || s.business.name)}</strong></p>
      ${s.link.keyError ? errorBox({ message: "The stored PC key cannot be read on this machine (" + s.link.keyError + "). Disconnect and connect again with a new activation code." }) : ""}
      <p class="small muted">Connected ${s.link.connectedAt ? fmtTime(s.link.connectedAt) : ""} with reference key ${esc(s.link.referenceKey)}. To move this business to another PC, ask WholeFlow support for a new activation code.</p>
      <div class="row"><button id="disconnect">Disconnect</button><span id="connectResult" class="small"></span></div>`;
  }
  return `${revoked}
    <p class="small muted">Enter the reference key and the activation code you received from WholeFlow support. The activation code works once.</p>
    <form id="connectForm" class="form">
      <label><span class="l">Reference key</span><input name="referenceKey" value="${esc(s.link.referenceKey || "")}" placeholder="ABCD-1234-ABCD-1234" autocomplete="off" required></label>
      <label><span class="l">Activation code</span><input name="activationCode" placeholder="XXXX-XXXX" autocomplete="off" required></label>
      <div class="row"><button type="submit" class="primary">Connect</button><span id="connectResult" class="small"></span></div>
    </form>
    <details ${legacy ? "open" : ""} style="margin-top:12px"><summary class="small">Advanced: connect with Supabase URL and key</summary>
      ${legacy ? `<p class="small muted">This PC uses the older direct Supabase connection. It keeps working; connecting with a reference key above replaces it.</p>` : ""}
      <label><span class="l">Business ID (UUID from the businesses table)</span><input id="bizId" value="${esc(s.business.id)}" placeholder="00000000-0000-0000-0000-000000000000"></label>
      <label><span class="l">Business name (for logs)</span><input id="bizName" value="${esc(s.business.name)}"></label>
      <label><span class="l">Provider</span><select id="provider"><option value="supabase" ${s.cloud.provider !== "memory" ? "selected" : ""}>Supabase (PostgreSQL)</option><option value="memory" ${s.cloud.provider === "memory" ? "selected" : ""}>Memory (dry run, nothing leaves this PC)</option></select></label>
      <label><span class="l">Supabase project URL</span><input id="sbUrl" value="${esc(s.cloud.supabaseUrl)}" placeholder="https://xxxx.supabase.co" ${env.includes("SUPABASE_URL") ? "disabled" : ""}></label>
      <label><span class="l">Service-role key ${s.cloud.hasKey ? '<span class="tag ok">stored</span>' : '<span class="tag warn">not set</span>'} ${s.cloud.keyFromEnv ? '<span class="tag neutral">from environment</span>' : ""}</span>
        <input id="sbKey" type="password" autocomplete="off" placeholder="${s.cloud.hasKey ? "leave blank to keep the stored key" : "paste the service_role key"}" ${s.cloud.keyFromEnv ? "disabled" : ""}></label>
      ${s.cloud.keyError ? errorBox({ message: "Stored key cannot be read: " + s.cloud.keyError + " Enter it again." }) : ""}
      <p class="small muted">Saved with "Save settings" (step 4). Never put the key in the mobile app.</p>
    </details>`;
}

async function refreshSyncStatus() {
  if (!location.hash.startsWith("#/sync")) return stopSyncPolling();
  try { sync.status = await syncApi("GET", "/api/sync/status"); renderSyncStatus(); loadSyncSummary(); if ($("#logAuto")?.checked) loadSyncLog(); }
  catch (e) { if (e.status === 401) stopSyncPolling(); }
}

function renderSyncStatus() {
  const st = sync.status.sync;
  const last = st.lastRun;
  const panel = $("#syncStatusPanel");
  if (!panel) return;
  panel.innerHTML = `
    <div class="grid two">
      <dl class="kv">
        <dt>Cloud sync</dt><dd>${syncTag(st.state)} ${st.running ? '<span class="muted small">running…</span>' : ""}</dd>
        <dt>Background sync</dt><dd>${st.enabled ? `on, every ${st.intervalSeconds / 60} min` : "off"}</dd>
        <dt>Next sync</dt><dd>${st.nextRunAt ? fmtTime(st.nextRunAt) : "—"}${st.consecutiveFailures ? ` <span class="tag warn">retry ${st.consecutiveFailures}</span>` : ""}</dd>
        <dt>Last run</dt><dd>${last ? `${fmtTime(last.startedAt)} · ${esc(last.status)}${last.errorCode ? ` · ${esc(last.errorCode)}: ${esc(last.errorMessage)}` : ""}` : "never"}</dd>
        ${st.configured || st.state === "DEVICE_REVOKED" ? "" : `<dt>Configuration</dt><dd><span class="tag warn">${esc(st.configMessage)}</span></dd>`}
      </dl>
      ${st.message ? `<div class="alert ${st.state === "SUBSCRIPTION_ENDED" || st.state === "DEVICE_REVOKED" ? "bad" : "warn"}" style="grid-column:1/-1">${esc(st.message)}</div>` : ""}
      <div class="table-wrap"><table>
        <thead><tr><th>Company</th><th>Status</th><th>Last successful sync</th><th class="num">Shops</th><th class="num">Transactions</th><th class="num">Suppliers</th><th class="num">Stock items</th><th class="num">Purchase bills</th></tr></thead>
        <tbody>${(st.companies || []).map((c) => `<tr><td>${esc(c.name || c.tallyId)}</td><td>${syncTag(c.status)}${c.lastError ? `<div class="small muted">${esc(c.lastErrorCode)}: ${esc(c.lastError)}</div>` : ""}</td><td>${fmtTime(c.lastSuccessAt)}</td><td class="num">${c.shopCount ?? 0}</td><td class="num">${c.transactionCount ?? 0}</td><td class="num">${c.supplierCount ?? 0}</td><td class="num">${c.stockItemCount ?? 0}</td><td class="num">${c.purchaseCount ?? 0}</td></tr>${(c.warnings || []).map((w) => `<tr><td></td><td colspan="7"><div class="alert warn small" style="margin:0">Warning — ${esc(w)}</div></td></tr>`).join("")}`).join("") || `<tr><td colspan="8" class="empty">No company selected yet.</td></tr>`}</tbody>
      </table></div>
    </div>`;
  if ($("#lastRun") && last) {
    $("#lastRun").innerHTML = `<div class="table-wrap"><table><thead><tr><th>Company</th><th>Result</th><th>Mode</th><th class="num">Shops +/~/−</th><th class="num">Txns +/~/−</th><th class="num">Suppliers +/~/−</th><th class="num">Items +/~/−</th><th class="num">Bills +/~/−</th><th class="num">Time</th></tr></thead>
      <tbody>${(last.companies || []).map((c) => `<tr><td>${esc(c.name)}</td><td>${syncTag(c.status)}${c.errorCode ? `<div class="small muted">${esc(c.errorCode)}: ${esc(c.errorMessage)}</div>` : ""}</td><td>${esc(c.mode || "")}</td>
        <td class="num">${c.shops.created}/${c.shops.updated}/${c.shops.deleted}</td><td class="num">${c.transactions.created}/${c.transactions.updated}/${c.transactions.deleted}</td>${[c.suppliers, c.stockItems, c.purchases].map((x) => `<td class="num">${x ? `${x.created}/${x.updated}/${x.deleted}` : "—"}</td>`).join("")}<td class="num">${(c.durationMs / 1000).toFixed(1)}s</td></tr>`).join("") || `<tr><td colspan="9" class="empty">${esc(last.status)}${last.errorMessage ? ": " + esc(last.errorMessage) : ""}</td></tr>`}</tbody></table></div>`;
  }
}

function renderSyncCompanies(discovered) {
  const cfg = sync.settings.companies || [];
  const byId = new Map(cfg.map((c) => [c.tallyId, c]));
  const rows = [];
  if (discovered) for (const c of discovered) rows.push({ tallyId: c.guid, name: c.name, enabled: byId.get(c.guid)?.enabled || false, open: true, info: `books from ${fmtDate(c.booksFrom)} · period ${fmtDate(c.currentPeriodFrom)} – ${fmtDate(c.currentPeriodTo)}` });
  for (const c of cfg) if (!rows.some((r) => r.tallyId === c.tallyId)) rows.push({ tallyId: c.tallyId, name: c.name, enabled: c.enabled, open: false, info: discovered ? "not open in TallyPrime right now" : "" });
  $("#companies").innerHTML = rows.length
    ? `<table><tbody>${rows.map((r) => `<tr><td style="width:30px"><input type="checkbox" class="cmp" data-id="${esc(r.tallyId)}" data-name="${esc(r.name)}" ${r.enabled ? "checked" : ""}></td>
        <td><strong>${esc(r.name || r.tallyId)}</strong> ${r.open ? "" : '<span class="tag warn">not open</span>'}<div class="small muted">${esc(r.tallyId)}${r.info ? " · " + esc(r.info) : ""}</div></td></tr>`).join("")}</tbody></table>`
    : `<p class="muted small">Click “Test Tally &amp; discover companies”.</p>`;
}

async function syncTallyTest(interactive) {
  const block = $("#tallyBlock");
  if (!block) return;
  if (interactive) block.textContent = "Checking TallyPrime…";
  let t;
  try { t = await syncApi("POST", "/api/sync/tally/test", {}); } catch (e) { block.textContent = "Error: " + e.message; return; }
  t.companies = t.companies || [];
  const lines = ["Tally Connection", "-------------------------", `Status: ${t.connected ? "Connected" : "Not Connected"}`, `Host: ${t.host}`, `Port: ${t.port}`];
  if (t.connected) lines.push(`Response: ${t.responseMs} ms`, `Companies open: ${t.companies.length}`);
  else { lines.push(`tally.exe: ${t.processRunning === true ? "running" : t.processRunning === false ? "NOT running" : "?"}`); if (t.error) lines.push("", t.error.message); }
  for (const w of t.warnings || []) lines.push("", "Warning: " + w);
  block.textContent = lines.join("\n");
  renderSyncCompanies(t.connected ? t.companies : null);
}

// legacyCloud reads the "Advanced" Supabase fields, or keeps the saved values
// when they are not on the page (connected with a reference key).
function legacyCloud() {
  const s = sync.settings;
  if (!$("#provider")) return { business: s.business, cloud: { provider: s.cloud.provider, supabaseUrl: s.cloud.supabaseUrl, supabaseKey: "" } };
  return { business: { id: $("#bizId").value, name: $("#bizName").value }, cloud: { provider: $("#provider").value, supabaseUrl: $("#sbUrl").value, supabaseKey: $("#sbKey").value } };
}

function collectSyncSettings() {
  return {
    ...legacyCloud(),
    sync: { enabled: $("#enabled").checked, intervalSeconds: +$("#interval").value, transactions: $("#txns").checked, fullReconcileHours: +$("#reconcile").value,
            suppliers: $("#syncSuppliers").checked, purchases: $("#syncPurchases").checked, inventory: $("#syncInventory").checked },
    companies: [...document.querySelectorAll("input.cmp")].map((el) => ({ tallyId: el.dataset.id, name: el.dataset.name, enabled: el.checked })),
  };
}

function bindSyncActions() {
  $("#tallyTest").onclick = () => syncTallyTest(true);
  $("#cloudTest").onclick = async () => {
    const out = $("#cloudResult"); out.textContent = "Testing…";
    try {
      const r = await syncApi("POST", "/api/sync/cloud/test", legacyCloud());
      out.innerHTML = r.ok ? `<span class="tag ok">connected</span> ${esc(r.businessName || r.provider)} · business ${esc(r.businessId)} · ${r.responseMs} ms` : `<span class="tag bad">${esc(r.error.code)}</span> ${esc(r.error.message)}`;
    } catch (e) { out.innerHTML = `<span class="tag bad">error</span> ${esc(e.message)}`; }
  };
  if ($("#connectForm")) $("#connectForm").onsubmit = async (e) => {
    e.preventDefault();
    const f = new FormData(e.target); const out = $("#connectResult"); out.textContent = "Connecting…";
    try {
      const r = await syncApi("POST", "/api/sync/connect", { referenceKey: f.get("referenceKey"), activationCode: f.get("activationCode") });
      out.innerHTML = `<span class="tag ok">connected</span> Connected to ${esc(r.businessName)}`;
      await renderSyncMain(); loadSyncSummary();
    } catch (err) { out.innerHTML = `<span class="tag bad">not connected</span> ${esc(err.message)}`; }
  };
  if ($("#disconnect")) $("#disconnect").onclick = async () => {
    if (!confirm("Disconnect this PC from the WholeFlow server? Syncing stops until it is connected again with a new activation code.")) return;
    const out = $("#connectResult");
    try { await syncApi("POST", "/api/sync/disconnect"); await renderSyncMain(); loadSyncSummary(); }
    catch (err) { out.innerHTML = `<span class="tag bad">error</span> ${esc(err.message)}`; }
  };
  $("#save").onclick = async () => {
    const out = $("#saveResult"); out.textContent = "Saving…";
    try { await syncApi("PUT", "/api/sync/settings", collectSyncSettings()); out.innerHTML = `<span class="tag ok">saved</span>`; await renderSyncMain(); loadSyncSummary(); }
    catch (e) { out.innerHTML = `<span class="tag bad">not saved</span> ${esc(e.message)}`; }
  };
  $("#syncNow").onclick = async () => {
    const out = $("#syncResult"); out.textContent = "Sync requested…";
    try { await syncApi("POST", "/api/sync/run"); out.textContent = "Running — the status above updates every few seconds."; $("#logAuto").checked = true; }
    catch (e) { out.innerHTML = `<span class="tag bad">error</span> ${esc(e.message)}`; }
  };
  $("#logRefresh").onclick = loadSyncLog;
  $("#userForm").onsubmit = async (e) => {
    e.preventDefault();
    const f = new FormData(e.target); const out = $("#userResult"); out.textContent = "Creating…";
    try {
      const r = await syncApi("POST", "/api/sync/users", { email: f.get("email"), name: f.get("name"), password: f.get("password"), role: f.get("role") });
      out.innerHTML = `<span class="tag ok">created</span> ${esc(r.user.email)} (${esc(r.user.role)}) — they can now log in to the mobile app with this email and password.`;
      e.target.reset();
      loadUsers();
    } catch (err) { out.innerHTML = `<span class="tag bad">${esc(err.code || "error")}</span> ${esc(err.message)}`; }
  };
}

async function loadUsers() {
  const box = $("#users");
  if (!box) return;
  let r;
  try { r = await syncApi("GET", "/api/sync/users"); }
  catch (e) { box.innerHTML = `<p class="small muted">${esc(e.message)}</p>`; return; }
  box.innerHTML = r.users.length
    ? `<div class="table-wrap"><table><thead><tr><th>Email</th><th>Name</th><th>Role</th><th>Status</th><th>Created</th><th></th></tr></thead>
       <tbody>${r.users.map((u) => `<tr><td>${esc(u.email)}</td><td>${esc(u.name)}</td><td>${esc(u.role)}</td>
         <td>${u.isActive ? '<span class="tag ok">active</span>' : '<span class="tag bad">disabled</span>'}</td><td>${fmtTime(u.createdAt)}</td>
         <td class="num"><button class="small" data-act="pw" data-id="${esc(u.id)}" data-email="${esc(u.email)}">Reset password</button>
             <button class="small" data-act="active" data-id="${esc(u.id)}" data-email="${esc(u.email)}" data-next="${u.isActive ? "false" : "true"}">${u.isActive ? "Disable" : "Enable"}</button></td></tr>`).join("")}</tbody></table></div>`
    : `<p class="small muted">No accounts yet for this business. Create the owner's login below.</p>`;
  box.querySelectorAll("button[data-act]").forEach((b) => (b.onclick = async () => {
    const out = $("#userResult");
    try {
      if (b.dataset.act === "pw") {
        const pw = prompt(`New password for ${b.dataset.email} (min 8 characters):`);
        if (!pw) return;
        await syncApi("POST", `/api/sync/users/${encodeURIComponent(b.dataset.id)}/password`, { password: pw });
        out.innerHTML = `<span class="tag ok">password changed</span> ${esc(b.dataset.email)}`;
      } else {
        const next = b.dataset.next === "true";
        if (!next && !confirm(`Disable ${b.dataset.email}? They will no longer be able to use the mobile app.`)) return;
        await syncApi("POST", `/api/sync/users/${encodeURIComponent(b.dataset.id)}/active`, { active: next });
        out.innerHTML = `<span class="tag ok">${next ? "enabled" : "disabled"}</span> ${esc(b.dataset.email)}`;
        loadUsers();
      }
    } catch (e) { out.innerHTML = `<span class="tag bad">${esc(e.code || "error")}</span> ${esc(e.message)}`; }
  }));
}

async function loadSyncLog() {
  const el = $("#log");
  if (!el) return;
  try { const r = await syncApi("GET", "/api/sync/logs?lines=300"); $("#logPath").textContent = r.path; el.textContent = (r.lines || []).join("\n") || "(empty)"; el.scrollTop = el.scrollHeight; }
  catch (e) { el.textContent = "Could not load log: " + e.message; }
}

// ------------------------------------------------------------ suppliers, purchases, inventory
//
// Suppliers are ledgers under SUPPLIER_GROUPS (default Sundry Creditors):
// for them a Cr balance is money we owe (payable), a Dr balance an advance.
// Purchases and stock items are read from Tally once per company and kept
// until "Refresh from Tally".

const qtyFmt = new Intl.NumberFormat("en-IN", { maximumFractionDigits: 3 });
const qty = (n, unit) => `${qtyFmt.format(n || 0)}${unit ? ` <span class="muted small">${esc(unit)}</span>` : ""}`;
const payTag = (b) => (b && b.type === "CR" ? `<span class="tag cr">Payable</span>` : b && b.type === "DR" ? `<span class="tag dr">Advance</span>` : "");
const STOCK_STATUS = { in_stock: ["ok", "In stock"], low: ["warn", "Low"], zero: ["neutral", "Out of stock"], negative: ["bad", "Negative"] };
const stockTag = (s) => { const [c, l] = STOCK_STATUS[s] || ["neutral", s]; return `<span class="tag ${c}">${esc(l)}</span>`; };
const SUPPLIER_CATEGORY_LABEL = { purchases: "Total Purchases", payments: "Total Payments", purchase_returns: "Total Purchase Returns (Debit Notes)", adjustments: "Total Adjustments (Journal / other)" };
const hashWith = (base, p) => base + "?" + new URLSearchParams(Object.entries(p).filter(([, v]) => v !== "" && v != null)).toString();
const pager = (r, what) => `
  <div class="pager">
    <span class="muted">${r.total} ${what}${r.total === 1 ? "" : "s"} · page ${r.total ? r.page : 0} of ${r.pages}</span>
    <select id="pageSize">${opts([[25, "25 / page"], [50, "50 / page"], [100, "100 / page"], [500, "500 / page"]], String(r.pageSize))}</select>
    <button id="prev" ${r.page <= 1 ? "disabled" : ""}>‹ Prev</button>
    <button id="next" ${r.page >= r.pages ? "disabled" : ""}>Next ›</button>
  </div>`;
const bindPager = (q, load) => {
  $("#prev").onclick = () => { q.page--; load(); };
  $("#next").onclick = () => { q.page++; load(); };
  $("#pageSize").onchange = (e) => { q.pageSize = +e.target.value; q.page = 1; load(); };
};

// ---- suppliers

async function viewSuppliers(params) {
  if (needCompany()) return;
  const q = { q: params.get("q") || "", type: params.get("type") || "", sort: params.get("sort") || "balance_desc" };
  view.innerHTML = `
    <h1>Suppliers</h1>
    <div id="kpis" class="grid kpis"></div>
    <div class="panel">
      <div class="toolbar">
        <input type="search" id="q" placeholder="Search suppliers…" value="${esc(q.q)}">
        <select id="type">${opts([["", "All balances"], ["cr", "Payable (Cr)"], ["dr", "Advance (Dr)"], ["zero", "Settled"]], q.type)}</select>
        <select id="sort">${opts([["balance_desc", "Highest payable first"], ["balance_asc", "Highest advance first"], ["name_asc", "Name A→Z"], ["name_desc", "Name Z→A"]], q.sort)}</select>
        <span class="spacer"></span>
        <a id="csv"><button>Export CSV</button></a>
        <a id="xlsx"><button>Export Excel</button></a>
      </div>
      <div id="results"><div class="loading">Loading from Tally…</div></div>
    </div>`;
  const load = async () => {
    const p = { q: $("#q").value.trim(), type: $("#type").value, sort: $("#sort").value, pageSize: 500 };
    history.replaceState(null, "", hashWith("#/suppliers", { q: p.q, type: p.type, sort: p.sort }));
    $("#csv").href = exportUrl("suppliers", "csv", p);
    $("#xlsx").href = exportUrl("suppliers", "xlsx", p);
    let r;
    try { r = await api("/api/suppliers", p); } catch (e) { $("#results").innerHTML = errorBox(e); return; }
    $("#kpis").innerHTML = `
      ${kpi("Suppliers", r.totalSuppliers, esc(r.groups.join(", ")))}
      ${kpi("Total payable", money(r.totalPayable), `${r.suppliersPayable} supplier(s) with a Cr balance`, "cr")}
      ${kpi("Advances paid", money(r.totalAdvance), `${r.suppliersAdvance} supplier(s) with a Dr balance`, "dr")}
      ${kpi("Net", `${money(r.netPayable.amount)} ${drcr(r.netPayable.type)}`, r.netPayable.type === "CR" ? "We owe suppliers overall" : r.netPayable.type === "DR" ? "Suppliers owe us / advances exceed dues" : "Settled")}`;
    $("#results").innerHTML = `
      <div class="table-wrap"><table>
        <thead><tr><th>Supplier</th><th>GSTIN</th><th>Phone</th><th>Tally group</th><th class="num">Balance</th><th></th></tr></thead>
        <tbody>${r.items.map((c) => `<tr>
          <td><a href="#/suppliers/${encodeURIComponent(c.id)}">${esc(c.name)}</a></td>
          <td class="small">${esc(c.gstin)}</td>
          <td>${esc((c.phones || []).join(", "))}</td>
          <td class="small muted">${esc(c.group)}</td>
          <td class="num">${bal(c.currentBalance)}</td>
          <td>${payTag(c.currentBalance)}</td>
        </tr>`).join("") || `<tr><td colspan="6" class="empty">No suppliers match.</td></tr>`}</tbody>
      </table></div>
      <p class="muted small">${r.total} supplier${r.total === 1 ? "" : "s"}. Cr = we owe the supplier; Dr = advance paid or excess payment.</p>`;
  };
  $("#q").addEventListener("input", debounce(load));
  for (const id of ["type", "sort"]) $("#" + id).addEventListener("change", load);
  load();
}

async function viewSupplier(id) {
  if (needCompany()) return;
  view.innerHTML = `<div class="loading">Loading from Tally…</div>`;
  let r;
  try { r = await api(`/api/suppliers/${encodeURIComponent(id)}`); } catch (e) { view.innerHTML = `<p><a href="#/suppliers">← Suppliers</a></p>` + errorBox(e); return; }
  const c = r.supplier;
  const row = (k, v) => (v ? `<dt>${k}</dt><dd>${v}</dd>` : "");
  const b = c.currentBalance;
  view.innerHTML = `
    <p><a href="javascript:history.back()">← Back</a></p>
    <h1>${esc(c.name)} ${payTag(b)}</h1>
    ${c.parseWarnings ? `<div class="alert warn">Some values from Tally could not be read: ${esc(c.parseWarnings.join("; "))}</div>` : ""}
    <div class="grid two">
      <section class="panel"><h2>Contact</h2><dl class="kv">
        ${row("Phone", esc((c.phones || []).join(", ")))}
        ${row("Contact person", esc(c.contactPerson))}
        ${row("Email", esc(c.email))}
        ${row("Address", (c.address || []).map(esc).join("<br>"))}
        ${row("State", esc(c.state))}
        ${row("Pincode", esc(c.pincode))}
        ${row("GSTIN", esc(c.gstin))}
        ${row("GST registration", esc(c.gstRegistrationType))}
        ${row("Alias", esc((c.aliases || []).join(", ")))}
        ${row("Tally group", esc(c.group))}
      </dl></section>
      <section class="panel"><h2>Account summary <span class="muted small">live from Tally · ${fmtTime(r.fetchedAt)}</span></h2><dl class="kv">
        <dt>Opening balance</dt><dd>${bal(c.openingBalance)}</dd>
        <dt>Current balance</dt><dd style="font-size:18px;font-weight:650">${bal(b)}</dd>
        <dt>Meaning</dt><dd>${b.type === "CR" ? "Cr — amount we owe this supplier" : b.type === "DR" ? "Dr — advance paid / the supplier owes us" : "Settled (zero balance)"}</dd>
      </dl>
      <p class="small"><a href="${hashWith("#/purchases", { supplier: c.name })}">Purchase bills from this supplier →</a></p></section>
    </div>
    <section class="panel" id="txn"><h2>Transaction summary</h2><div class="loading">Reading vouchers from Tally…</div></section>`;

  let t;
  try { t = await api(`/api/suppliers/${encodeURIComponent(id)}/transactions`); } catch (e) { $("#txn").innerHTML = `<h2>Transaction summary</h2>` + errorBox(e); return; }
  const ex = t.excluded, exN = ex.optional + ex.cancelled + ex.postDated;
  $("#txn").innerHTML = `
    <h2>Transaction summary <span class="muted small">${fmtDate(t.from)} – ${fmtDate(t.to)}</span></h2>
    ${t.reconciled
      ? `<div class="alert ok small">Checked: opening balance + these transactions = Tally's current balance (${bal(t.tallyClosing)}).</div>`
      : `<div class="alert warn small">These transactions do not add up to Tally's balance: opening ${bal(t.opening)} + movement ${bal(t.movement)} = ${bal(t.computedClosing)}, but Tally reports ${bal(t.tallyClosing)}. The <strong>current balance above is Tally's own figure</strong>.</div>`}
    <div class="table-wrap"><table>
      <thead><tr><th></th><th class="num">Vouchers</th><th class="num">Debit</th><th class="num">Credit</th><th class="num">Net</th></tr></thead>
      <tbody>${t.totals.map((x) => `<tr><td>${SUPPLIER_CATEGORY_LABEL[x.category] || esc(x.category)}</td><td class="num">${x.count}</td><td class="num">${money(x.debit)}</td><td class="num">${money(x.credit)}</td><td class="num">${bal(x.net)}</td></tr>`).join("")}</tbody>
    </table></div>
    ${exN ? `<p class="muted small">Not counted (as in Tally's balance): ${ex.optional} optional, ${ex.cancelled} cancelled, ${ex.postDated} post-dated voucher(s).</p>` : ""}
    <h2 style="margin-top:20px">Transactions (${t.transactions.length})</h2>
    <div class="table-wrap"><table>
      <thead><tr><th>Date</th><th>Voucher type</th><th>No.</th><th>Narration</th><th class="num">Amount</th></tr></thead>
      <tbody id="txrows"></tbody>
    </table></div>
    <div class="pager"><button id="more" hidden>Show all</button></div>`;
  const rows = t.transactions.map((x) => `<tr><td>${fmtDate(x.date)}</td><td>${esc(x.voucherType)}</td><td>${esc(x.number)}</td><td class="small">${esc(x.narration)}</td><td class="num">${bal(x.amount)}</td></tr>`);
  const show = (n) => { $("#txrows").innerHTML = rows.slice(0, n).join("") || `<tr><td colspan="5" class="empty">No transactions.</td></tr>`; $("#more").hidden = rows.length <= n; };
  show(25);
  $("#more").onclick = () => show(rows.length);
}

// ---- purchases

const isoDay = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

function quickRanges() {
  const now = new Date();
  const y = now.getFullYear(), m = now.getMonth();
  const fyStart = new Date(m >= 3 ? y : y - 1, 3, 1);
  return [
    ["month", "This month", isoDay(new Date(y, m, 1)), isoDay(now)],
    ["lastmonth", "Last month", isoDay(new Date(y, m - 1, 1)), isoDay(new Date(y, m, 0))],
    ["fy", "This FY", isoDay(fyStart), isoDay(new Date(fyStart.getFullYear() + 1, 2, 31))],
    ["all", "All", "", ""],
  ];
}

async function viewPurchases(params) {
  if (needCompany()) return;
  const q = { tab: params.get("tab") || "bills", from: params.get("from") || "", to: params.get("to") || "", supplier: params.get("supplier") || "",
              q: params.get("q") || "", page: +params.get("page") || 1, pageSize: +params.get("pageSize") || 50 };
  view.innerHTML = `
    <h1>Purchases</h1>
    <div class="panel">
      <div class="toolbar">
        <span class="tabs">
          <button data-tab="bills" class="${q.tab === "bills" ? "primary" : ""}">Bills</button>
          <button data-tab="items" class="${q.tab === "items" ? "primary" : ""}">By item</button>
        </span>
        <label class="small">From <input type="date" id="from" value="${esc(q.from)}"></label>
        <label class="small">To <input type="date" id="to" value="${esc(q.to)}"></label>
        ${quickRanges().map(([k, l]) => `<button data-range="${k}">${l}</button>`).join("")}
      </div>
      <div class="toolbar">
        <input type="search" id="q" placeholder="${q.tab === "items" ? "Search items…" : "Search supplier, bill no., item…"}" value="${esc(q.q)}">
        <select id="supplier"><option value="">All suppliers</option>${q.supplier ? `<option value="${esc(q.supplier)}" selected>${esc(q.supplier)}</option>` : ""}</select>
        <span class="spacer"></span>
        <a id="csv"><button>Export CSV</button></a>
        <a id="xlsx"><button>Export Excel</button></a>
        ${q.tab === "bills" ? `<a id="lines"><button title="One row per item line">Export lines (Excel)</button></a>` : ""}
      </div>
    </div>
    <div id="kpis" class="grid kpis"></div>
    <div id="results"><div class="loading">Reading purchase vouchers from Tally…</div></div>`;

  const params_ = () => ({ from: $("#from").value, to: $("#to").value, supplier: $("#supplier").value, q: $("#q").value.trim() });
  const load = async () => {
    const f = params_();
    history.replaceState(null, "", hashWith("#/purchases", { tab: q.tab === "bills" ? "" : q.tab, ...f, page: q.page > 1 ? q.page : "" }));
    const report = q.tab === "items" ? "purchase-items" : "purchases";
    $("#csv").href = exportUrl(report, "csv", f);
    $("#xlsx").href = exportUrl(report, "xlsx", f);
    if ($("#lines")) $("#lines").href = exportUrl("purchase-lines", "xlsx", f);
    try {
      if (q.tab === "items") await loadItems(f); else await loadBills(f);
    } catch (e) { $("#results").innerHTML = errorBox(e); }
  };

  const fillSuppliers = (names) => {
    const sel = $("#supplier"), cur = sel.value;
    if (sel.options.length > 2 || !names) return;
    sel.innerHTML = `<option value="">All suppliers</option>` + names.map((n) => `<option value="${esc(n)}" ${n === cur ? "selected" : ""}>${esc(n)}</option>`).join("");
  };

  const loadBills = async (f) => {
    const r = await api("/api/purchases", { ...f, page: q.page, pageSize: q.pageSize });
    fillSuppliers(r.suppliers);
    const t = r.totals;
    $("#kpis").innerHTML = `
      ${kpi("Bills", t.bills, r.firstDate ? `Tally has bills from ${fmtDate(r.firstDate)} to ${fmtDate(r.lastDate)}` : "")}
      ${kpi("Taxable value", money(t.taxable), "Sum of item lines")}
      ${kpi("Tax & other", money(t.other), "GST, TCS, freight, round off")}
      ${kpi("Purchase total", money(t.total), "Bill amounts credited to suppliers")}
      ${kpi("Quantity", qtyFmt.format(t.qty), "All units added together")}`;
    const ex = r.excluded;
    $("#results").innerHTML = `
      <div class="grid" style="grid-template-columns:minmax(0,3fr) minmax(260px,1fr)">
        <section class="panel">
          <div class="table-wrap"><table>
            <thead><tr><th>Date</th><th>Voucher no.</th><th>Supplier</th><th>Supplier bill</th><th class="num">Items</th><th class="num">Qty</th><th class="num">Taxable</th><th class="num">Tax &amp; other</th><th class="num">Total</th></tr></thead>
            <tbody>${r.items.map((p) => `<tr>
              <td>${fmtDate(p.date)}</td>
              <td><a href="#/purchases/${encodeURIComponent(p.id)}">${esc(p.number || "(no number)")}</a><div class="small muted">${esc(p.voucherType)}</div></td>
              <td>${esc(p.supplier)}</td><td class="small">${esc(p.reference)}</td>
              <td class="num">${p.lineCount}</td><td class="num">${qtyFmt.format(p.qty)}</td>
              <td class="num">${money(p.taxable)}</td><td class="num">${money(p.other)}</td><td class="num"><strong>${money(p.total)}</strong></td>
            </tr>`).join("") || `<tr><td colspan="9" class="empty">No purchase bills match.</td></tr>`}</tbody>
          </table></div>
          ${pager(r, "bill")}
          ${ex.cancelled + ex.optional ? `<p class="muted small">Not included: ${ex.cancelled} cancelled, ${ex.optional} optional voucher(s).</p>` : ""}
        </section>
        <section class="panel"><h2>By supplier</h2>
          <table><tbody>${r.bySupplier.map((s) => `<tr><td><a href="#" data-sup="${esc(s.supplier)}">${esc(s.supplier)}</a><div class="small muted">${s.bills} bill${s.bills === 1 ? "" : "s"}</div></td><td class="num">${money(s.total)}</td></tr>`).join("") || `<tr><td class="empty">—</td></tr>`}</tbody></table>
        </section>
      </div>`;
    bindPager(q, load);
    $("#results").querySelectorAll("a[data-sup]").forEach((a) => (a.onclick = (e) => {
      e.preventDefault(); $("#supplier").value = a.dataset.sup; q.page = 1; load();
    }));
  };

  const loadItems = async (f) => {
    const [r, bills] = await Promise.all([api("/api/purchases/items", f), api("/api/purchases", { ...f, q: "", pageSize: 1 })]);
    fillSuppliers(bills.suppliers);
    $("#kpis").innerHTML = `
      ${kpi("Items purchased", r.count, "Distinct stock items")}
      ${kpi("Taxable value", money(r.totalAmount), "Sum of item lines")}
      ${kpi("Bills", bills.totals.bills, "In the selected period")}`;
    $("#results").innerHTML = `
      <section class="panel"><div class="table-wrap"><table>
        <thead><tr><th>Item</th><th class="num">Qty</th><th class="num">Avg rate</th><th class="num">Last rate</th><th>Last purchased</th><th class="num">Bills</th><th class="num">Amount</th></tr></thead>
        <tbody>${r.items.map((it) => `<tr>
          <td><a href="#/inventory/${encodeURIComponent(it.item)}">${esc(it.item)}</a></td>
          <td class="num">${qty(it.qty, it.unit)}</td><td class="num">${money(it.avgRate)}</td><td class="num">${money(it.lastRate)}</td>
          <td>${fmtDate(it.lastDate)}</td><td class="num">${it.bills}</td><td class="num"><strong>${money(it.amount)}</strong></td>
        </tr>`).join("") || `<tr><td colspan="7" class="empty">No items match.</td></tr>`}</tbody>
      </table></div></section>`;
  };

  const reset = () => { q.page = 1; load(); };
  view.querySelectorAll("button[data-tab]").forEach((b) => (b.onclick = () => { q.tab = b.dataset.tab; q.page = 1; q.q = ""; history.replaceState(null, "", hashWith("#/purchases", { tab: q.tab === "bills" ? "" : q.tab, ...params_(), q: "" })); viewPurchases(new URLSearchParams(location.hash.split("?")[1] || "")); }));
  view.querySelectorAll("button[data-range]").forEach((b) => (b.onclick = () => {
    const [, , from, to] = quickRanges().find(([k]) => k === b.dataset.range);
    $("#from").value = from; $("#to").value = to; reset();
  }));
  $("#q").addEventListener("input", debounce(reset));
  for (const id of ["from", "to", "supplier"]) $("#" + id).addEventListener("change", reset);
  load();
}

async function viewPurchase(id) {
  if (needCompany()) return;
  view.innerHTML = `<div class="loading">Loading from Tally…</div>`;
  let r;
  try { r = await api(`/api/purchases/${encodeURIComponent(id)}`); } catch (e) { view.innerHTML = `<p><a href="#/purchases">← Purchases</a></p>` + errorBox(e); return; }
  const p = r.purchase;
  const row = (k, v) => (v ? `<dt>${k}</dt><dd>${v}</dd>` : "");
  view.innerHTML = `
    <p><a href="javascript:history.back()">← Back</a></p>
    <h1>Purchase ${esc(p.number)} <span class="muted small">${fmtDate(p.date)}</span></h1>
    <div class="grid two">
      <section class="panel"><h2>Bill</h2><dl class="kv">
        ${row("Supplier", `<a href="${hashWith("#/purchases", { supplier: p.supplier })}">${esc(p.supplier)}</a>`)}
        ${row("Date", fmtDate(p.date))}
        ${row("Voucher type", esc(p.voucherType))}
        ${row("Voucher no.", esc(p.number))}
        ${row("Supplier bill no.", esc(p.reference))}
        ${row("Narration", esc(p.narration))}
      </dl></section>
      <section class="panel"><h2>Amounts</h2><dl class="kv">
        <dt>Taxable value</dt><dd>${money(p.taxable)}</dd>
        <dt>Tax &amp; other</dt><dd>${money(p.other)}</dd>
        <dt>Bill total</dt><dd style="font-size:18px;font-weight:650">${money(p.total)}</dd>
        <dt>Quantity</dt><dd>${qtyFmt.format(p.qty)}</dd>
      </dl></section>
    </div>
    <section class="panel"><h2>Items (${(p.lines || []).length})</h2>
      <div class="table-wrap"><table>
        <thead><tr><th>#</th><th>Item</th><th>Godown</th><th class="num">Qty</th><th class="num">Rate</th><th class="num">Disc %</th><th class="num">Amount</th></tr></thead>
        <tbody>${(p.lines || []).map((l, i) => `<tr><td class="muted">${i + 1}</td><td><a href="#/inventory/${encodeURIComponent(l.item)}">${esc(l.item)}</a></td><td class="small">${esc(l.godown)}</td>
          <td class="num">${qty(l.qty, l.unit)}</td><td class="num">${money(l.rate)}</td><td class="num">${l.discount ? l.discount : ""}</td><td class="num">${money(l.amount)}</td></tr>`).join("") || `<tr><td colspan="7" class="empty">No item lines (accounting-only voucher).</td></tr>`}</tbody>
        <tfoot><tr><td></td><td>Taxable value</td><td></td><td class="num">${qtyFmt.format(p.qty)}</td><td></td><td></td><td class="num">${money(p.taxable)}</td></tr></tfoot>
      </table></div></section>
    <section class="panel"><h2>Accounting entries <span class="muted small">(supplier's entry omitted)</span></h2>
      <div class="table-wrap"><table>
        <thead><tr><th>Ledger</th><th class="num">Amount</th></tr></thead>
        <tbody>${(p.ledgers || []).map((l) => `<tr><td>${esc(l.ledger)}</td><td class="num">${bal(l.amount)}</td></tr>`).join("")}</tbody>
        <tfoot><tr><td>Credited to ${esc(p.supplier)}</td><td class="num">${money(p.total)} <span class="tag cr">Cr</span></td></tr></tfoot>
      </table></div></section>`;
}

// ---- inventory

async function viewInventory(params) {
  if (needCompany()) return;
  const q = { q: params.get("q") || "", group: params.get("group") || "", status: params.get("status") || "", sort: params.get("sort") || "name_asc",
              page: +params.get("page") || 1, pageSize: +params.get("pageSize") || 50 };
  view.innerHTML = `
    <h1>Inventory <span class="muted small">stock position from Tally</span></h1>
    <div id="kpis" class="grid kpis"></div>
    <div class="panel">
      <div class="toolbar">
        <input type="search" id="q" placeholder="Search item, part no., group…" value="${esc(q.q)}">
        <select id="group"><option value="">All stock groups</option>${q.group ? `<option selected>${esc(q.group)}</option>` : ""}</select>
        <select id="status">${opts([["", "All items"], ["available", "On hand (qty > 0)"], ["low", "Low (at/below reorder level)"], ["zero", "Out of stock"], ["negative", "Negative stock"]], q.status)}</select>
        <select id="sort">${opts([["name_asc", "Name A→Z"], ["value_desc", "Highest value first"], ["qty_desc", "Highest qty first"], ["qty_asc", "Lowest qty first"], ["group_asc", "Stock group"]], q.sort)}</select>
        <span class="spacer"></span>
        <a id="csv"><button>Export CSV</button></a>
        <a id="xlsx"><button>Export Excel</button></a>
      </div>
      <div id="results"><div class="loading">Reading stock items from Tally…</div></div>
    </div>`;
  const load = async () => {
    const p = { q: $("#q").value.trim(), group: $("#group").value, status: $("#status").value, sort: $("#sort").value, page: q.page, pageSize: q.pageSize };
    history.replaceState(null, "", hashWith("#/inventory", { q: p.q, group: p.group, status: p.status, sort: p.sort === "name_asc" ? "" : p.sort, page: q.page > 1 ? q.page : "" }));
    $("#csv").href = exportUrl("inventory", "csv", p);
    $("#xlsx").href = exportUrl("inventory", "xlsx", p);
    let r;
    try { r = await api("/api/inventory", p); } catch (e) { $("#results").innerHTML = errorBox(e); return; }
    const sel = $("#group");
    if (sel.options.length <= 2) {
      const cur = sel.value;
      sel.innerHTML = `<option value="">All stock groups</option>` + r.groups.map((g) => `<option value="${esc(g.group)}" ${g.group === cur ? "selected" : ""}>${esc(g.group)} (${g.items})</option>`).join("");
    }
    const a = r.all, f = r.filtered, filtered = f.items !== a.items;
    $("#kpis").innerHTML = `
      ${kpi("Stock items", a.items, filtered ? `${f.items} match the filters` : "")}
      ${kpi("Stock value", money(a.value), filtered ? `${money(f.value)} for the filtered items` : "At Tally's valuation")}
      ${kpi("On hand", a.inStock + a.low, a.low ? `${a.low} at or below reorder level` : "Items with qty > 0", "cr")}
      ${kpi("Out of stock", a.zero, "Qty zero")}
      ${kpi("Negative stock", a.negative, a.negative ? "Sold more than recorded in stock — check in Tally" : "None", a.negative ? "dr" : "")}`;
    $("#results").innerHTML = `
      <div class="table-wrap"><table>
        <thead><tr><th>Item</th><th>Stock group</th><th class="num">Closing qty</th><th class="num">Rate</th><th class="num">Value</th><th>Status</th></tr></thead>
        <tbody>${r.items.map((it) => `<tr>
          <td><a href="#/inventory/${encodeURIComponent(it.id)}">${esc(it.name)}</a>${it.aliases ? `<div class="small muted">${esc(it.aliases.join(", "))}</div>` : ""}</td>
          <td class="small">${esc(it.group)}</td>
          <td class="num ${it.closingQty < 0 ? "dr" : ""}">${qty(it.closingQty, it.unit)}</td>
          <td class="num">${it.closingRate ? money(it.closingRate) : ""}</td>
          <td class="num">${money(it.closingValue)}</td>
          <td>${stockTag(it.status)}</td>
        </tr>`).join("") || `<tr><td colspan="6" class="empty">No stock items match.</td></tr>`}</tbody>
        <tfoot><tr><td>${f.items} item${f.items === 1 ? "" : "s"}</td><td></td><td class="num">${qtyFmt.format(f.qty)}</td><td></td><td class="num">${money(f.value)}</td><td></td></tr></tfoot>
      </table></div>
      ${pager(r, "item")}`;
    bindPager(q, load);
  };
  const reset = () => { q.page = 1; load(); };
  $("#q").addEventListener("input", debounce(reset));
  for (const id of ["group", "status", "sort"]) $("#" + id).addEventListener("change", reset);
  load();
}

async function viewStockItem(id) {
  if (needCompany()) return;
  view.innerHTML = `<div class="loading">Loading from Tally…</div>`;
  let r;
  try { r = await api(`/api/inventory/${encodeURIComponent(id)}`); } catch (e) { view.innerHTML = `<p><a href="#/inventory">← Inventory</a></p>` + errorBox(e); return; }
  const it = r.item;
  const row = (k, v) => (v || v === 0 ? `<dt>${k}</dt><dd>${v}</dd>` : "");
  view.innerHTML = `
    <p><a href="javascript:history.back()">← Back</a></p>
    <h1>${esc(it.name)} ${stockTag(it.status)}</h1>
    ${it.parseWarnings ? `<div class="alert warn">Some values from Tally could not be read: ${esc(it.parseWarnings.join("; "))}</div>` : ""}
    <div class="grid two">
      <section class="panel"><h2>Item</h2><dl class="kv">
        ${row("Stock group", `<a href="${hashWith("#/inventory", { group: it.group })}">${esc(it.group)}</a>`)}
        ${row("Category", esc(it.category))}
        ${row("Part no. / alias", esc((it.aliases || []).join(", ")))}
        ${row("Unit", esc(it.unit))}
        ${row("GST", it.gstApplicable ? "Applicable" : "Not applicable")}
        ${it.reorderLevel ? row("Reorder level", qty(it.reorderLevel, it.unit)) : ""}
        ${it.minOrderQty ? row("Minimum order", qty(it.minOrderQty, it.unit)) : ""}
      </dl></section>
      <section class="panel"><h2>Stock position <span class="muted small">from Tally · ${fmtTime(r.fetchedAt)}</span></h2><dl class="kv">
        <dt>Opening</dt><dd>${qty(it.openingQty, it.unit)} · ${money(it.openingValue)}</dd>
        <dt>Closing qty</dt><dd style="font-size:18px;font-weight:650" class="${it.closingQty < 0 ? "dr" : ""}">${qty(it.closingQty, it.unit)}</dd>
        <dt>Valuation rate</dt><dd>${it.closingRate ? money(it.closingRate) + (it.unit ? " / " + esc(it.unit) : "") : "—"}</dd>
        <dt>Closing value</dt><dd><strong>${money(it.closingValue)}</strong></dd>
      </dl></section>
    </div>
    <section class="panel" id="hist"><h2>Purchase history</h2><div class="loading">Reading purchase vouchers from Tally…</div></section>`;

  let h;
  try { h = await api(`/api/inventory/${encodeURIComponent(id)}/purchases`); } catch (e) { $("#hist").innerHTML = `<h2>Purchase history</h2>` + errorBox(e); return; }
  $("#hist").innerHTML = `
    <h2>Purchase history <span class="muted small">${h.count} line${h.count === 1 ? "" : "s"}</span></h2>
    ${h.count ? `<div class="grid kpis">${kpi("Purchased", qty(h.qty, it.unit))}${kpi("Amount", money(h.amount), "Taxable value")}${kpi("Average rate", money(h.avgRate))}${kpi("Last rate", money(h.purchases[0].rate), fmtDate(h.purchases[0].date))}</div>` : ""}
    <div class="table-wrap"><table>
      <thead><tr><th>Date</th><th>Voucher no.</th><th>Supplier</th><th class="num">Qty</th><th class="num">Rate</th><th class="num">Amount</th></tr></thead>
      <tbody>${h.purchases.map((x) => `<tr><td>${fmtDate(x.date)}</td><td><a href="#/purchases/${encodeURIComponent(x.purchaseId)}">${esc(x.number)}</a></td><td>${esc(x.supplier)}</td>
        <td class="num">${qty(x.qty, x.unit)}</td><td class="num">${money(x.rate)}</td><td class="num">${money(x.amount)}</td></tr>`).join("") || `<tr><td colspan="6" class="empty">No purchases of this item in the books.</td></tr>`}</tbody>
    </table></div>`;
}

// ------------------------------------------------------------ router

async function route() {
  const [path, qs] = (location.hash.slice(1) || "/dashboard").split("?");
  const params = new URLSearchParams(qs || "");
  const parts = path.split("/").filter(Boolean);
  document.querySelectorAll("nav a").forEach((a) => a.classList.toggle("active", a.dataset.nav === parts[0]));
  window.scrollTo(0, 0);
  if (parts[0] !== "sync") stopSyncPolling();
  switch (parts[0]) {
    case "shops": return parts[1] ? viewShop(decodeURIComponent(parts[1])) : viewShops(params);
    case "outstanding": return viewOutstanding(params);
    case "suppliers": return parts[1] ? viewSupplier(decodeURIComponent(parts[1])) : viewSuppliers(params);
    case "purchases": return parts[1] ? viewPurchase(decodeURIComponent(parts[1])) : viewPurchases(params);
    case "inventory": return parts[1] ? viewStockItem(decodeURIComponent(parts.slice(1).join("/"))) : viewInventory(params);
    case "status": return viewStatus();
    case "sync": return viewSync();
    default: return viewDashboard();
  }
}

// ------------------------------------------------------------ login (whole app)

let loginShown = false;

function setChrome(loggedIn) {
  document.querySelector("nav").style.display = loggedIn ? "" : "none";
  for (const id of ["conn", "company", "refresh", "asof"]) { const el = $("#" + id); if (el) el.style.visibility = loggedIn ? "" : "hidden"; }
  $("#logout").hidden = !loggedIn;
  if (!loggedIn) $("#syncpill").hidden = true;
}

function showLogin(err) {
  if (loginShown) return;
  loginShown = true;
  stopSyncPolling();
  setChrome(false);
  view.innerHTML = `<div class="panel login"><h1>WholeFlow</h1>${err ? errorBox({ message: err }) : ""}
    <form id="loginForm" class="form">
      <label><span class="l">Email</span><input name="email" autocomplete="username" required autofocus></label>
      <label><span class="l">Password</span><input name="password" type="password" autocomplete="current-password" required></label>
      <button class="primary" type="submit">Log in</button>
    </form>
    <p class="small muted">Log in with your WholeFlow account. Without internet, an account that logged in here recently still works for a few days.</p></div>`;
  $("#loginForm").onsubmit = async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    try {
      await syncApi("POST", "/api/sync/login", { email: f.get("email"), password: f.get("password") });
      loginShown = false;
      start();
    } catch (err) { loginShown = false; showLogin(err.message); }
  };
}

$("#logout").onclick = async () => { try { await syncApi("POST", "/api/sync/logout"); } catch {} location.hash = "#/dashboard"; loginShown = false; showLogin(); };

async function start() {
  let session;
  try { session = await syncApi("GET", "/api/sync/session"); }
  catch (e) { view.innerHTML = errorBox(e); return; }
  if (!session.loggedIn) return showLogin();
  setChrome(true);
  await loadStatus();
  await route();
  loadSyncSummary();
}

window.addEventListener("hashchange", () => { if (!loginShown) route(); });
start();
