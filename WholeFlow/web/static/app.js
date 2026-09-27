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
    state.companies.map((c) => `<option ${c.name === state.company ? "selected" : ""}>${esc(c.name)}</option>`).join("");
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
          <tr><td style="width:34%"><a href="#/outstanding?q=${encodeURIComponent(a.area)}&field=area">${esc(a.area)}</a> <span class="muted small">${a.shops} shop${a.shops === 1 ? "" : "s"}</span></td>
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
        <select id="field">${opts([["all", "All fields"], ["name", "Shop name"], ["phone", "Phone"], ["area", "Area / address"]], params.get("field") || "all")}</select>
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
const SYNC_STATE_CLASS = { SYNCED: "ok", CONNECTED: "ok", SYNCING: "warn", NOT_CONFIGURED: "warn", DISABLED: "neutral", PENDING: "neutral" };
const syncCls = (s) => SYNC_STATE_CLASS[s] ?? "bad";
const syncTag = (s) => `<span class="tag ${syncCls(s)}">${esc(s)}</span>`;

async function syncApi(method, path, body) {
  const opts = { method, headers: { "X-Requested-With": "WholeFlowSync" } };
  if (body !== undefined) { opts.headers["Content-Type"] = "application/json"; opts.body = JSON.stringify(body); }
  let res;
  try { res = await fetch(path, opts); }
  catch { throw new ApiError(0, { error: { code: "APP_UNREACHABLE", message: "The application server is not responding. Is it still running?" } }); }
  const data = await res.json().catch(() => null);
  if (res.status === 401 && path !== "/api/sync/login" && path !== "/api/sync/setup") { showLogin(data?.error?.message); throw new ApiError(401, data); }
  if (!res.ok) throw new ApiError(res.status, data);
  return data;
}

// Header pill with the cloud sync state (needs the session like everything else).
async function loadSyncSummary() {
  const pill = $("#syncpill");
  try {
    const s = await syncApi("GET", "/api/sync/summary");
    const last = (s.companies || []).map((c) => c.lastSuccessAt).filter(Boolean).sort().pop();
    pill.textContent = `Cloud sync: ${s.state}${last ? " · " + fmtTime(last) : ""}`;
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
      <section class="panel form"><h2><span class="step">1</span>Business</h2>
        <label><span class="l">Business ID (UUID from the businesses table)</span><input id="bizId" value="${esc(s.business.id)}" placeholder="00000000-0000-0000-0000-000000000000"></label>
        <label><span class="l">Business name (for logs)</span><input id="bizName" value="${esc(s.business.name)}"></label>
        <p class="small muted">Every synchronised record is tagged with this business_id. Create the business row in Supabase first (docs/DATABASE_SCHEMA.md).</p>
      </section>
      <section class="panel form"><h2><span class="step">2</span>Cloud backend</h2>
        <label><span class="l">Provider</span><select id="provider"><option value="supabase" ${s.cloud.provider === "supabase" ? "selected" : ""}>Supabase (PostgreSQL)</option><option value="memory" ${s.cloud.provider === "memory" ? "selected" : ""}>Memory (dry run, nothing leaves this PC)</option></select></label>
        <label><span class="l">Supabase project URL</span><input id="sbUrl" value="${esc(s.cloud.supabaseUrl)}" placeholder="https://xxxx.supabase.co" ${env.includes("SUPABASE_URL") ? "disabled" : ""}></label>
        <label><span class="l">Service-role key ${s.cloud.hasKey ? '<span class="tag ok">stored</span>' : '<span class="tag warn">not set</span>'} ${s.cloud.keyFromEnv ? '<span class="tag neutral">from environment</span>' : ""}</span>
          <input id="sbKey" type="password" autocomplete="off" placeholder="${s.cloud.hasKey ? "leave blank to keep the stored key" : "paste the service_role key"}" ${s.cloud.keyFromEnv ? "disabled" : ""}></label>
        ${s.cloud.keyError ? errorBox({ message: "Stored key cannot be read: " + s.cloud.keyError + " Enter it again." }) : ""}
        <div class="row"><button id="cloudTest">Test cloud connection</button><span id="cloudResult" class="small"></span></div>
        <p class="small muted">The key is encrypted at rest (${esc(sync.status.secretScheme)}) and never shown again. Never put it in the mobile app.</p>
      </section>
    </div>
    <section class="panel"><h2><span class="step">3</span>TallyPrime companies to synchronise</h2>
      <div class="grid two">
        <div><div id="tallyBlock" class="status-block">Checking…</div>
          <div class="row"><button id="tallyTest">Test Tally &amp; discover companies</button></div>
          <p class="small muted">Endpoint ${esc(sync.status.tallyEndpoint)} · port from ${esc(sync.status.portSource)} · shop groups: ${esc((sync.status.shopGroups || []).join(", "))}</p></div>
        <div><p class="small muted">Tick the companies to synchronise. Only ticked companies are ever read.</p><div id="companies"></div></div>
      </div>
    </section>
    <div class="grid two">
      <section class="panel form"><h2><span class="step">4</span>Sync settings</h2>
        <label><span class="l">Sync interval</span><select id="interval">${intervals.map((v) => `<option value="${v}" ${s.sync.intervalSeconds === v ? "selected" : ""}>${v < 3600 ? v / 60 + " min" : "1 hour"}</option>`).join("")}${intervals.includes(s.sync.intervalSeconds) ? "" : `<option value="${s.sync.intervalSeconds}" selected>${s.sync.intervalSeconds} s</option>`}</select></label>
        <label class="check"><input type="checkbox" checked disabled> Shops &amp; current balances (always)</label>
        <label class="check"><input type="checkbox" id="txns" ${s.sync.transactions ? "checked" : ""}> Transactions (vouchers, incremental)</label>
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
      <p class="small muted">These accounts belong to the business (business ID above) and are used in the mobile app, never in this app. Create the owner here; the owner can later add staff from the mobile app, or you can add them here.</p>
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
      <pre class="log" id="log">…</pre></section>
    <section class="panel form"><h2>Admin password <span class="muted small">(unlocks the whole app)</span></h2>
      <form id="pwForm" class="grid two">
        <label><span class="l">Current password</span><input name="current" type="password" autocomplete="current-password" required></label>
        <label><span class="l">Username</span><input name="username" value="${esc(s.developer.Username)}"></label>
        <label><span class="l">New password (min 10 characters)</span><input name="password" type="password" autocomplete="new-password" required minlength="10"></label>
        <div class="row"><button type="submit">Change password</button><span id="pwResult" class="small"></span></div>
      </form></section>`;

  renderSyncStatus();
  renderSyncCompanies(null);
  bindSyncActions();
  loadSyncLog();
  syncTallyTest(false);
  loadUsers();
  sync.timer = setInterval(refreshSyncStatus, 5000);
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
        ${st.configured ? "" : `<dt>Configuration</dt><dd><span class="tag warn">${esc(st.configMessage)}</span></dd>`}
      </dl>
      <div class="table-wrap"><table>
        <thead><tr><th>Company</th><th>Status</th><th>Last successful sync</th><th class="num">Shops</th><th class="num">Transactions</th></tr></thead>
        <tbody>${(st.companies || []).map((c) => `<tr><td>${esc(c.name || c.tallyId)}</td><td>${syncTag(c.status)}${c.lastError ? `<div class="small muted">${esc(c.lastErrorCode)}: ${esc(c.lastError)}</div>` : ""}</td><td>${fmtTime(c.lastSuccessAt)}</td><td class="num">${c.shopCount ?? 0}</td><td class="num">${c.transactionCount ?? 0}</td></tr>`).join("") || `<tr><td colspan="5" class="empty">No company selected yet.</td></tr>`}</tbody>
      </table></div>
    </div>`;
  if ($("#lastRun") && last) {
    $("#lastRun").innerHTML = `<div class="table-wrap"><table><thead><tr><th>Company</th><th>Result</th><th>Mode</th><th class="num">Shops +/~/−</th><th class="num">Txns +/~/−</th><th class="num">Time</th></tr></thead>
      <tbody>${(last.companies || []).map((c) => `<tr><td>${esc(c.name)}</td><td>${syncTag(c.status)}${c.errorCode ? `<div class="small muted">${esc(c.errorCode)}: ${esc(c.errorMessage)}</div>` : ""}</td><td>${esc(c.mode || "")}</td>
        <td class="num">${c.shops.created}/${c.shops.updated}/${c.shops.deleted}</td><td class="num">${c.transactions.created}/${c.transactions.updated}/${c.transactions.deleted}</td><td class="num">${(c.durationMs / 1000).toFixed(1)}s</td></tr>`).join("") || `<tr><td colspan="6" class="empty">${esc(last.status)}${last.errorMessage ? ": " + esc(last.errorMessage) : ""}</td></tr>`}</tbody></table></div>`;
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

function collectSyncSettings() {
  return {
    business: { id: $("#bizId").value, name: $("#bizName").value },
    cloud: { provider: $("#provider").value, supabaseUrl: $("#sbUrl").value, supabaseKey: $("#sbKey").value },
    sync: { enabled: $("#enabled").checked, intervalSeconds: +$("#interval").value, transactions: $("#txns").checked, fullReconcileHours: +$("#reconcile").value },
    companies: [...document.querySelectorAll("input.cmp")].map((el) => ({ tallyId: el.dataset.id, name: el.dataset.name, enabled: el.checked })),
  };
}

function bindSyncActions() {
  $("#tallyTest").onclick = () => syncTallyTest(true);
  $("#cloudTest").onclick = async () => {
    const out = $("#cloudResult"); out.textContent = "Testing…";
    try {
      const r = await syncApi("POST", "/api/sync/cloud/test", { business: { id: $("#bizId").value }, cloud: { provider: $("#provider").value, supabaseUrl: $("#sbUrl").value, supabaseKey: $("#sbKey").value } });
      out.innerHTML = r.ok ? `<span class="tag ok">connected</span> ${esc(r.provider)} · business ${esc(r.businessId)} · ${r.responseMs} ms` : `<span class="tag bad">${esc(r.error.code)}</span> ${esc(r.error.message)}`;
    } catch (e) { out.innerHTML = `<span class="tag bad">error</span> ${esc(e.message)}`; }
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
  $("#pwForm").onsubmit = async (e) => {
    e.preventDefault();
    const f = new FormData(e.target); const out = $("#pwResult");
    try { await syncApi("POST", "/api/sync/password", { current: f.get("current"), username: f.get("username"), password: f.get("password") }); out.innerHTML = `<span class="tag ok">changed</span>`; e.target.reset(); }
    catch (err) { out.innerHTML = `<span class="tag bad">${esc(err.message)}</span>`; }
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
      <label><span class="l">Username</span><input name="username" autocomplete="username" required autofocus></label>
      <label><span class="l">Password</span><input name="password" type="password" autocomplete="current-password" required></label>
      <button class="primary" type="submit">Log in</button>
    </form>
    <p class="small muted">Admin access only. Forgotten password: run <code>wholeflow.exe set-password</code> on this PC.</p></div>`;
  $("#loginForm").onsubmit = async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    try {
      await syncApi("POST", "/api/sync/login", { username: f.get("username"), password: f.get("password") });
      loginShown = false;
      start();
    } catch (err) { loginShown = false; showLogin(err.message); }
  };
}

function showSetupRequired(err) {
  setChrome(false);
  view.innerHTML = `<div class="panel login"><h1>WholeFlow</h1><h2>Welcome — create the admin account</h2>
    <p class="small muted">This is the first run. Choose the username and password that will unlock this app. Only you should know them; the shop owner never uses this app.</p>
    ${err ? errorBox({ message: err }) : ""}
    <form id="setupForm" class="form">
      <label><span class="l">Username</span><input name="username" value="admin" autocomplete="username" required></label>
      <label><span class="l">Password (min 10 characters)</span><input name="password" type="password" autocomplete="new-password" required minlength="10" autofocus></label>
      <label><span class="l">Repeat password</span><input name="confirm" type="password" autocomplete="new-password" required minlength="10"></label>
      <button class="primary" type="submit">Create account and continue</button>
    </form>
    <p class="small muted">Forgotten later? Run <code>wholeflow.exe set-password</code> on this PC to reset it.</p></div>`;
  $("#setupForm").onsubmit = async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    if (f.get("password") !== f.get("confirm")) return showSetupRequired("The two passwords do not match.");
    try {
      await syncApi("POST", "/api/sync/setup", { username: f.get("username"), password: f.get("password"), confirm: f.get("confirm") });
      start();
    } catch (err) { showSetupRequired(err.message); }
  };
}

$("#logout").onclick = async () => { try { await syncApi("POST", "/api/sync/logout"); } catch {} location.hash = "#/dashboard"; loginShown = false; showLogin(); };

async function start() {
  let session;
  try { session = await syncApi("GET", "/api/sync/session"); }
  catch (e) { view.innerHTML = errorBox(e); return; }
  if (session.setupRequired) return showSetupRequired();
  if (!session.loggedIn) return showLogin();
  setChrome(true);
  await loadStatus();
  await route();
  loadSyncSummary();
}

window.addEventListener("hashchange", () => { if (!loginShown) route(); });
start();
