import React, { useState, useEffect, useCallback } from "react";
import { createRoot } from "react-dom/client";

/* ============================================================
   WholesaleTrack — single-file wholesale creditor manager
   React (no build tools) + custom Supabase REST client.
   ============================================================ */

/* ---------- Theme ---------- */
const C = {
  navy: "#0B1D3A",
  navyMid: "#16346A",
  gold: "#D4930A",
  goldLight: "#F5B829",
  white: "#FFFFFF",
  cream: "#F7F8FA",
  ink: "#111827",
  muted: "#9CA3AF",
  border: "#E5E7EB",
  red: "#DC2626",
  green: "#15803D",
};

/* ---------- Helpers ---------- */
const todayISO = () => {
  const d = new Date();
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60000).toISOString().slice(0, 10);
};

const fmtZAR = (n) => {
  const v = Number(n) || 0;
  return (
    "R " +
    v.toLocaleString("en-ZA", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  );
};

const fmtDate = (s) => {
  if (!s) return "";
  const d = new Date(s + "T00:00:00");
  if (isNaN(d)) return s;
  return d.toLocaleDateString("en-ZA", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
};

/* ---------- Custom Supabase REST client (fetch only) ---------- */
function makeSupabase(url, key) {
  const base = url.replace(/\/+$/, "") + "/rest/v1";
  const headers = () => ({
    apikey: key,
    Authorization: "Bearer " + key,
    "Content-Type": "application/json",
  });

  const handle = async (res) => {
    if (!res.ok) {
      let msg = res.status + " " + res.statusText;
      try {
        const body = await res.json();
        if (body && (body.message || body.hint))
          msg = body.message || body.hint;
      } catch (_) {}
      throw new Error(msg);
    }
    if (res.status === 204) return null;
    const txt = await res.text();
    return txt ? JSON.parse(txt) : null;
  };

  return {
    async query(table, opts = {}) {
      const { select = "*", eq = null, order = null } = opts;
      const p = new URLSearchParams();
      p.set("select", select);
      if (eq) for (const [k, v] of Object.entries(eq)) p.append(k, "eq." + v);
      if (order) p.set("order", order);
      const res = await fetch(`${base}/${table}?${p.toString()}`, {
        headers: headers(),
      });
      return handle(res);
    },

    async insert(table, row) {
      const res = await fetch(`${base}/${table}`, {
        method: "POST",
        headers: { ...headers(), Prefer: "return=representation" },
        body: JSON.stringify(row),
      });
      return handle(res);
    },

    async update(table, id, patch) {
      const res = await fetch(`${base}/${table}?id=eq.${id}`, {
        method: "PATCH",
        headers: { ...headers(), Prefer: "return=representation" },
        body: JSON.stringify(patch),
      });
      return handle(res);
    },

    async delete(table, id) {
      const res = await fetch(`${base}/${table}?id=eq.${id}`, {
        method: "DELETE",
        headers: headers(),
      });
      return handle(res);
    },

    async upsert(table, row, onConflict) {
      const q = onConflict
        ? `?on_conflict=${encodeURIComponent(onConflict)}`
        : "";
      const res = await fetch(`${base}/${table}${q}`, {
        method: "POST",
        headers: {
          ...headers(),
          Prefer: "resolution=merge-duplicates,return=representation",
        },
        body: JSON.stringify(row),
      });
      return handle(res);
    },

    async testConnection() {
      const res = await fetch(`${base}/wt_creditors?select=id&limit=1`, {
        headers: headers(),
      });
      if (!res.ok) {
        let msg = "Connection failed (" + res.status + ")";
        try {
          const b = await res.json();
          if (b && b.message) msg = b.message;
        } catch (_) {}
        throw new Error(msg);
      }
      return true;
    },
  };
}

/* ---------- SQL schema shown in setup ---------- */
const SCHEMA_SQL = `create table if not exists wt_creditors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact text,
  address text,
  username text not null unique,
  password text not null,
  created_at timestamptz default now()
);

create table if not exists wt_transactions (
  id uuid primary key default gen_random_uuid(),
  creditor_id uuid references wt_creditors(id) on delete cascade,
  date date not null,
  type text not null check (type in ('invoice','payment')),
  description text not null,
  amount numeric(12,2) not null,
  created_at timestamptz default now()
);

create table if not exists wt_settings (
  key text primary key,
  value text not null
);
insert into wt_settings (key, value) values ('admin_password', '0000')
  on conflict (key) do nothing;
insert into wt_settings (key, value) values ('staff_password', '9999')
  on conflict (key) do nothing;

alter table wt_creditors    enable row level security;
alter table wt_transactions enable row level security;
alter table wt_settings     enable row level security;
create policy "allow_all_creditors"    on wt_creditors    for all using (true) with check (true);
create policy "allow_all_transactions" on wt_transactions for all using (true) with check (true);
create policy "allow_all_settings"     on wt_settings     for all using (true) with check (true);`;

/* ---------- Tiny UI atoms ---------- */
function Spinner({ size = 18, color = C.gold }) {
  return (
    <span
      style={{
        display: "inline-block",
        width: size,
        height: size,
        border: `2.5px solid ${color}33`,
        borderTopColor: color,
        borderRadius: "50%",
        animation: "wt-spin 0.7s linear infinite",
        verticalAlign: "middle",
      }}
    />
  );
}

const card = {
  background: C.white,
  borderRadius: 14,
  border: `1px solid ${C.border}`,
  boxShadow: "0 1px 3px rgba(16,24,40,0.06)",
};

const btn = (kind = "gold") => {
  const map = {
    gold: { bg: C.gold, fg: "#fff" },
    navy: { bg: C.navyMid, fg: "#fff" },
    ghost: { bg: "transparent", fg: C.ink, border: `1px solid ${C.border}` },
    red: { bg: C.red, fg: "#fff" },
    green: { bg: C.green, fg: "#fff" },
  };
  const m = map[kind] || map.gold;
  return {
    background: m.bg,
    color: m.fg,
    border: m.border || "none",
    borderRadius: 9,
    padding: "9px 14px",
    fontWeight: 700,
    fontSize: 13.5,
    cursor: "pointer",
    fontFamily: "inherit",
  };
};

const inputStyle = {
  width: "100%",
  padding: "10px 12px",
  border: `1.5px solid ${C.border}`,
  borderRadius: 8,
  fontSize: 14,
  fontFamily: "inherit",
  outline: "none",
  background: "#fff",
};

function Field({ label, children }) {
  return (
    <label style={{ display: "block", marginBottom: 12 }}>
      <span
        style={{
          display: "block",
          fontSize: 12.5,
          fontWeight: 600,
          color: "#374151",
          marginBottom: 5,
        }}
      >
        {label}
      </span>
      {children}
    </label>
  );
}

function Input(props) {
  const [f, setF] = useState(false);
  return (
    <input
      {...props}
      onFocus={(e) => {
        setF(true);
        props.onFocus && props.onFocus(e);
      }}
      onBlur={(e) => {
        setF(false);
        props.onBlur && props.onBlur(e);
      }}
      style={{
        ...inputStyle,
        borderColor: f ? C.gold : C.border,
        boxShadow: f ? `0 0 0 3px ${C.gold}33` : "none",
        ...(props.style || {}),
      }}
    />
  );
}

function Toasts({ items }) {
  return (
    <div
      style={{
        position: "fixed",
        right: 18,
        bottom: 18,
        display: "flex",
        flexDirection: "column",
        gap: 10,
        zIndex: 9999,
      }}
    >
      {items.map((t) => (
        <div
          key={t.id}
          style={{
            background: t.kind === "error" ? C.red : C.green,
            color: "#fff",
            padding: "12px 16px",
            borderRadius: 10,
            fontSize: 13.5,
            fontWeight: 600,
            boxShadow: "0 6px 18px rgba(0,0,0,0.18)",
            maxWidth: 340,
          }}
        >
          {t.msg}
        </div>
      ))}
    </div>
  );
}

function Modal({ title, onClose, children, footer }) {
  return (
    <div
      onMouseDown={onClose}
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(11,29,58,0.55)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: 16,
        zIndex: 8000,
      }}
    >
      <div
        onMouseDown={(e) => e.stopPropagation()}
        style={{
          ...card,
          width: "100%",
          maxWidth: 480,
          maxHeight: "90vh",
          overflowY: "auto",
        }}
      >
        <div
          style={{
            padding: "16px 20px",
            borderBottom: `1px solid ${C.border}`,
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
          }}
        >
          <h3 style={{ margin: 0, fontSize: 17, color: C.navy }}>{title}</h3>
          <button
            onClick={onClose}
            style={{
              border: "none",
              background: "transparent",
              fontSize: 22,
              cursor: "pointer",
              color: C.muted,
              lineHeight: 1,
            }}
          >
            ×
          </button>
        </div>
        <div style={{ padding: 20 }}>{children}</div>
        {footer && (
          <div
            style={{
              padding: "14px 20px",
              borderTop: `1px solid ${C.border}`,
              display: "flex",
              gap: 10,
              justifyContent: "flex-end",
            }}
          >
            {footer}
          </div>
        )}
      </div>
    </div>
  );
}

/* ---------- Logo ---------- */
function Logo({ light }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
      <div
        style={{
          width: 30,
          height: 30,
          borderRadius: 8,
          background: C.goldLight,
          color: C.navy,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontWeight: 900,
          fontSize: 16,
        }}
      >
        W
      </div>
      <span
        style={{
          fontWeight: 800,
          fontSize: 17,
          color: light ? "#fff" : C.navy,
          letterSpacing: 0.2,
        }}
      >
        Wholesale<span style={{ color: C.goldLight }}>Track</span>
      </span>
    </div>
  );
}

/* ============================================================
   Setup Wizard
   ============================================================ */
function SetupWizard({ onDone, toast }) {
  const [step, setStep] = useState(1);
  const [url, setUrl] = useState("");
  const [key, setKey] = useState("");
  const [testing, setTesting] = useState(false);
  const [err, setErr] = useState("");

  const copySql = async () => {
    try {
      await navigator.clipboard.writeText(SCHEMA_SQL);
      toast("SQL copied to clipboard", "success");
    } catch (_) {
      toast("Could not copy — select manually", "error");
    }
  };

  const connect = async () => {
    setErr("");
    if (!url.trim() || !key.trim()) {
      setErr("Both the Project URL and anon key are required.");
      return;
    }
    setTesting(true);
    try {
      const sb = makeSupabase(url.trim(), key.trim());
      await sb.testConnection();
      localStorage.setItem("wt_url", url.trim());
      localStorage.setItem("wt_key", key.trim());
      toast("Connected to Supabase", "success");
      onDone(url.trim(), key.trim());
    } catch (e) {
      setErr(
        "Connection failed: " +
          e.message +
          ". Check the URL/key and that the SQL ran."
      );
    } finally {
      setTesting(false);
    }
  };

  const StepDot = ({ n }) => (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 8,
        opacity: step >= n ? 1 : 0.45,
      }}
    >
      <div
        style={{
          width: 26,
          height: 26,
          borderRadius: "50%",
          background: step >= n ? C.gold : C.border,
          color: step >= n ? "#fff" : C.muted,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontWeight: 700,
          fontSize: 13,
        }}
      >
        {n}
      </div>
    </div>
  );

  return (
    <div
      style={{
        minHeight: "100%",
        background: C.navy,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: 20,
      }}
    >
      <div style={{ ...card, width: "100%", maxWidth: 640 }}>
        <div
          style={{
            padding: "20px 24px",
            borderBottom: `1px solid ${C.border}`,
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
          }}
        >
          <Logo />
          <span style={{ fontSize: 13, color: C.muted }}>First-time setup</span>
        </div>

        <div
          style={{
            display: "flex",
            gap: 18,
            padding: "16px 24px",
            borderBottom: `1px solid ${C.border}`,
          }}
        >
          <StepDot n={1} />
          <StepDot n={2} />
          <StepDot n={3} />
        </div>

        <div style={{ padding: 24 }}>
          {step === 1 && (
            <div>
              <h2 style={{ marginTop: 0, color: C.navy }}>
                Step 1 — Create a free Supabase project
              </h2>
              <ol style={{ lineHeight: 1.8, color: "#374151", fontSize: 14.5 }}>
                <li>
                  Go to{" "}
                  <a
                    href="https://supabase.com"
                    target="_blank"
                    rel="noreferrer"
                    style={{ color: C.gold, fontWeight: 700 }}
                  >
                    supabase.com
                  </a>{" "}
                  and sign up (free).
                </li>
                <li>Click <b>New Project</b> and pick any name &amp; region.</li>
                <li>Wait ~1 minute for the database to be provisioned.</li>
              </ol>
              <div style={{ display: "flex", justifyContent: "flex-end" }}>
                <button style={btn("gold")} onClick={() => setStep(2)}>
                  Next →
                </button>
              </div>
            </div>
          )}

          {step === 2 && (
            <div>
              <h2 style={{ marginTop: 0, color: C.navy }}>
                Step 2 — Run the database schema
              </h2>
              <p style={{ color: "#374151", fontSize: 14.5 }}>
                Open the <b>SQL Editor</b> in Supabase, paste the script below,
                and click <b>Run</b>.
              </p>
              <div style={{ position: "relative" }}>
                <pre
                  style={{
                    background: C.navy,
                    color: "#D7E3F4",
                    padding: 16,
                    borderRadius: 10,
                    fontSize: 12,
                    overflowX: "auto",
                    maxHeight: 240,
                    margin: 0,
                  }}
                >
                  {SCHEMA_SQL}
                </pre>
                <button
                  onClick={copySql}
                  style={{
                    ...btn("gold"),
                    position: "absolute",
                    top: 10,
                    right: 10,
                    padding: "6px 10px",
                    fontSize: 12,
                  }}
                >
                  Copy
                </button>
              </div>
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  marginTop: 16,
                }}
              >
                <button style={btn("ghost")} onClick={() => setStep(1)}>
                  ← Back
                </button>
                <button style={btn("gold")} onClick={() => setStep(3)}>
                  Next →
                </button>
              </div>
            </div>
          )}

          {step === 3 && (
            <div>
              <h2 style={{ marginTop: 0, color: C.navy }}>
                Step 3 — Connect your project
              </h2>
              <p style={{ color: "#374151", fontSize: 14.5 }}>
                In Supabase go to <b>Project Settings → API</b> and copy the
                values below.
              </p>
              <Field label="Project URL">
                <Input
                  placeholder="https://xxxxx.supabase.co"
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                />
              </Field>
              <Field label="anon public key">
                <Input
                  placeholder="eyJhbGciOi..."
                  value={key}
                  onChange={(e) => setKey(e.target.value)}
                />
              </Field>
              {err && (
                <div
                  style={{
                    background: "#FEF2F2",
                    color: C.red,
                    border: `1px solid ${C.red}44`,
                    borderRadius: 8,
                    padding: "10px 12px",
                    fontSize: 13,
                    marginBottom: 12,
                  }}
                >
                  {err}
                </div>
              )}
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                }}
              >
                <button
                  style={btn("ghost")}
                  onClick={() => setStep(2)}
                  disabled={testing}
                >
                  ← Back
                </button>
                <button
                  style={{ ...btn("gold"), opacity: testing ? 0.7 : 1 }}
                  onClick={connect}
                  disabled={testing}
                >
                  {testing ? (
                    <>
                      <Spinner size={14} color="#fff" /> &nbsp;Testing…
                    </>
                  ) : (
                    "Connect & Launch"
                  )}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   Login Screen
   ============================================================ */
function Login({ sb, onLogin, toast, onReconnect, settings }) {
  const [portal, setPortal] = useState("staff"); // "staff" | "shop"
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");

  const switchPortal = (p) => {
    setPortal(p);
    setErr("");
    setUsername("");
    setPassword("");
  };

  const submitStaff = () => {
    setErr("");
    const u = username.trim();
    const p = password;
    if (u === "admin" && p === (settings.admin_password || "0000")) {
      onLogin({ role: "admin", name: "Administrator" });
    } else if (u === "staff" && p === (settings.staff_password || "9999")) {
      onLogin({ role: "staff", name: "Staff (read-only)" });
    } else {
      setErr("Invalid staff or admin credentials.");
    }
  };

  const submitShop = async () => {
    setErr("");
    const u = username.trim();
    const p = password;
    if (!u || !p) {
      setErr("Enter your shop username and password.");
      return;
    }
    setBusy(true);
    try {
      const rows = await sb.query("wt_creditors", {
        select: "*",
        eq: { username: u, password: p },
      });
      if (rows && rows.length > 0) {
        onLogin({ role: "shop", name: rows[0].name, creditor: rows[0] });
      } else {
        setErr("No shop found with those credentials.");
      }
    } catch (e) {
      toast("Login error: " + e.message, "error");
      setErr("Could not reach the database.");
    } finally {
      setBusy(false);
    }
  };

  const submit = () => (portal === "staff" ? submitStaff() : submitShop());
  const onKey = (e) => {
    if (e.key === "Enter") submit();
  };

  const isShop = portal === "shop";

  const Tab = ({ id, label }) => {
    const on = portal === id;
    return (
      <button
        onClick={() => switchPortal(id)}
        style={{
          flex: 1,
          padding: "11px 8px",
          border: "none",
          cursor: "pointer",
          fontWeight: 700,
          fontSize: 13.5,
          fontFamily: "inherit",
          background: on ? "#fff" : "transparent",
          color: on ? C.navy : C.muted,
          borderBottom: on ? `2.5px solid ${C.gold}` : `2.5px solid transparent`,
        }}
      >
        {label}
      </button>
    );
  };

  return (
    <div
      style={{
        minHeight: "100%",
        background: C.navy,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: 20,
      }}
    >
      <div style={{ ...card, width: "100%", maxWidth: 400, overflow: "hidden" }}>
        <div
          style={{
            padding: "26px 26px 14px",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 6,
          }}
        >
          <Logo />
          <p style={{ color: C.muted, fontSize: 13, margin: "6px 0 0" }}>
            {isShop ? "Shop account login" : "Staff & admin login"}
          </p>
        </div>

        {/* Separate portals */}
        <div
          style={{
            display: "flex",
            borderTop: `1px solid ${C.border}`,
            borderBottom: `1px solid ${C.border}`,
            background: C.cream,
          }}
        >
          <Tab id="staff" label="Staff / Admin" />
          <Tab id="shop" label="Shop Login" />
        </div>

        <div style={{ padding: "18px 26px 24px" }}>
          <Field label={isShop ? "Shop Username" : "Username"}>
            <Input
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              onKeyDown={onKey}
              placeholder={isShop ? "your shop username" : "username"}
              autoComplete="username"
            />
          </Field>

          <Field label="Password">
            <Input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              onKeyDown={onKey}
              placeholder="••••"
              autoComplete="current-password"
            />
          </Field>

          {err && (
            <div
              style={{
                background: "#FEF2F2",
                color: C.red,
                border: `1px solid ${C.red}44`,
                borderRadius: 8,
                padding: "10px 12px",
                fontSize: 13,
                marginBottom: 12,
              }}
            >
              {err}
            </div>
          )}

          <button
            style={{
              ...btn(isShop ? "navy" : "gold"),
              width: "100%",
              padding: "11px",
            }}
            onClick={submit}
            disabled={busy}
          >
            {busy ? (
              <>
                <Spinner size={14} color="#fff" /> &nbsp;Signing in…
              </>
            ) : isShop ? (
              "View My Statement"
            ) : (
              "Sign In"
            )}
          </button>

          <div style={{ textAlign: "center", marginTop: 16 }}>
            <button
              onClick={onReconnect}
              style={{
                background: "none",
                border: "none",
                color: C.muted,
                fontSize: 12,
                cursor: "pointer",
                textDecoration: "underline",
              }}
            >
              Reconnect to Supabase
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   Shared data helpers
   ============================================================ */
function computeBalances(creditors, transactions) {
  const map = {};
  creditors.forEach((c) => (map[c.id] = { invoiced: 0, paid: 0 }));
  transactions.forEach((t) => {
    if (!map[t.creditor_id]) map[t.creditor_id] = { invoiced: 0, paid: 0 };
    if (t.type === "invoice") map[t.creditor_id].invoiced += Number(t.amount);
    else map[t.creditor_id].paid += Number(t.amount);
  });
  Object.keys(map).forEach((k) => {
    map[k].balance = map[k].invoiced - map[k].paid;
  });
  return map;
}

function sortTx(list) {
  return [...list].sort((a, b) => {
    if (a.date !== b.date) return a.date < b.date ? -1 : 1;
    return (a.created_at || "") < (b.created_at || "") ? -1 : 1;
  });
}

/* Aging: apply all payments FIFO to invoices (oldest first) and return the
   date + age (in days) of the oldest invoice still not fully paid. Returns
   null when the shop owes nothing. */
function oldestPending(transactions) {
  const txs = sortTx(transactions);
  const invoices = txs
    .filter((t) => t.type === "invoice")
    .map((t) => ({ date: t.date, remaining: Number(t.amount) }));
  let pool = txs
    .filter((t) => t.type === "payment")
    .reduce((s, t) => s + Number(t.amount), 0);

  for (const inv of invoices) {
    if (pool <= 0) break;
    const applied = Math.min(pool, inv.remaining);
    inv.remaining -= applied;
    pool -= applied;
  }

  const open = invoices.find((inv) => inv.remaining > 0.001);
  if (!open) return null;

  const days = Math.floor(
    (new Date(todayISO()) - new Date(open.date)) / 86400000
  );
  return { date: open.date, days: Math.max(0, days) };
}

function TypeBadge({ type }) {
  const inv = type === "invoice";
  return (
    <span
      style={{
        display: "inline-block",
        padding: "2px 9px",
        borderRadius: 999,
        fontSize: 11.5,
        fontWeight: 700,
        background: inv ? "#FEECEC" : "#E7F4EC",
        color: inv ? C.red : C.green,
      }}
    >
      {inv ? "Invoice" : "Payment"}
    </span>
  );
}

/* ============================================================
   Dashboard (Admin / Staff)
   ============================================================ */
function Dashboard({ sb, user, onLogout, toast, settings, onSettingsChanged }) {
  const isAdmin = user.role === "admin";
  const [creditors, setCreditors] = useState([]);
  const [transactions, setTransactions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [active, setActive] = useState("dashboard"); // "dashboard" | creditorId
  const [sidebarOpen, setSidebarOpen] = useState(false);

  const [shopModal, setShopModal] = useState(null); // {mode:'add'|'edit', data}
  const [txModal, setTxModal] = useState(null); // {creditor_id?}
  const [pwModal, setPwModal] = useState(false);

  const pwKey = isAdmin ? "admin_password" : "staff_password";
  const changeMyPassword = async (newPass) => {
    await sb.upsert("wt_settings", { key: pwKey, value: newPass }, "key");
    toast("Password updated", "success");
    setPwModal(false);
    onSettingsChanged && onSettingsChanged();
  };

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [c, t] = await Promise.all([
        sb.query("wt_creditors", { select: "*", order: "name.asc" }),
        sb.query("wt_transactions", { select: "*", order: "date.desc" }),
      ]);
      setCreditors(c || []);
      setTransactions(t || []);
    } catch (e) {
      toast("Failed to load data: " + e.message, "error");
    } finally {
      setLoading(false);
    }
  }, [sb, toast]);

  useEffect(() => {
    load();
  }, [load]);

  const balances = computeBalances(creditors, transactions);

  const totalOwed = Object.values(balances).reduce(
    (s, b) => s + Math.max(0, b.balance),
    0
  );
  const shopsWithBalance = Object.values(balances).filter(
    (b) => b.balance > 0.001
  ).length;

  /* ----- mutations ----- */
  const saveShop = async (form, mode, id) => {
    try {
      if (mode === "add") {
        await sb.insert("wt_creditors", form);
        toast("Shop added", "success");
      } else {
        await sb.update("wt_creditors", id, form);
        toast("Shop updated", "success");
      }
      setShopModal(null);
      await load();
    } catch (e) {
      toast("Save failed: " + e.message, "error");
    }
  };

  const deleteShop = async (c) => {
    if (
      !window.confirm(
        `Delete "${c.name}" and ALL its transactions? This cannot be undone.`
      )
    )
      return;
    try {
      await sb.delete("wt_creditors", c.id);
      toast("Shop deleted", "success");
      if (active === c.id) setActive("dashboard");
      await load();
    } catch (e) {
      toast("Delete failed: " + e.message, "error");
    }
  };

  const saveTx = async (form) => {
    try {
      await sb.insert("wt_transactions", form);
      toast("Transaction added", "success");
      setTxModal(null);
      await load();
    } catch (e) {
      toast("Save failed: " + e.message, "error");
    }
  };

  const deleteTx = async (t) => {
    if (!window.confirm("Delete this transaction? This cannot be undone."))
      return;
    try {
      await sb.delete("wt_transactions", t.id);
      toast("Transaction deleted", "success");
      await load();
    } catch (e) {
      toast("Delete failed: " + e.message, "error");
    }
  };

  const creditorName = (id) =>
    (creditors.find((c) => c.id === id) || {}).name || "—";

  /* ----- UI pieces ----- */
  const RoleBadge = (
    <span
      style={{
        padding: "3px 10px",
        borderRadius: 999,
        background: isAdmin ? C.gold : C.navyMid,
        color: "#fff",
        fontSize: 11.5,
        fontWeight: 700,
        textTransform: "uppercase",
        letterSpacing: 0.5,
      }}
    >
      {user.role}
    </span>
  );

  const StatCard = ({ label, value, color }) => (
    <div style={{ ...card, padding: 18, flex: "1 1 160px", minWidth: 150 }}>
      <div style={{ fontSize: 12.5, color: C.muted, fontWeight: 600 }}>
        {label}
      </div>
      <div
        style={{
          fontSize: 24,
          fontWeight: 800,
          color: color || C.navy,
          marginTop: 6,
        }}
      >
        {value}
      </div>
    </div>
  );

  const activeCreditor =
    active !== "dashboard" ? creditors.find((c) => c.id === active) : null;

  return (
    <div style={{ minHeight: "100%", display: "flex", flexDirection: "column" }}>
      {/* Top nav */}
      <div
        style={{
          background: C.navy,
          color: "#fff",
          padding: "0 16px",
          height: 58,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          position: "sticky",
          top: 0,
          zIndex: 50,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <button
            onClick={() => setSidebarOpen((s) => !s)}
            className="wt-burger"
            style={{
              background: "transparent",
              border: "none",
              color: "#fff",
              fontSize: 22,
              cursor: "pointer",
              display: "none",
            }}
          >
            ☰
          </button>
          <Logo light />
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          {RoleBadge}
          {isAdmin && (
            <>
              <button style={btn("navy")} onClick={() => setTxModal({})}>
                + Txn
              </button>
              <button
                style={btn("gold")}
                onClick={() => setShopModal({ mode: "add", data: null })}
              >
                + Shop
              </button>
            </>
          )}
          <button style={btn("ghost")} onClick={() => setPwModal(true)}>
            <span style={{ color: "#fff" }}>Password</span>
          </button>
          <button style={btn("ghost")} onClick={onLogout}>
            <span style={{ color: "#fff" }}>Logout</span>
          </button>
        </div>
      </div>

      <div style={{ display: "flex", flex: 1, minHeight: 0 }}>
        {/* Sidebar */}
        <div
          className={"wt-sidebar" + (sidebarOpen ? " wt-open" : "")}
          style={{
            width: 256,
            background: "#fff",
            borderRight: `1px solid ${C.border}`,
            padding: 12,
            overflowY: "auto",
          }}
        >
          <button
            onClick={() => {
              setActive("dashboard");
              setSidebarOpen(false);
            }}
            style={{
              width: "100%",
              textAlign: "left",
              padding: "10px 12px",
              borderRadius: 9,
              border: "none",
              cursor: "pointer",
              fontWeight: 700,
              fontSize: 14,
              marginBottom: 8,
              background: active === "dashboard" ? C.gold : "transparent",
              color: active === "dashboard" ? "#fff" : C.ink,
            }}
          >
            ▦ Dashboard
          </button>

          <div
            style={{
              fontSize: 11,
              fontWeight: 700,
              color: C.muted,
              textTransform: "uppercase",
              letterSpacing: 0.6,
              padding: "8px 12px 4px",
            }}
          >
            Shops ({creditors.length})
          </div>

          {creditors.map((c) => {
            const b = balances[c.id] || { balance: 0 };
            const owes = b.balance > 0.001;
            const isActive = active === c.id;
            return (
              <button
                key={c.id}
                onClick={() => {
                  setActive(c.id);
                  setSidebarOpen(false);
                }}
                style={{
                  width: "100%",
                  textAlign: "left",
                  padding: "9px 12px",
                  borderRadius: 9,
                  border: "none",
                  cursor: "pointer",
                  marginBottom: 4,
                  background: isActive ? C.gold : "transparent",
                  color: isActive ? "#fff" : C.ink,
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  gap: 8,
                }}
              >
                <span
                  style={{
                    fontWeight: 600,
                    fontSize: 13.5,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                >
                  {c.name}
                </span>
                <span
                  style={{
                    fontSize: 12,
                    fontWeight: 700,
                    color: isActive ? "#fff" : owes ? C.red : C.green,
                    whiteSpace: "nowrap",
                  }}
                >
                  {fmtZAR(b.balance)}
                </span>
              </button>
            );
          })}
        </div>

        {/* Overlay for mobile sidebar */}
        {sidebarOpen && (
          <div
            className="wt-overlay"
            onClick={() => setSidebarOpen(false)}
            style={{
              position: "fixed",
              inset: 0,
              background: "rgba(0,0,0,0.35)",
              zIndex: 40,
            }}
          />
        )}

        {/* Main content */}
        <div
          style={{
            flex: 1,
            padding: 20,
            overflowY: "auto",
            background: C.cream,
          }}
        >
          {loading ? (
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                color: C.muted,
                padding: 40,
              }}
            >
              <Spinner /> Loading data…
            </div>
          ) : active === "dashboard" ? (
            <DashboardOverview
              creditors={creditors}
              transactions={transactions}
              balances={balances}
              StatCard={StatCard}
              totalOwed={totalOwed}
              shopsWithBalance={shopsWithBalance}
              isAdmin={isAdmin}
              creditorName={creditorName}
              onView={(id) => setActive(id)}
              onEdit={(c) => setShopModal({ mode: "edit", data: c })}
              onDelete={deleteShop}
              onDeleteTx={deleteTx}
            />
          ) : activeCreditor ? (
            <ShopTab
              creditor={activeCreditor}
              transactions={transactions.filter(
                (t) => t.creditor_id === activeCreditor.id
              )}
              isAdmin={isAdmin}
              onAddTx={() => setTxModal({ creditor_id: activeCreditor.id })}
              onDeleteTx={deleteTx}
            />
          ) : (
            <div style={{ color: C.muted }}>Shop not found.</div>
          )}
        </div>
      </div>

      {shopModal && (
        <ShopModal
          mode={shopModal.mode}
          data={shopModal.data}
          onClose={() => setShopModal(null)}
          onSave={saveShop}
        />
      )}
      {txModal && (
        <TxModal
          creditors={creditors}
          presetCreditor={txModal.creditor_id}
          onClose={() => setTxModal(null)}
          onSave={saveTx}
        />
      )}
      {pwModal && (
        <ChangePasswordModal
          title={`Change ${isAdmin ? "Admin" : "Staff"} Password`}
          verify={(cur) => cur === (settings[pwKey] || (isAdmin ? "0000" : "9999"))}
          onSave={changeMyPassword}
          onClose={() => setPwModal(false)}
        />
      )}
    </div>
  );
}

function DashboardOverview({
  creditors,
  transactions,
  balances,
  StatCard,
  totalOwed,
  shopsWithBalance,
  isAdmin,
  creditorName,
  onView,
  onEdit,
  onDelete,
  onDeleteTx,
}) {
  const recent = [...transactions]
    .sort((a, b) => (a.created_at < b.created_at ? 1 : -1))
    .slice(0, 15);

  const [overdueDays, setOverdueDays] = useState(30);
  const overdueShops = creditors
    .map((c) => {
      const aging = oldestPending(
        transactions.filter((t) => t.creditor_id === c.id)
      );
      return aging
        ? {
            creditor: c,
            balance: (balances[c.id] || { balance: 0 }).balance,
            ...aging,
          }
        : null;
    })
    .filter((x) => x && x.days > Number(overdueDays))
    .sort((a, b) => b.days - a.days);

  const th = {
    textAlign: "left",
    padding: "10px 12px",
    fontSize: 12,
    color: C.muted,
    fontWeight: 700,
    textTransform: "uppercase",
    letterSpacing: 0.4,
    borderBottom: `2px solid ${C.border}`,
    whiteSpace: "nowrap",
  };
  const td = {
    padding: "11px 12px",
    fontSize: 13.5,
    borderBottom: `1px solid ${C.border}`,
  };

  return (
    <div>
      <h1 style={{ margin: "0 0 16px", color: C.navy, fontSize: 22 }}>
        Dashboard
      </h1>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 14, marginBottom: 22 }}>
        <StatCard label="Total Shops" value={creditors.length} />
        <StatCard label="Total Owed" value={fmtZAR(totalOwed)} color={C.red} />
        <StatCard label="Shops With Balance" value={shopsWithBalance} />
        <StatCard label="Total Transactions" value={transactions.length} />
      </div>

      {/* Overdue shops (admin only) */}
      {isAdmin && (
        <div style={{ ...card, marginBottom: 22, overflow: "hidden" }}>
          <div
            style={{
              padding: "14px 16px",
              borderBottom: `1px solid ${C.border}`,
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              flexWrap: "wrap",
              gap: 10,
            }}
          >
            <div style={{ fontWeight: 800, color: C.navy }}>
              Overdue Shops
              <span
                style={{
                  marginLeft: 8,
                  padding: "2px 9px",
                  borderRadius: 999,
                  fontSize: 12,
                  fontWeight: 700,
                  background: overdueShops.length ? "#FEECEC" : "#E7F4EC",
                  color: overdueShops.length ? C.red : C.green,
                }}
              >
                {overdueShops.length}
              </span>
            </div>
            <div
              style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 13 }}
            >
              <span style={{ color: C.muted, fontWeight: 600 }}>Pending more than</span>
              <input
                type="number"
                min="0"
                value={overdueDays}
                onChange={(e) => setOverdueDays(e.target.value)}
                style={{
                  ...inputStyle,
                  width: 72,
                  padding: "6px 8px",
                  textAlign: "center",
                }}
              />
              <span style={{ color: C.muted, fontWeight: 600 }}>days</span>
            </div>
          </div>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr>
                  <th style={th}>Name</th>
                  <th style={th}>Oldest Unpaid</th>
                  <th style={{ ...th, textAlign: "right" }}>Days Pending</th>
                  <th style={{ ...th, textAlign: "right" }}>Balance</th>
                  <th style={th}></th>
                </tr>
              </thead>
              <tbody>
                {overdueShops.length === 0 && (
                  <tr>
                    <td style={{ ...td, color: C.muted }} colSpan={5}>
                      No shops have a balance pending more than {overdueDays} days.
                    </td>
                  </tr>
                )}
                {overdueShops.map((o) => (
                  <tr key={o.creditor.id}>
                    <td style={{ ...td, fontWeight: 700 }}>{o.creditor.name}</td>
                    <td style={{ ...td, whiteSpace: "nowrap" }}>{fmtDate(o.date)}</td>
                    <td
                      style={{
                        ...td,
                        textAlign: "right",
                        fontWeight: 800,
                        color: C.red,
                      }}
                    >
                      {o.days} days
                    </td>
                    <td
                      style={{
                        ...td,
                        textAlign: "right",
                        fontWeight: 700,
                        color: C.red,
                      }}
                    >
                      {fmtZAR(o.balance)}
                    </td>
                    <td style={{ ...td, textAlign: "right" }}>
                      <button
                        style={{ ...btn("ghost"), padding: "5px 10px", fontSize: 12 }}
                        onClick={() => onView(o.creditor.id)}
                      >
                        View
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* All shops */}
      <div style={{ ...card, marginBottom: 22, overflow: "hidden" }}>
        <div
          style={{
            padding: "14px 16px",
            borderBottom: `1px solid ${C.border}`,
            fontWeight: 800,
            color: C.navy,
          }}
        >
          All Shops
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr>
                <th style={th}>Name</th>
                <th style={th}>Contact</th>
                <th style={th}>Balance</th>
                {isAdmin && <th style={th}>Credentials</th>}
                <th style={th}>Manage</th>
              </tr>
            </thead>
            <tbody>
              {creditors.length === 0 && (
                <tr>
                  <td style={{ ...td, color: C.muted }} colSpan={isAdmin ? 5 : 4}>
                    No shops yet.
                  </td>
                </tr>
              )}
              {creditors.map((c) => {
                const b = balances[c.id] || { balance: 0 };
                const owes = b.balance > 0.001;
                return (
                  <tr key={c.id}>
                    <td style={{ ...td, fontWeight: 700 }}>{c.name}</td>
                    <td style={{ ...td, color: "#374151" }}>{c.contact || "—"}</td>
                    <td
                      style={{
                        ...td,
                        fontWeight: 700,
                        color: owes ? C.red : C.green,
                      }}
                    >
                      {fmtZAR(b.balance)}
                    </td>
                    {isAdmin && (
                      <td style={{ ...td, fontSize: 12.5, color: "#374151" }}>
                        <code
                          style={{
                            background: C.cream,
                            padding: "2px 6px",
                            borderRadius: 5,
                          }}
                        >
                          {c.username} / {c.password}
                        </code>
                      </td>
                    )}
                    <td style={td}>
                      <div style={{ display: "flex", gap: 6 }}>
                        <button
                          style={{ ...btn("ghost"), padding: "5px 10px", fontSize: 12 }}
                          onClick={() => onView(c.id)}
                        >
                          View
                        </button>
                        {isAdmin && (
                          <>
                            <button
                              style={{
                                ...btn("navy"),
                                padding: "5px 10px",
                                fontSize: 12,
                              }}
                              onClick={() => onEdit(c)}
                            >
                              Edit
                            </button>
                            <button
                              style={{
                                ...btn("red"),
                                padding: "5px 10px",
                                fontSize: 12,
                              }}
                              onClick={() => onDelete(c)}
                            >
                              Delete
                            </button>
                          </>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Recent transactions */}
      <div style={{ ...card, overflow: "hidden" }}>
        <div
          style={{
            padding: "14px 16px",
            borderBottom: `1px solid ${C.border}`,
            fontWeight: 800,
            color: C.navy,
          }}
        >
          Recent Transactions
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr>
                <th style={th}>Date</th>
                <th style={th}>Shop</th>
                <th style={th}>Description</th>
                <th style={th}>Type</th>
                <th style={{ ...th, textAlign: "right" }}>Amount</th>
                {isAdmin && <th style={th}></th>}
              </tr>
            </thead>
            <tbody>
              {recent.length === 0 && (
                <tr>
                  <td style={{ ...td, color: C.muted }} colSpan={isAdmin ? 6 : 5}>
                    No transactions yet.
                  </td>
                </tr>
              )}
              {recent.map((t) => (
                <tr key={t.id}>
                  <td style={{ ...td, whiteSpace: "nowrap" }}>{fmtDate(t.date)}</td>
                  <td style={{ ...td, fontWeight: 600 }}>
                    {creditorName(t.creditor_id)}
                  </td>
                  <td style={td}>{t.description}</td>
                  <td style={td}>
                    <TypeBadge type={t.type} />
                  </td>
                  <td
                    style={{
                      ...td,
                      textAlign: "right",
                      fontWeight: 700,
                      color: t.type === "invoice" ? C.red : C.green,
                    }}
                  >
                    {fmtZAR(t.amount)}
                  </td>
                  {isAdmin && (
                    <td style={{ ...td, textAlign: "right" }}>
                      <button
                        style={{ ...btn("red"), padding: "4px 9px", fontSize: 12 }}
                        onClick={() => onDeleteTx(t)}
                      >
                        Delete
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

function ShopTab({ creditor, transactions, isAdmin, onAddTx, onDeleteTx }) {
  const sorted = sortTx(transactions);
  const invoiced = transactions
    .filter((t) => t.type === "invoice")
    .reduce((s, t) => s + Number(t.amount), 0);
  const paid = transactions
    .filter((t) => t.type === "payment")
    .reduce((s, t) => s + Number(t.amount), 0);
  const balance = invoiced - paid;
  const owes = balance > 0.001;

  const th = {
    textAlign: "left",
    padding: "10px 12px",
    fontSize: 12,
    color: C.muted,
    fontWeight: 700,
    textTransform: "uppercase",
    letterSpacing: 0.4,
    borderBottom: `2px solid ${C.border}`,
    whiteSpace: "nowrap",
  };
  const td = {
    padding: "11px 12px",
    fontSize: 13.5,
    borderBottom: `1px solid ${C.border}`,
  };

  const Stat = ({ label, value, color }) => (
    <div style={{ ...card, padding: 18, flex: "1 1 160px", minWidth: 150 }}>
      <div style={{ fontSize: 12.5, color: C.muted, fontWeight: 600 }}>{label}</div>
      <div style={{ fontSize: 22, fontWeight: 800, color, marginTop: 6 }}>
        {value}
      </div>
    </div>
  );

  return (
    <div>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          flexWrap: "wrap",
          gap: 10,
          marginBottom: 16,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <h1 style={{ margin: 0, color: C.navy, fontSize: 22 }}>{creditor.name}</h1>
          <span
            style={{
              padding: "4px 12px",
              borderRadius: 999,
              fontSize: 12.5,
              fontWeight: 700,
              background: owes ? "#FEECEC" : "#E7F4EC",
              color: owes ? C.red : C.green,
            }}
          >
            {owes ? "Owes" : "Settled"}
          </span>
        </div>
        {isAdmin && (
          <button style={btn("gold")} onClick={onAddTx}>
            + Add Transaction
          </button>
        )}
      </div>

      <div style={{ display: "flex", flexWrap: "wrap", gap: 14, marginBottom: 22 }}>
        <Stat label="Total Invoiced" value={fmtZAR(invoiced)} color={C.red} />
        <Stat label="Total Paid" value={fmtZAR(paid)} color={C.green} />
        <Stat
          label="Balance Due"
          value={fmtZAR(balance)}
          color={owes ? C.red : C.green}
        />
      </div>

      <div style={{ ...card, overflow: "hidden" }}>
        <div
          style={{
            padding: "14px 16px",
            borderBottom: `1px solid ${C.border}`,
            fontWeight: 800,
            color: C.navy,
          }}
        >
          Transactions
        </div>
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr>
                <th style={th}>Date</th>
                <th style={th}>Description</th>
                <th style={{ ...th, textAlign: "right" }}>Invoice</th>
                <th style={{ ...th, textAlign: "right" }}>Payment</th>
                {isAdmin && <th style={th}></th>}
              </tr>
            </thead>
            <tbody>
              {sorted.length === 0 && (
                <tr>
                  <td style={{ ...td, color: C.muted }} colSpan={isAdmin ? 5 : 4}>
                    No transactions for this shop yet.
                  </td>
                </tr>
              )}
              {sorted.map((t) => (
                <tr key={t.id}>
                  <td style={{ ...td, whiteSpace: "nowrap" }}>{fmtDate(t.date)}</td>
                  <td style={td}>{t.description}</td>
                  <td
                    style={{
                      ...td,
                      textAlign: "right",
                      color: C.red,
                      fontWeight: 700,
                    }}
                  >
                    {t.type === "invoice" ? fmtZAR(t.amount) : "—"}
                  </td>
                  <td
                    style={{
                      ...td,
                      textAlign: "right",
                      color: C.green,
                      fontWeight: 700,
                    }}
                  >
                    {t.type === "payment" ? fmtZAR(t.amount) : "—"}
                  </td>
                  {isAdmin && (
                    <td style={{ ...td, textAlign: "right" }}>
                      <button
                        style={{ ...btn("red"), padding: "4px 9px", fontSize: 12 }}
                        onClick={() => onDeleteTx(t)}
                      >
                        Delete
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

/* ---------- Shop add/edit modal ---------- */
function ShopModal({ mode, data, onClose, onSave }) {
  const [form, setForm] = useState({
    name: data?.name || "",
    contact: data?.contact || "",
    address: data?.address || "",
    username: data?.username || "",
    password: data?.password || "",
  });
  const [busy, setBusy] = useState(false);
  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }));

  const submit = async () => {
    if (!form.name.trim() || !form.username.trim() || !form.password.trim()) {
      alert("Name, username and password are required.");
      return;
    }
    setBusy(true);
    await onSave(
      {
        name: form.name.trim(),
        contact: form.contact.trim() || null,
        address: form.address.trim() || null,
        username: form.username.trim(),
        password: form.password,
      },
      mode,
      data?.id
    );
    setBusy(false);
  };

  return (
    <Modal
      title={mode === "add" ? "Add Shop" : "Edit Shop"}
      onClose={onClose}
      footer={
        <>
          <button style={btn("ghost")} onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button style={btn("gold")} onClick={submit} disabled={busy}>
            {busy ? <Spinner size={14} color="#fff" /> : "Save"}
          </button>
        </>
      }
    >
      <Field label="Shop Name *">
        <Input value={form.name} onChange={set("name")} />
      </Field>
      <Field label="Contact">
        <Input value={form.contact} onChange={set("contact")} placeholder="Phone / email" />
      </Field>
      <Field label="Address">
        <Input value={form.address} onChange={set("address")} />
      </Field>
      <Field label="Username *">
        <Input value={form.username} onChange={set("username")} />
      </Field>
      <Field label="Password *">
        <Input value={form.password} onChange={set("password")} />
      </Field>
    </Modal>
  );
}

/* ---------- Transaction add modal ---------- */
function TxModal({ creditors, presetCreditor, onClose, onSave }) {
  const [form, setForm] = useState({
    creditor_id: presetCreditor || (creditors[0] ? creditors[0].id : ""),
    type: "invoice",
    date: todayISO(),
    description: "",
    amount: "",
  });
  const [busy, setBusy] = useState(false);
  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }));

  const submit = async () => {
    if (!form.creditor_id) {
      alert("Select a shop.");
      return;
    }
    if (!form.description.trim()) {
      alert("Description is required.");
      return;
    }
    const amt = Number(form.amount);
    if (!amt || amt <= 0) {
      alert("Enter a valid amount greater than zero.");
      return;
    }
    setBusy(true);
    await onSave({
      creditor_id: form.creditor_id,
      type: form.type,
      date: form.date,
      description: form.description.trim(),
      amount: amt,
    });
    setBusy(false);
  };

  return (
    <Modal
      title="Add Transaction"
      onClose={onClose}
      footer={
        <>
          <button style={btn("ghost")} onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button style={btn("gold")} onClick={submit} disabled={busy}>
            {busy ? <Spinner size={14} color="#fff" /> : "Save"}
          </button>
        </>
      }
    >
      <Field label="Shop *">
        <select
          value={form.creditor_id}
          onChange={set("creditor_id")}
          style={{ ...inputStyle, appearance: "auto" }}
        >
          {creditors.length === 0 && <option value="">No shops available</option>}
          {creditors.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </Field>
      <Field label="Type *">
        <select
          value={form.type}
          onChange={set("type")}
          style={{ ...inputStyle, appearance: "auto" }}
        >
          <option value="invoice">Invoice (delivery — increases balance)</option>
          <option value="payment">Payment (received — reduces balance)</option>
        </select>
      </Field>
      <Field label="Date *">
        <Input type="date" value={form.date} onChange={set("date")} />
      </Field>
      <Field label="Description *">
        <Input
          value={form.description}
          onChange={set("description")}
          placeholder="e.g. Delivery #102 / Cash payment"
        />
      </Field>
      <Field label="Amount (R) *">
        <Input
          type="number"
          min="0"
          step="0.01"
          value={form.amount}
          onChange={set("amount")}
          placeholder="0.00"
        />
      </Field>
    </Modal>
  );
}

/* ---------- Change password modal (shared by all roles) ---------- */
function ChangePasswordModal({ title, verify, onSave, onClose }) {
  const [cur, setCur] = useState("");
  const [n1, setN1] = useState("");
  const [n2, setN2] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");

  const submit = async () => {
    setErr("");
    if (!verify(cur)) {
      setErr("Current password is incorrect.");
      return;
    }
    if (n1.length < 4) {
      setErr("New password must be at least 4 characters.");
      return;
    }
    if (n1 !== n2) {
      setErr("New passwords do not match.");
      return;
    }
    setBusy(true);
    try {
      await onSave(n1);
    } catch (e) {
      setErr("Could not update password: " + e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal
      title={title || "Change Password"}
      onClose={onClose}
      footer={
        <>
          <button style={btn("ghost")} onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button style={btn("gold")} onClick={submit} disabled={busy}>
            {busy ? <Spinner size={14} color="#fff" /> : "Update Password"}
          </button>
        </>
      }
    >
      <Field label="Current Password">
        <Input
          type="password"
          value={cur}
          onChange={(e) => setCur(e.target.value)}
        />
      </Field>
      <Field label="New Password">
        <Input
          type="password"
          value={n1}
          onChange={(e) => setN1(e.target.value)}
        />
      </Field>
      <Field label="Confirm New Password">
        <Input
          type="password"
          value={n2}
          onChange={(e) => setN2(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && submit()}
        />
      </Field>
      {err && (
        <div
          style={{
            background: "#FEF2F2",
            color: C.red,
            border: `1px solid ${C.red}44`,
            borderRadius: 8,
            padding: "10px 12px",
            fontSize: 13,
          }}
        >
          {err}
        </div>
      )}
    </Modal>
  );
}

/* ============================================================
   Shop Statement View (creditor login)
   ============================================================ */
function ShopStatement({ sb, user, onLogout, toast }) {
  const creditor = user.creditor;
  const [transactions, setTransactions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [pwModal, setPwModal] = useState(false);
  const [currentPass, setCurrentPass] = useState(creditor.password);

  const changePassword = async (newPass) => {
    await sb.update("wt_creditors", creditor.id, { password: newPass });
    setCurrentPass(newPass);
    creditor.password = newPass;
    toast("Password updated", "success");
    setPwModal(false);
  };

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const t = await sb.query("wt_transactions", {
        select: "*",
        eq: { creditor_id: creditor.id },
        order: "date.asc",
      });
      setTransactions(t || []);
    } catch (e) {
      toast("Failed to load statement: " + e.message, "error");
    } finally {
      setLoading(false);
    }
  }, [sb, creditor.id, toast]);

  useEffect(() => {
    load();
  }, [load]);

  const sorted = sortTx(transactions);
  let running = 0;
  const rows = sorted.map((t) => {
    if (t.type === "invoice") running += Number(t.amount);
    else running -= Number(t.amount);
    return { ...t, running };
  });
  const balance = running;
  const owes = balance > 0.001;

  const th = {
    textAlign: "left",
    padding: "11px 12px",
    fontSize: 12,
    color: C.muted,
    fontWeight: 700,
    textTransform: "uppercase",
    letterSpacing: 0.4,
    borderBottom: `2px solid ${C.border}`,
    whiteSpace: "nowrap",
  };
  const td = {
    padding: "11px 12px",
    fontSize: 13.5,
    borderBottom: `1px solid ${C.border}`,
  };

  return (
    <div style={{ minHeight: "100%", display: "flex", flexDirection: "column" }}>
      <div
        style={{
          background: C.navy,
          color: "#fff",
          height: 58,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "0 18px",
        }}
      >
        <Logo light />
        <div style={{ display: "flex", gap: 10 }}>
          <button style={btn("ghost")} onClick={() => setPwModal(true)}>
            <span style={{ color: "#fff" }}>Password</span>
          </button>
          <button style={btn("ghost")} onClick={onLogout}>
            <span style={{ color: "#fff" }}>Logout</span>
          </button>
        </div>
      </div>

      {pwModal && (
        <ChangePasswordModal
          title="Change Password"
          verify={(cur) => cur === currentPass}
          onSave={changePassword}
          onClose={() => setPwModal(false)}
        />
      )}

      <div
        style={{
          flex: 1,
          overflowY: "auto",
          padding: 20,
          display: "flex",
          justifyContent: "center",
        }}
      >
        <div style={{ width: "100%", maxWidth: 860 }}>
          {/* Header card */}
          <div
            style={{
              background: C.navy,
              color: "#fff",
              borderRadius: 14,
              padding: 24,
              marginBottom: 20,
              display: "flex",
              justifyContent: "space-between",
              flexWrap: "wrap",
              gap: 16,
            }}
          >
            <div>
              <div style={{ fontSize: 12, color: C.goldLight, fontWeight: 700, letterSpacing: 0.5 }}>
                ACCOUNT STATEMENT
              </div>
              <div style={{ fontSize: 24, fontWeight: 800, marginTop: 4 }}>
                {creditor.name}
              </div>
              {creditor.address && (
                <div style={{ fontSize: 13, color: "#C7D2E4", marginTop: 4 }}>
                  {creditor.address}
                </div>
              )}
              <div style={{ fontSize: 13, color: "#C7D2E4", marginTop: 8 }}>
                {transactions.length} transaction
                {transactions.length === 1 ? "" : "s"}
              </div>
            </div>
            <div style={{ textAlign: "right" }}>
              <div style={{ fontSize: 12, color: "#C7D2E4", fontWeight: 600 }}>
                Balance Due
              </div>
              <div
                style={{
                  fontSize: 30,
                  fontWeight: 900,
                  color: owes ? "#FCA5A5" : "#86EFAC",
                  marginTop: 4,
                }}
              >
                {fmtZAR(balance)}
              </div>
            </div>
          </div>

          {loading ? (
            <div
              style={{
                display: "flex",
                gap: 10,
                color: C.muted,
                padding: 30,
                justifyContent: "center",
              }}
            >
              <Spinner /> Loading statement…
            </div>
          ) : (
            <>
              <div style={{ ...card, overflow: "hidden" }}>
                <div style={{ overflowX: "auto" }}>
                  <table style={{ width: "100%", borderCollapse: "collapse" }}>
                    <thead>
                      <tr>
                        <th style={th}>Date</th>
                        <th style={th}>Description</th>
                        <th style={{ ...th, textAlign: "right" }}>Invoice</th>
                        <th style={{ ...th, textAlign: "right" }}>Payment</th>
                        <th style={{ ...th, textAlign: "right" }}>Balance</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.length === 0 && (
                        <tr>
                          <td style={{ ...td, color: C.muted }} colSpan={5}>
                            No transactions on record yet.
                          </td>
                        </tr>
                      )}
                      {rows.map((t) => (
                        <tr key={t.id}>
                          <td style={{ ...td, whiteSpace: "nowrap" }}>
                            {fmtDate(t.date)}
                          </td>
                          <td style={td}>{t.description}</td>
                          <td
                            style={{
                              ...td,
                              textAlign: "right",
                              color: C.red,
                              fontWeight: 700,
                            }}
                          >
                            {t.type === "invoice" ? fmtZAR(t.amount) : "—"}
                          </td>
                          <td
                            style={{
                              ...td,
                              textAlign: "right",
                              color: C.green,
                              fontWeight: 700,
                            }}
                          >
                            {t.type === "payment" ? fmtZAR(t.amount) : "—"}
                          </td>
                          <td
                            style={{
                              ...td,
                              textAlign: "right",
                              fontWeight: 800,
                              color: t.running > 0.001 ? C.red : C.green,
                            }}
                          >
                            {fmtZAR(t.running)}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>

              {/* Closing balance bar */}
              <div
                style={{
                  marginTop: 18,
                  borderRadius: 12,
                  padding: "16px 22px",
                  background: owes ? C.red : C.green,
                  color: "#fff",
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  flexWrap: "wrap",
                  gap: 8,
                }}
              >
                <span style={{ fontSize: 15, fontWeight: 700 }}>
                  Closing Balance
                </span>
                <span style={{ fontSize: 22, fontWeight: 900 }}>
                  {fmtZAR(balance)}
                </span>
              </div>

              <div
                style={{
                  textAlign: "center",
                  color: C.muted,
                  fontSize: 12,
                  marginTop: 14,
                }}
              >
                Statement generated {fmtDate(todayISO())}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

/* ============================================================
   Root App
   ============================================================ */
function App() {
  const [config, setConfig] = useState(() => {
    const url = localStorage.getItem("wt_url");
    const key = localStorage.getItem("wt_key");
    return url && key ? { url, key } : null;
  });
  const [sb, setSb] = useState(() =>
    config ? makeSupabase(config.url, config.key) : null
  );
  const [user, setUser] = useState(null);
  const [toasts, setToasts] = useState([]);
  const [settings, setSettings] = useState({
    admin_password: "0000",
    staff_password: "9999",
  });

  const toast = useCallback((msg, kind = "success") => {
    const id = Math.random().toString(36).slice(2) + Date.now();
    setToasts((t) => [...t, { id, msg, kind }]);
    setTimeout(() => {
      setToasts((t) => t.filter((x) => x.id !== id));
    }, 3000);
  }, []);

  const loadSettings = useCallback(async () => {
    if (!sb) return;
    try {
      const rows = await sb.query("wt_settings", { select: "*" });
      if (rows && rows.length) {
        const map = {};
        rows.forEach((r) => (map[r.key] = r.value));
        setSettings((s) => ({ ...s, ...map }));
      }
    } catch (_) {
      // wt_settings may not exist yet — keep defaults so login still works
    }
  }, [sb]);

  useEffect(() => {
    loadSettings();
  }, [loadSettings]);

  const onSetupDone = (url, key) => {
    setConfig({ url, key });
    setSb(makeSupabase(url, key));
  };

  const reconnect = () => {
    localStorage.removeItem("wt_url");
    localStorage.removeItem("wt_key");
    window.location.reload();
  };

  let screen;
  if (!config || !sb) {
    screen = <SetupWizard onDone={onSetupDone} toast={toast} />;
  } else if (!user) {
    screen = (
      <Login
        sb={sb}
        onLogin={setUser}
        toast={toast}
        onReconnect={reconnect}
        settings={settings}
      />
    );
  } else if (user.role === "shop") {
    screen = (
      <ShopStatement
        sb={sb}
        user={user}
        onLogout={() => setUser(null)}
        toast={toast}
      />
    );
  } else {
    screen = (
      <Dashboard
        sb={sb}
        user={user}
        onLogout={() => setUser(null)}
        toast={toast}
        settings={settings}
        onSettingsChanged={loadSettings}
      />
    );
  }

  return (
    <>
      {screen}
      <Toasts items={toasts} />
    </>
  );
}

/* ---------- Responsive sidebar styles (injected once) ---------- */
const styleTag = document.createElement("style");
styleTag.textContent = `
  @media (max-width: 640px) {
    .wt-burger { display: inline-block !important; }
    .wt-sidebar {
      position: fixed; top: 58px; bottom: 0; left: 0; z-index: 45;
      transform: translateX(-100%); transition: transform 0.2s ease;
      box-shadow: 0 0 30px rgba(0,0,0,0.2);
    }
    .wt-sidebar.wt-open { transform: translateX(0); }
  }
  @media (min-width: 641px) {
    .wt-overlay { display: none !important; }
  }
`;
document.head.appendChild(styleTag);

/* ---------- Mount ---------- */
const root = createRoot(document.getElementById("root"));
root.render(<App />);

export default App;
