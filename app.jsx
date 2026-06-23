import React, { useState, useEffect, useCallback, useRef } from "react";
import { createRoot } from "react-dom/client";

/* ============================================================
   WholesaleTrack — single-file wholesale creditor manager
   React (no build tools) + custom Supabase REST client.
   UI: design-system stylesheet (8px grid) + semantic classes.
   ============================================================ */

/* ---------- Dynamic colors used inline (match CSS vars) ---------- */
const C = {
  navy: "#0B1D3A",
  navyMid: "#16346A",
  gold: "#D4930A",
  goldLight: "#F5B829",
  red: "#DC2626",
  green: "#15803D",
  muted: "#94A3B8",
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

/* ============================================================
   Icons (inline, currentColor stroke)
   ============================================================ */
const Ic = {
  menu: "M3 6h18M3 12h18M3 18h18",
  close: "M6 6l12 12M18 6L6 18",
  plus: "M12 5v14M5 12h14",
  home: "M3 11l9-8 9 8M5 10v10h14V10",
  shop: "M4 7h16l-1 5H5L4 7zM4 7l-.5-2.5H2M6 21a1 1 0 100-2 1 1 0 000 2zM17 21a1 1 0 100-2 1 1 0 000 2z",
  logout: "M16 17l5-5-5-5M21 12H9M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4",
  key: "M21 2l-2 2m-7 7a4 4 0 11-5.66 5.66A4 4 0 0112 11zm0 0l4-4m0 0l3 3m-3-3l2 2",
  search: "M11 19a8 8 0 100-16 8 8 0 000 16zM21 21l-4.3-4.3",
  inbox: "M22 12h-6l-2 3h-4l-2-3H2M5.45 5.11L2 12v6a2 2 0 002 2h16a2 2 0 002-2v-6l-3.45-6.89A2 2 0 0016.76 4H7.24a2 2 0 00-1.79 1.11z",
  alert: "M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z",
  copy: "M9 9h10a2 2 0 012 2v10a2 2 0 01-2 2H9a2 2 0 01-2-2V11a2 2 0 012-2zM5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1",
  check: "M20 6L9 17l-5-5",
  clock: "M12 22a10 10 0 100-20 10 10 0 000 20zM12 6v6l4 2",
  chart: "M3 3v18h18M18 9l-5 5-3-3-4 4",
  users: "M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2M9 11a4 4 0 100-8 4 4 0 000 8zM23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75",
};
function Icon({ name, size = 18, className = "" }) {
  return (
    <svg
      className={"ic " + className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d={Ic[name]} />
    </svg>
  );
}

/* ============================================================
   UI atoms
   ============================================================ */
function Spinner({ size = 18 }) {
  return (
    <span
      className="spinner"
      style={{ width: size, height: size }}
      aria-hidden="true"
    />
  );
}

function Button({
  variant = "primary",
  size,
  block,
  className = "",
  children,
  ...props
}) {
  const cls = [
    "btn",
    "btn--" + variant,
    size === "sm" && "btn--sm",
    size === "lg" && "btn--lg",
    block && "btn--block",
    className,
  ]
    .filter(Boolean)
    .join(" ");
  return (
    <button className={cls} {...props}>
      {children}
    </button>
  );
}

function IconButton({ icon, label, className = "", ...props }) {
  return (
    <button className={"icon-btn " + className} aria-label={label} {...props}>
      <Icon name={icon} />
    </button>
  );
}

function Field({ label, error, hint, required, children }) {
  return (
    <div className="field">
      {label && (
        <label className="field__label">
          {label} {required && <span className="field__req">*</span>}
        </label>
      )}
      {children}
      {hint && !error && <span className="field__hint">{hint}</span>}
      {error && (
        <span className="field__error" role="alert">
          <Icon name="alert" size={13} /> {error}
        </span>
      )}
    </div>
  );
}

function Input({ invalid, className = "", ...p }) {
  return (
    <input
      className={"input " + (invalid ? "is-invalid " : "") + className}
      {...p}
    />
  );
}

function Select({ invalid, className = "", children, ...p }) {
  return (
    <select
      className={"input select " + (invalid ? "is-invalid " : "") + className}
      {...p}
    >
      {children}
    </select>
  );
}

function Badge({ tone = "neutral", children, className = "" }) {
  return (
    <span className={`badge badge--${tone} ${className}`}>{children}</span>
  );
}

function EmptyState({ icon = "inbox", title, hint }) {
  return (
    <div className="empty">
      <div className="empty__icon">
        <Icon name={icon} size={22} />
      </div>
      <div className="empty__title">{title}</div>
      {hint && <div className="empty__hint">{hint}</div>}
    </div>
  );
}

/* skeleton loaders */
function Sk({ w = "100%", h = 14, r = 7, className = "", style }) {
  return (
    <span
      className={"sk " + className}
      style={{ width: w, height: h, borderRadius: r, ...(style || {}) }}
    />
  );
}
function SkeletonStats() {
  return (
    <div className="stat-grid" aria-hidden="true">
      {[0, 1, 2, 3].map((i) => (
        <div className="stat" key={i}>
          <Sk w="55%" h={11} />
          <Sk w="70%" h={26} style={{ marginTop: 12 }} />
        </div>
      ))}
    </div>
  );
}
function SkeletonCard({ rows = 5 }) {
  return (
    <div className="card" aria-hidden="true">
      <div className="card__head">
        <Sk w={140} h={14} />
      </div>
      <div className="card__pad">
        {Array.from({ length: rows }).map((_, i) => (
          <div className="sk-row" key={i}>
            <Sk w="40%" h={13} />
            <Sk w="20%" h={13} />
          </div>
        ))}
      </div>
    </div>
  );
}

function Toasts({ items, onDismiss }) {
  return (
    <div className="toast-wrap" role="status" aria-live="polite">
      {items.map((t) => (
        <div
          key={t.id}
          className={`toast toast--${t.kind === "error" ? "error" : "success"}`}
          onClick={() => onDismiss(t.id)}
        >
          <Icon name={t.kind === "error" ? "alert" : "check"} size={16} />
          <span>{t.msg}</span>
        </div>
      ))}
    </div>
  );
}

function Modal({ title, onClose, children, footer, size = "md" }) {
  const panelRef = useRef(null);
  useEffect(() => {
    const onKey = (e) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const el = panelRef.current;
    if (el) {
      const f = el.querySelector(
        "input,select,textarea,button:not(.icon-btn)"
      );
      f && f.focus();
    }
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onClose]);

  return (
    <div className="overlay" onMouseDown={onClose}>
      <div
        ref={panelRef}
        className={"modal modal--" + size}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="modal__head">
          <h3 className="modal__title">{title}</h3>
          <IconButton icon="close" label="Close dialog" onClick={onClose} />
        </div>
        <div className="modal__body">{children}</div>
        {footer && <div className="modal__foot">{footer}</div>}
      </div>
    </div>
  );
}

/* ---------- Logo ---------- */
function Logo({ light, size = "md" }) {
  return (
    <div className={"logo " + (light ? "logo--light " : "") + "logo--" + size}>
      <span className="logo__mark" aria-hidden="true">
        W
      </span>
      <span className="logo__text">
        Wholesale<span className="logo__accent">Track</span>
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

  return (
    <div className="screen-brand">
      <div className="auth-card auth-card--wide">
        <div className="auth-card__top">
          <Logo />
          <span className="muted-sm">First-time setup</span>
        </div>

        <div className="stepper">
          {[1, 2, 3].map((n) => (
            <div
              className={"stepper__item " + (step >= n ? "is-done" : "")}
              key={n}
            >
              <span className="stepper__dot">{step > n ? "✓" : n}</span>
              <span className="stepper__label">
                {n === 1 ? "Create" : n === 2 ? "Schema" : "Connect"}
              </span>
            </div>
          ))}
        </div>

        <div className="auth-card__body">
          {step === 1 && (
            <div className="stack">
              <h2 className="h2">Create a free Supabase project</h2>
              <ol className="steps-list">
                <li>
                  Go to{" "}
                  <a
                    href="https://supabase.com"
                    target="_blank"
                    rel="noreferrer"
                  >
                    supabase.com
                  </a>{" "}
                  and sign up (free).
                </li>
                <li>
                  Click <b>New Project</b> and pick any name &amp; region.
                </li>
                <li>Wait ~1 minute for the database to be provisioned.</li>
              </ol>
              <div className="row-end">
                <Button onClick={() => setStep(2)}>Continue</Button>
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="stack">
              <h2 className="h2">Run the database schema</h2>
              <p className="muted">
                Open the <b>SQL Editor</b> in Supabase, paste the script below,
                and click <b>Run</b>.
              </p>
              <div className="code-block">
                <pre>{SCHEMA_SQL}</pre>
                <Button
                  variant="subtle"
                  size="sm"
                  className="code-block__copy"
                  onClick={copySql}
                >
                  <Icon name="copy" size={14} /> Copy
                </Button>
              </div>
              <div className="row-split">
                <Button variant="ghost" onClick={() => setStep(1)}>
                  Back
                </Button>
                <Button onClick={() => setStep(3)}>Continue</Button>
              </div>
            </div>
          )}

          {step === 3 && (
            <div className="stack">
              <h2 className="h2">Connect your project</h2>
              <p className="muted">
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
              <Field label="anon public key" error={err}>
                <Input
                  placeholder="eyJhbGciOi..."
                  value={key}
                  onChange={(e) => setKey(e.target.value)}
                />
              </Field>
              <div className="row-split">
                <Button
                  variant="ghost"
                  onClick={() => setStep(2)}
                  disabled={testing}
                >
                  Back
                </Button>
                <Button onClick={connect} disabled={testing}>
                  {testing ? (
                    <>
                      <Spinner size={15} /> Testing…
                    </>
                  ) : (
                    "Connect & Launch"
                  )}
                </Button>
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

  return (
    <div className="screen-brand">
      <div className="auth-card">
        <div className="auth-card__hero">
          <Logo size="lg" />
          <p className="auth-card__sub">
            {isShop ? "Shop account login" : "Staff & admin login"}
          </p>
        </div>

        <div className="auth-card__body">
          <div className="seg" role="tablist" aria-label="Login type">
            <button
              role="tab"
              aria-selected={!isShop}
              className={"seg__btn " + (!isShop ? "is-active" : "")}
              onClick={() => switchPortal("staff")}
            >
              Staff / Admin
            </button>
            <button
              role="tab"
              aria-selected={isShop}
              className={"seg__btn " + (isShop ? "is-active" : "")}
              onClick={() => switchPortal("shop")}
            >
              Shop
            </button>
          </div>

          <Field label={isShop ? "Shop username" : "Username"}>
            <Input
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              onKeyDown={onKey}
              placeholder={isShop ? "your shop username" : "username"}
              autoComplete="username"
            />
          </Field>

          <Field label="Password" error={err}>
            <Input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              onKeyDown={onKey}
              placeholder="••••"
              autoComplete="current-password"
            />
          </Field>

          <Button block onClick={submit} disabled={busy}>
            {busy ? (
              <>
                <Spinner size={15} /> Signing in…
              </>
            ) : isShop ? (
              "View my statement"
            ) : (
              "Sign in"
            )}
          </Button>

          <button className="link-btn" onClick={onReconnect}>
            Reconnect to Supabase
          </button>
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
    <Badge tone={inv ? "danger" : "success"}>
      {inv ? "Invoice" : "Payment"}
    </Badge>
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
  const [active, setActive] = useState("dashboard");
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [navQuery, setNavQuery] = useState("");

  const [shopModal, setShopModal] = useState(null);
  const [txModal, setTxModal] = useState(null);
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

  const activeCreditor =
    active !== "dashboard" ? creditors.find((c) => c.id === active) : null;

  const go = (key) => {
    setActive(key);
    setSidebarOpen(false);
  };

  const filteredNav = creditors.filter((c) =>
    (c.name + " " + (c.contact || ""))
      .toLowerCase()
      .includes(navQuery.trim().toLowerCase())
  );

  return (
    <div className="app">
      {/* Top bar */}
      <header className="topbar">
        <div className="topbar__left">
          <IconButton
            icon="menu"
            label="Open menu"
            className="hamburger"
            onClick={() => setSidebarOpen((s) => !s)}
          />
          <Logo />
        </div>
        <div className="topbar__right">
          {isAdmin && (
            <>
              <Button
                variant="ghost"
                size="sm"
                aria-label="Add transaction"
                onClick={() => setTxModal({})}
              >
                <Icon name="plus" size={16} />
                <span className="btn__label">Transaction</span>
              </Button>
              <Button
                size="sm"
                aria-label="Add shop"
                onClick={() => setShopModal({ mode: "add", data: null })}
              >
                <Icon name="plus" size={16} />
                <span className="btn__label">Add shop</span>
              </Button>
            </>
          )}
        </div>
      </header>

      <div className="layout">
        {/* Sidebar */}
        <aside className={"sidebar " + (sidebarOpen ? "is-open" : "")}>
          <div className="sidebar__scroll">
            <div className="sidebar__search">
              <Icon name="search" size={15} />
              <input
                className="sidebar__search-input"
                placeholder="Search shops"
                value={navQuery}
                onChange={(e) => setNavQuery(e.target.value)}
                aria-label="Search shops"
              />
            </div>

            <button
              className={
                "navlink " + (active === "dashboard" ? "is-active" : "")
              }
              onClick={() => go("dashboard")}
            >
              <Icon name="home" size={17} />
              <span className="navlink__name">Dashboard</span>
            </button>

            <div className="sidebar__section">Shops · {creditors.length}</div>

            {filteredNav.length === 0 && (
              <div className="sidebar__empty">
                {creditors.length === 0 ? "No shops yet" : "No matches"}
              </div>
            )}
            {filteredNav.map((c) => {
              const b = balances[c.id] || { balance: 0 };
              const owes = b.balance > 0.001;
              return (
                <button
                  key={c.id}
                  className={"navlink " + (active === c.id ? "is-active" : "")}
                  onClick={() => go(c.id)}
                >
                  <span className="navlink__name">{c.name}</span>
                  <span
                    className={
                      "navlink__bal " + (owes ? "t-danger" : "t-success")
                    }
                  >
                    {fmtZAR(b.balance)}
                  </span>
                </button>
              );
            })}
          </div>

          <div className="sidebar__foot">
            <div className="acct">
              <div className="acct__id">
                <Badge tone={isAdmin ? "accent" : "brand"}>{user.role}</Badge>
                <span className="acct__name">{user.name}</span>
              </div>
              <div className="acct__actions">
                <Button
                  variant="subtle"
                  size="sm"
                  onClick={() => setPwModal(true)}
                >
                  <Icon name="key" size={15} /> Password
                </Button>
                <Button variant="subtle" size="sm" onClick={onLogout}>
                  <Icon name="logout" size={15} /> Logout
                </Button>
              </div>
            </div>
          </div>
        </aside>

        {sidebarOpen && (
          <div className="scrim" onClick={() => setSidebarOpen(false)} />
        )}

        {/* Main */}
        <main className="main">
          <div className="container">
            {loading ? (
              <div className="stack-lg">
                <SkeletonStats />
                <SkeletonCard rows={4} />
                <SkeletonCard rows={5} />
              </div>
            ) : active === "dashboard" ? (
              <DashboardOverview
                creditors={creditors}
                transactions={transactions}
                balances={balances}
                totalOwed={totalOwed}
                shopsWithBalance={shopsWithBalance}
                isAdmin={isAdmin}
                creditorName={creditorName}
                onView={(id) => go(id)}
                onEdit={(c) => setShopModal({ mode: "edit", data: c })}
                onDelete={deleteShop}
                onDeleteTx={deleteTx}
                onAddShop={() => setShopModal({ mode: "add", data: null })}
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
                onBack={() => go("dashboard")}
              />
            ) : (
              <EmptyState title="Shop not found" />
            )}
          </div>
        </main>
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
          title={`Change ${isAdmin ? "admin" : "staff"} password`}
          verify={(cur) =>
            cur === (settings[pwKey] || (isAdmin ? "0000" : "9999"))
          }
          onSave={changeMyPassword}
          onClose={() => setPwModal(false)}
        />
      )}
    </div>
  );
}

function StatCard({ label, value, tone, icon }) {
  return (
    <div className="stat">
      <div className="stat__top">
        <span className="stat__label">{label}</span>
        {icon && (
          <span className={"stat__icon stat__icon--" + (tone || "neutral")}>
            <Icon name={icon} size={16} />
          </span>
        )}
      </div>
      <div className={"stat__value " + (tone ? "t-" + tone : "")}>{value}</div>
    </div>
  );
}

function DashboardOverview({
  creditors,
  transactions,
  balances,
  totalOwed,
  shopsWithBalance,
  isAdmin,
  creditorName,
  onView,
  onEdit,
  onDelete,
  onDeleteTx,
  onAddShop,
}) {
  const recent = [...transactions]
    .sort((a, b) => (a.created_at < b.created_at ? 1 : -1))
    .slice(0, 15);

  const [overdueDays, setOverdueDays] = useState(30);
  const [shopQuery, setShopQuery] = useState("");

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

  const shownShops = creditors.filter((c) =>
    (c.name + " " + (c.contact || ""))
      .toLowerCase()
      .includes(shopQuery.trim().toLowerCase())
  );

  return (
    <div className="stack-lg">
      <div className="page-head">
        <h1 className="h1">Dashboard</h1>
        <p className="muted">Overview of every shop account.</p>
      </div>

      <div className="stat-grid">
        <StatCard label="Total shops" value={creditors.length} icon="shop" />
        <StatCard
          label="Total owed"
          value={fmtZAR(totalOwed)}
          tone="danger"
          icon="alert"
        />
        <StatCard
          label="Shops with balance"
          value={shopsWithBalance}
          icon="users"
        />
        <StatCard
          label="Transactions"
          value={transactions.length}
          icon="chart"
        />
      </div>

      {/* Overdue (admin only) */}
      {isAdmin && (
        <div className="card">
          <div className="card__head card__head--split">
            <div className="card__title">
              Overdue shops
              <Badge
                tone={overdueShops.length ? "danger" : "success"}
                className="ml-8"
              >
                {overdueShops.length}
              </Badge>
            </div>
            <label className="inline-control">
              <span className="muted-sm">Pending over</span>
              <input
                className="input input--xs"
                type="number"
                min="0"
                inputMode="numeric"
                value={overdueDays}
                onChange={(e) => setOverdueDays(e.target.value)}
                aria-label="Days pending threshold"
              />
              <span className="muted-sm">days</span>
            </label>
          </div>

          {overdueShops.length === 0 ? (
            <div className="card__pad">
              <EmptyState
                icon="check"
                title="Nothing overdue"
                hint={`No shop has a balance pending more than ${overdueDays} days.`}
              />
            </div>
          ) : (
            <div className="table-wrap">
              <table className="table table--responsive">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Oldest unpaid</th>
                    <th className="num">Days</th>
                    <th className="num">Balance</th>
                    <th aria-label="Actions"></th>
                  </tr>
                </thead>
                <tbody>
                  {overdueShops.map((o) => (
                    <tr key={o.creditor.id}>
                      <td data-label="Name" className="strong">
                        {o.creditor.name}
                      </td>
                      <td data-label="Oldest unpaid">{fmtDate(o.date)}</td>
                      <td data-label="Days" className="num t-danger strong">
                        {o.days} days
                      </td>
                      <td data-label="Balance" className="num t-danger strong">
                        {fmtZAR(o.balance)}
                      </td>
                      <td className="cell-actions">
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => onView(o.creditor.id)}
                        >
                          View
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* All shops */}
      <div className="card">
        <div className="card__head card__head--split">
          <div className="card__title">All shops</div>
          <label className="inline-control inline-control--grow">
            <Icon name="search" size={15} className="t-muted" />
            <input
              className="input input--sm"
              placeholder="Filter shops"
              value={shopQuery}
              onChange={(e) => setShopQuery(e.target.value)}
              aria-label="Filter shops"
            />
          </label>
        </div>

        {creditors.length === 0 ? (
          <div className="card__pad">
            <EmptyState
              icon="shop"
              title="No shops yet"
              hint={isAdmin ? "Add your first shop to get started." : undefined}
            />
            {isAdmin && (
              <div className="row-center">
                <Button onClick={onAddShop}>
                  <Icon name="plus" size={16} /> Add shop
                </Button>
              </div>
            )}
          </div>
        ) : (
          <div className="table-wrap">
            <table className="table table--responsive">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Contact</th>
                  <th className="num">Balance</th>
                  {isAdmin && <th>Credentials</th>}
                  <th aria-label="Actions"></th>
                </tr>
              </thead>
              <tbody>
                {shownShops.length === 0 && (
                  <tr className="empty-row">
                    <td colSpan={isAdmin ? 5 : 4}>
                      <span className="muted">No shops match “{shopQuery}”.</span>
                    </td>
                  </tr>
                )}
                {shownShops.map((c) => {
                  const b = balances[c.id] || { balance: 0 };
                  const owes = b.balance > 0.001;
                  return (
                    <tr key={c.id}>
                      <td data-label="Name" className="strong">
                        {c.name}
                      </td>
                      <td data-label="Contact" className="t-muted">
                        {c.contact || "—"}
                      </td>
                      <td
                        data-label="Balance"
                        className={"num strong " + (owes ? "t-danger" : "t-success")}
                      >
                        {fmtZAR(b.balance)}
                      </td>
                      {isAdmin && (
                        <td data-label="Credentials">
                          <code className="code-pill">
                            {c.username} / {c.password}
                          </code>
                        </td>
                      )}
                      <td className="cell-actions">
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => onView(c.id)}
                        >
                          View
                        </Button>
                        {isAdmin && (
                          <>
                            <Button
                              variant="subtle"
                              size="sm"
                              onClick={() => onEdit(c)}
                            >
                              Edit
                            </Button>
                            <Button
                              variant="danger-ghost"
                              size="sm"
                              onClick={() => onDelete(c)}
                            >
                              Delete
                            </Button>
                          </>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Recent transactions */}
      <div className="card">
        <div className="card__head">
          <div className="card__title">Recent transactions</div>
        </div>
        {recent.length === 0 ? (
          <div className="card__pad">
            <EmptyState icon="inbox" title="No transactions yet" />
          </div>
        ) : (
          <div className="table-wrap">
            <table className="table table--responsive">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Shop</th>
                  <th>Description</th>
                  <th>Type</th>
                  <th className="num">Amount</th>
                  {isAdmin && <th aria-label="Actions"></th>}
                </tr>
              </thead>
              <tbody>
                {recent.map((t) => (
                  <tr key={t.id}>
                    <td data-label="Date" className="nowrap">
                      {fmtDate(t.date)}
                    </td>
                    <td data-label="Shop" className="strong">
                      {creditorName(t.creditor_id)}
                    </td>
                    <td data-label="Description">{t.description}</td>
                    <td data-label="Type">
                      <TypeBadge type={t.type} />
                    </td>
                    <td
                      data-label="Amount"
                      className={
                        "num strong " +
                        (t.type === "invoice" ? "t-danger" : "t-success")
                      }
                    >
                      {fmtZAR(t.amount)}
                    </td>
                    {isAdmin && (
                      <td className="cell-actions">
                        <Button
                          variant="danger-ghost"
                          size="sm"
                          onClick={() => onDeleteTx(t)}
                        >
                          Delete
                        </Button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

function ShopTab({ creditor, transactions, isAdmin, onAddTx, onDeleteTx, onBack }) {
  const sorted = sortTx(transactions);
  const invoiced = transactions
    .filter((t) => t.type === "invoice")
    .reduce((s, t) => s + Number(t.amount), 0);
  const paid = transactions
    .filter((t) => t.type === "payment")
    .reduce((s, t) => s + Number(t.amount), 0);
  const balance = invoiced - paid;
  const owes = balance > 0.001;

  return (
    <div className="stack-lg">
      <button className="link-btn link-btn--back" onClick={onBack}>
        ← Dashboard
      </button>

      <div className="page-head page-head--split">
        <div className="page-head__title">
          <h1 className="h1">{creditor.name}</h1>
          <Badge tone={owes ? "danger" : "success"}>
            {owes ? "Owes" : "Settled"}
          </Badge>
        </div>
        {isAdmin && (
          <Button onClick={onAddTx}>
            <Icon name="plus" size={16} /> Add transaction
          </Button>
        )}
      </div>

      <div className="stat-grid stat-grid--3">
        <StatCard label="Total invoiced" value={fmtZAR(invoiced)} tone="danger" />
        <StatCard label="Total paid" value={fmtZAR(paid)} tone="success" />
        <StatCard
          label="Balance due"
          value={fmtZAR(balance)}
          tone={owes ? "danger" : "success"}
        />
      </div>

      <div className="card">
        <div className="card__head">
          <div className="card__title">Transactions</div>
        </div>
        {sorted.length === 0 ? (
          <div className="card__pad">
            <EmptyState
              icon="inbox"
              title="No transactions yet"
              hint={isAdmin ? "Add a delivery or payment for this shop." : undefined}
            />
          </div>
        ) : (
          <div className="table-wrap">
            <table className="table table--responsive">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Description</th>
                  <th className="num">Invoice</th>
                  <th className="num">Payment</th>
                  {isAdmin && <th aria-label="Actions"></th>}
                </tr>
              </thead>
              <tbody>
                {sorted.map((t) => (
                  <tr key={t.id}>
                    <td data-label="Date" className="nowrap">
                      {fmtDate(t.date)}
                    </td>
                    <td data-label="Description">{t.description}</td>
                    <td data-label="Invoice" className="num t-danger strong">
                      {t.type === "invoice" ? fmtZAR(t.amount) : "—"}
                    </td>
                    <td data-label="Payment" className="num t-success strong">
                      {t.type === "payment" ? fmtZAR(t.amount) : "—"}
                    </td>
                    {isAdmin && (
                      <td className="cell-actions">
                        <Button
                          variant="danger-ghost"
                          size="sm"
                          onClick={() => onDeleteTx(t)}
                        >
                          Delete
                        </Button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
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
  const [errors, setErrors] = useState({});
  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }));

  const submit = async () => {
    const e = {};
    if (!form.name.trim()) e.name = "Shop name is required.";
    if (!form.username.trim()) e.username = "Username is required.";
    if (!form.password.trim()) e.password = "Password is required.";
    setErrors(e);
    if (Object.keys(e).length) return;

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
      title={mode === "add" ? "Add shop" : "Edit shop"}
      onClose={onClose}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={busy}>
            {busy ? <Spinner size={15} /> : "Save"}
          </Button>
        </>
      }
    >
      <Field label="Shop name" required error={errors.name}>
        <Input value={form.name} onChange={set("name")} invalid={!!errors.name} />
      </Field>
      <Field label="Contact" hint="Phone or email (optional)">
        <Input value={form.contact} onChange={set("contact")} />
      </Field>
      <Field label="Address">
        <Input value={form.address} onChange={set("address")} />
      </Field>
      <div className="grid-2">
        <Field label="Username" required error={errors.username}>
          <Input
            value={form.username}
            onChange={set("username")}
            invalid={!!errors.username}
          />
        </Field>
        <Field label="Password" required error={errors.password}>
          <Input
            value={form.password}
            onChange={set("password")}
            invalid={!!errors.password}
          />
        </Field>
      </div>
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
  const [errors, setErrors] = useState({});
  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }));

  const submit = async () => {
    const e = {};
    if (!form.creditor_id) e.creditor_id = "Select a shop.";
    if (!form.description.trim()) e.description = "Description is required.";
    const amt = Number(form.amount);
    if (!amt || amt <= 0) e.amount = "Enter an amount greater than zero.";
    setErrors(e);
    if (Object.keys(e).length) return;

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
      title="Add transaction"
      onClose={onClose}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={busy}>
            {busy ? <Spinner size={15} /> : "Save"}
          </Button>
        </>
      }
    >
      <Field label="Shop" required error={errors.creditor_id}>
        <Select
          value={form.creditor_id}
          onChange={set("creditor_id")}
          invalid={!!errors.creditor_id}
        >
          {creditors.length === 0 && <option value="">No shops available</option>}
          {creditors.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </Select>
      </Field>
      <div className="grid-2">
        <Field label="Type" required>
          <Select value={form.type} onChange={set("type")}>
            <option value="invoice">Invoice (delivery)</option>
            <option value="payment">Payment (received)</option>
          </Select>
        </Field>
        <Field label="Date" required>
          <Input type="date" value={form.date} onChange={set("date")} />
        </Field>
      </div>
      <Field label="Description" required error={errors.description}>
        <Input
          value={form.description}
          onChange={set("description")}
          invalid={!!errors.description}
          placeholder="e.g. Delivery #102 / Cash payment"
        />
      </Field>
      <Field label="Amount (R)" required error={errors.amount}>
        <Input
          type="number"
          min="0"
          step="0.01"
          inputMode="decimal"
          value={form.amount}
          onChange={set("amount")}
          invalid={!!errors.amount}
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
      title={title || "Change password"}
      onClose={onClose}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={busy}>
            {busy ? <Spinner size={15} /> : "Update password"}
          </Button>
        </>
      }
    >
      <Field label="Current password">
        <Input
          type="password"
          value={cur}
          onChange={(e) => setCur(e.target.value)}
        />
      </Field>
      <Field label="New password" hint="At least 4 characters">
        <Input
          type="password"
          value={n1}
          onChange={(e) => setN1(e.target.value)}
        />
      </Field>
      <Field label="Confirm new password" error={err}>
        <Input
          type="password"
          value={n2}
          onChange={(e) => setN2(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && submit()}
        />
      </Field>
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

  return (
    <div className="app">
      <header className="topbar">
        <Logo />
        <div className="topbar__right">
          <Button variant="ghost" size="sm" onClick={() => setPwModal(true)}>
            <Icon name="key" size={15} />
            <span className="btn__label">Password</span>
          </Button>
          <Button variant="subtle" size="sm" onClick={onLogout}>
            <Icon name="logout" size={15} />
            <span className="btn__label">Logout</span>
          </Button>
        </div>
      </header>

      {pwModal && (
        <ChangePasswordModal
          title="Change password"
          verify={(c) => c === currentPass}
          onSave={changePassword}
          onClose={() => setPwModal(false)}
        />
      )}

      <main className="main">
        <div className="container container--narrow stack-lg">
          <div className="statement-hero">
            <div>
              <div className="statement-hero__eyebrow">Account statement</div>
              <div className="statement-hero__name">{creditor.name}</div>
              {creditor.address && (
                <div className="statement-hero__meta">{creditor.address}</div>
              )}
              <div className="statement-hero__meta">
                {transactions.length} transaction
                {transactions.length === 1 ? "" : "s"}
              </div>
            </div>
            <div className="statement-hero__balance">
              <div className="statement-hero__balance-label">Balance due</div>
              <div
                className={
                  "statement-hero__balance-value " +
                  (owes ? "is-owed" : "is-clear")
                }
              >
                {fmtZAR(balance)}
              </div>
            </div>
          </div>

          {loading ? (
            <SkeletonCard rows={6} />
          ) : (
            <>
              <div className="card">
                {rows.length === 0 ? (
                  <div className="card__pad">
                    <EmptyState
                      icon="inbox"
                      title="No transactions on record yet"
                    />
                  </div>
                ) : (
                  <div className="table-wrap table-wrap--tall">
                    <table className="table table--responsive">
                      <thead>
                        <tr>
                          <th>Date</th>
                          <th>Description</th>
                          <th className="num">Invoice</th>
                          <th className="num">Payment</th>
                          <th className="num">Balance</th>
                        </tr>
                      </thead>
                      <tbody>
                        {rows.map((t) => (
                          <tr key={t.id}>
                            <td data-label="Date" className="nowrap">
                              {fmtDate(t.date)}
                            </td>
                            <td data-label="Description">{t.description}</td>
                            <td data-label="Invoice" className="num t-danger strong">
                              {t.type === "invoice" ? fmtZAR(t.amount) : "—"}
                            </td>
                            <td data-label="Payment" className="num t-success strong">
                              {t.type === "payment" ? fmtZAR(t.amount) : "—"}
                            </td>
                            <td
                              data-label="Balance"
                              className={
                                "num strong " +
                                (t.running > 0.001 ? "t-danger" : "t-success")
                              }
                            >
                              {fmtZAR(t.running)}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>

              <div
                className={"closing-bar " + (owes ? "is-owed" : "is-clear")}
              >
                <span>Closing balance</span>
                <span className="closing-bar__value">{fmtZAR(balance)}</span>
              </div>

              <div className="statement-foot">
                Statement generated {fmtDate(todayISO())}
              </div>
            </>
          )}
        </div>
      </main>
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
    if (url && key) return { url, key };
    const w = typeof window !== "undefined" ? window.WT_CONFIG : null;
    if (w && w.url && w.key) return { url: w.url, key: w.key };
    return null;
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

  const dismissToast = useCallback(
    (id) => setToasts((t) => t.filter((x) => x.id !== id)),
    []
  );
  const toast = useCallback(
    (msg, kind = "success") => {
      const id = Math.random().toString(36).slice(2) + Date.now();
      setToasts((t) => [...t, { id, msg, kind }]);
      setTimeout(() => dismissToast(id), 3000);
    },
    [dismissToast]
  );

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
      <Toasts items={toasts} onDismiss={dismissToast} />
    </>
  );
}

/* ============================================================
   Design system stylesheet (injected once)
   ============================================================ */
const STYLES = `
:root{
  --bg:#F4F6F8; --surface:#FFFFFF; --surface-2:#F7F9FB;
  --text:#0F172A; --text-2:#475569; --text-3:#94A3B8;
  --border:#E8ECF1; --border-2:#DCE2EA;
  --brand:#0B1D3A; --brand-2:#16346A;
  --accent:#D4930A; --accent-2:#B97E06; --accent-soft:#FBF1DD;
  --danger:#DC2626; --danger-soft:#FEF2F2;
  --success:#15803D; --success-soft:#ECFDF3;
  --r-xs:8px; --r-sm:10px; --r:12px; --r-lg:16px; --r-pill:999px;
  --sh-sm:0 1px 2px rgba(16,24,40,.04), 0 1px 3px rgba(16,24,40,.05);
  --sh-md:0 4px 14px rgba(16,24,40,.08);
  --sh-lg:0 16px 40px rgba(16,24,40,.16);
  --topbar-h:60px;
  --focus:0 0 0 3px rgba(212,147,10,.32);
}
*{box-sizing:border-box}
html,body,#root{height:100%}
body{margin:0;background:var(--bg);color:var(--text);
  font-family:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  font-size:14px;line-height:1.5;-webkit-font-smoothing:antialiased;
  text-rendering:optimizeLegibility;}
a{color:var(--accent-2);font-weight:600;text-decoration:none}
a:hover{text-decoration:underline}
:focus-visible{outline:none;box-shadow:var(--focus);border-radius:8px}
.ic{flex:none;display:inline-block;vertical-align:middle}

/* ---- typography ---- */
.h1{font-size:22px;font-weight:700;letter-spacing:-.01em;margin:0;color:var(--text)}
.h2{font-size:18px;font-weight:700;margin:0;color:var(--text)}
.muted{color:var(--text-2);margin:0}
.muted-sm{color:var(--text-3);font-size:12.5px}
.t-muted{color:var(--text-3)}
.t-danger{color:var(--danger)}
.t-success{color:var(--success)}
.strong{font-weight:650}
.nowrap{white-space:nowrap}
.num{text-align:right;font-variant-numeric:tabular-nums}
.ml-8{margin-left:8px}

/* ---- layout primitives ---- */
.stack{display:flex;flex-direction:column;gap:14px}
.stack-lg{display:flex;flex-direction:column;gap:20px}
.row-end{display:flex;justify-content:flex-end}
.row-split{display:flex;justify-content:space-between;align-items:center;gap:12px}
.row-center{display:flex;justify-content:center;margin-top:14px}
.grid-2{display:grid;grid-template-columns:1fr 1fr;gap:0 14px}
@media (max-width:520px){.grid-2{grid-template-columns:1fr}}

/* ---- buttons ---- */
.btn{display:inline-flex;align-items:center;justify-content:center;gap:7px;
  font-family:inherit;font-size:13.5px;font-weight:600;line-height:1;
  min-height:40px;padding:0 16px;border-radius:var(--r-sm);border:1px solid transparent;
  cursor:pointer;white-space:nowrap;transition:background .15s,border-color .15s,box-shadow .15s,transform .05s,color .15s}
.btn:active{transform:translateY(1px)}
.btn:disabled{opacity:.6;cursor:not-allowed}
.btn--sm{min-height:34px;padding:0 12px;font-size:13px;border-radius:9px}
.btn--lg{min-height:46px;padding:0 20px;font-size:15px}
.btn--block{width:100%}
.btn--primary{background:var(--brand);color:#fff}
.btn--primary:hover:not(:disabled){background:#0e2a55}
.btn--accent{background:var(--accent);color:#fff}
.btn--accent:hover:not(:disabled){background:var(--accent-2)}
.btn--ghost{background:var(--surface);color:var(--text);border-color:var(--border-2)}
.btn--ghost:hover:not(:disabled){background:var(--surface-2);border-color:var(--text-3)}
.btn--subtle{background:var(--surface-2);color:var(--text-2);border-color:transparent}
.btn--subtle:hover:not(:disabled){background:#eef1f5;color:var(--text)}
.btn--danger{background:var(--danger);color:#fff}
.btn--danger:hover:not(:disabled){background:#b91c1c}
.btn--danger-ghost{background:transparent;color:var(--danger);border-color:transparent}
.btn--danger-ghost:hover:not(:disabled){background:var(--danger-soft)}
.btn__label{display:inline}
.icon-btn{display:inline-flex;align-items:center;justify-content:center;
  width:40px;height:40px;border-radius:var(--r-sm);border:none;background:transparent;
  color:inherit;cursor:pointer;transition:background .15s}
.icon-btn:hover{background:rgba(15,23,42,.06)}
.link-btn{background:none;border:none;color:var(--text-3);font-size:12.5px;
  font-weight:600;cursor:pointer;padding:6px;align-self:center;font-family:inherit}
.link-btn:hover{color:var(--text-2);text-decoration:underline}
.link-btn--back{align-self:flex-start;color:var(--text-2);padding:0}

/* ---- inputs ---- */
.input{width:100%;min-height:40px;padding:9px 12px;border:1px solid var(--border-2);
  border-radius:var(--r-sm);font-size:14px;font-family:inherit;color:var(--text);
  background:var(--surface);outline:none;transition:border-color .15s,box-shadow .15s}
.input::placeholder{color:var(--text-3)}
.input:hover{border-color:var(--text-3)}
.input:focus{border-color:var(--accent);box-shadow:var(--focus)}
.input.is-invalid{border-color:var(--danger)}
.input.is-invalid:focus{box-shadow:0 0 0 3px rgba(220,38,38,.18)}
.input--sm{min-height:34px;padding:6px 10px;font-size:13px}
.input--xs{min-height:32px;width:64px;padding:5px 8px;text-align:center;font-size:13px}
.select{appearance:auto;background-image:none}
.field{margin-bottom:14px}
.field__label{display:block;font-size:12.5px;font-weight:600;color:var(--text-2);margin-bottom:6px}
.field__req{color:var(--accent-2)}
.field__hint{display:block;font-size:12px;color:var(--text-3);margin-top:5px}
.field__error{display:flex;align-items:center;gap:5px;font-size:12.5px;color:var(--danger);
  font-weight:600;margin-top:6px}
.inline-control{display:inline-flex;align-items:center;gap:7px}
.inline-control--grow{flex:1;max-width:280px}
.inline-control--grow .input{min-height:34px}

/* ---- badges ---- */
.badge{display:inline-flex;align-items:center;padding:2px 9px;border-radius:var(--r-pill);
  font-size:11.5px;font-weight:700;letter-spacing:.02em;text-transform:capitalize;line-height:1.6}
.badge--neutral{background:var(--surface-2);color:var(--text-2)}
.badge--danger{background:var(--danger-soft);color:var(--danger)}
.badge--success{background:var(--success-soft);color:var(--success)}
.badge--accent{background:var(--accent-soft);color:var(--accent-2)}
.badge--brand{background:#E7ECF5;color:var(--brand-2)}

/* ---- cards ---- */
.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--r-lg);
  box-shadow:var(--sh-sm);overflow:hidden}
.card__head{padding:16px 18px;border-bottom:1px solid var(--border)}
.card__head--split{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}
.card__title{font-size:15px;font-weight:700;color:var(--text);display:inline-flex;align-items:center}
.card__pad{padding:18px}

/* ---- stat grid ---- */
.stat-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px}
.stat-grid--3{grid-template-columns:repeat(3,1fr)}
@media (max-width:900px){.stat-grid,.stat-grid--3{grid-template-columns:repeat(2,1fr)}}
@media (max-width:420px){.stat-grid{grid-template-columns:1fr 1fr;gap:10px}}
.stat{background:var(--surface);border:1px solid var(--border);border-radius:var(--r-lg);
  box-shadow:var(--sh-sm);padding:16px}
.stat__top{display:flex;align-items:center;justify-content:space-between;gap:8px}
.stat__label{font-size:12px;font-weight:600;color:var(--text-3);text-transform:uppercase;letter-spacing:.04em}
.stat__icon{display:inline-flex;align-items:center;justify-content:center;width:28px;height:28px;
  border-radius:8px;background:var(--surface-2);color:var(--text-3)}
.stat__icon--danger{background:var(--danger-soft);color:var(--danger)}
.stat__value{font-size:24px;font-weight:750;letter-spacing:-.01em;margin-top:10px;
  font-variant-numeric:tabular-nums}
@media (max-width:420px){.stat__value{font-size:20px}}

/* ---- tables ---- */
.table-wrap{overflow-x:auto}
.table-wrap--tall{max-height:62vh;overflow-y:auto}
.table{width:100%;border-collapse:collapse;font-size:14px}
.table th{position:relative;text-align:left;padding:11px 16px;font-size:11.5px;font-weight:600;
  color:var(--text-3);text-transform:uppercase;letter-spacing:.04em;white-space:nowrap;
  border-bottom:1px solid var(--border);background:var(--surface)}
.table-wrap--tall thead th{position:sticky;top:0;z-index:2}
.table th.num{text-align:right}
.table td{padding:13px 16px;border-bottom:1px solid var(--border);color:var(--text);vertical-align:middle}
.table tbody tr:last-child td{border-bottom:none}
.table tbody tr{transition:background .12s}
.table tbody tr:hover{background:var(--surface-2)}
.cell-actions{text-align:right;white-space:nowrap}
.cell-actions .btn{margin-left:6px}
.code-pill{background:var(--surface-2);border:1px solid var(--border);padding:3px 8px;
  border-radius:7px;font-size:12.5px;color:var(--text-2);font-family:ui-monospace,Menlo,Consolas,monospace}

/* responsive table -> cards */
@media (max-width:720px){
  .table--responsive thead{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}
  .table--responsive tbody{display:block}
  .table--responsive tr{display:block;background:var(--surface);border:1px solid var(--border);
    border-radius:14px;padding:6px 14px;margin-bottom:10px;box-shadow:var(--sh-sm)}
  .table--responsive tr:hover{background:var(--surface)}
  .table--responsive td{display:flex;align-items:center;justify-content:space-between;gap:16px;
    padding:9px 0;border-bottom:1px solid var(--border)!important;text-align:right!important}
  .table--responsive tr td:last-child{border-bottom:none!important}
  .table--responsive td[data-label]::before{content:attr(data-label);text-align:left;
    color:var(--text-3);font-weight:600;font-size:11.5px;letter-spacing:.03em;text-transform:uppercase;flex:none}
  .table--responsive td.cell-actions{justify-content:flex-end;flex-wrap:wrap;gap:8px;padding-top:11px}
  .table--responsive td.cell-actions .btn{margin-left:0}
  .table--responsive .empty-row td{display:block;text-align:center!important;border:none!important;padding:14px 0}
  .table-wrap--tall{max-height:none}
}

/* ---- empty state ---- */
.empty{display:flex;flex-direction:column;align-items:center;justify-content:center;
  text-align:center;padding:26px 16px;gap:6px}
.empty__icon{width:46px;height:46px;border-radius:50%;background:var(--surface-2);
  display:flex;align-items:center;justify-content:center;color:var(--text-3);margin-bottom:4px}
.empty__title{font-weight:650;color:var(--text)}
.empty__hint{font-size:13px;color:var(--text-3);max-width:340px}

/* ---- app shell ---- */
.app{display:flex;flex-direction:column;height:100%}
.topbar{flex:none;height:var(--topbar-h);display:flex;align-items:center;justify-content:space-between;
  gap:12px;padding:0 16px;padding-top:env(safe-area-inset-top,0);
  background:var(--surface);border-bottom:1px solid var(--border);
  position:sticky;top:0;z-index:50}
.topbar__left{display:flex;align-items:center;gap:8px;min-width:0}
.topbar__right{display:flex;align-items:center;gap:8px}
.layout{flex:1;display:flex;min-height:0}
.sidebar{flex:none;width:264px;background:var(--surface);border-right:1px solid var(--border);
  display:flex;flex-direction:column;min-height:0}
.sidebar__scroll{flex:1;overflow-y:auto;padding:12px}
.sidebar__search{display:flex;align-items:center;gap:8px;padding:0 10px;margin-bottom:10px;
  background:var(--surface-2);border:1px solid var(--border);border-radius:var(--r-sm);color:var(--text-3)}
.sidebar__search-input{flex:1;border:none;background:transparent;outline:none;padding:9px 0;
  font-size:13.5px;font-family:inherit;color:var(--text)}
.sidebar__section{font-size:11px;font-weight:700;color:var(--text-3);text-transform:uppercase;
  letter-spacing:.06em;padding:14px 10px 6px}
.sidebar__empty{padding:6px 10px;color:var(--text-3);font-size:13px}
.navlink{display:flex;align-items:center;gap:10px;width:100%;text-align:left;padding:9px 11px;
  border-radius:var(--r-sm);border:none;background:transparent;color:var(--text);
  font-weight:500;font-size:13.5px;cursor:pointer;transition:background .12s,color .12s;margin-bottom:2px}
.navlink:hover{background:var(--surface-2)}
.navlink.is-active{background:var(--accent-soft);color:var(--brand);font-weight:650;
  box-shadow:inset 3px 0 0 var(--accent)}
.navlink__name{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.navlink__bal{font-variant-numeric:tabular-nums;font-weight:650;font-size:12.5px;white-space:nowrap}
.navlink.is-active .navlink__bal{color:var(--brand)}
.sidebar__foot{flex:none;border-top:1px solid var(--border);padding:12px}
.acct{display:flex;flex-direction:column;gap:10px}
.acct__id{display:flex;align-items:center;gap:8px;min-width:0}
.acct__name{font-size:12.5px;color:var(--text-3);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.acct__actions{display:flex;gap:8px}
.acct__actions .btn{flex:1}
.scrim{position:fixed;inset:0;background:rgba(11,29,58,.4);z-index:45;
  animation:wt-fade .15s ease}
.main{flex:1;min-width:0;overflow-y:auto;
  padding-bottom:env(safe-area-inset-bottom,0)}
.container{max-width:1180px;margin:0 auto;padding:22px;animation:wt-rise .22s ease}
.container--narrow{max-width:880px}
@media (max-width:600px){.container{padding:16px}}
.page-head{display:flex;flex-direction:column;gap:2px}
.page-head--split{flex-direction:row;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}
.page-head__title{display:flex;align-items:center;gap:10px;flex-wrap:wrap}

/* sidebar drawer on small screens */
@media (max-width:900px){
  .sidebar{position:fixed;top:var(--topbar-h);bottom:0;left:0;width:282px;z-index:60;
    transform:translateX(-100%);transition:transform .22s cubic-bezier(.4,0,.2,1);box-shadow:var(--sh-lg)}
  .sidebar.is-open{transform:none}
}
@media (min-width:901px){.hamburger{display:none}.scrim{display:none}}
@media (max-width:640px){.btn__label{display:none}.topbar__right .btn{padding:0;width:40px}}

/* ---- brand screens (setup / login) ---- */
.screen-brand{min-height:100%;display:flex;align-items:center;justify-content:center;padding:20px;
  background:radial-gradient(120% 120% at 50% 0%,#16346A 0%,#0B1D3A 60%)}
.auth-card{width:100%;max-width:400px;background:var(--surface);border-radius:var(--r-lg);
  box-shadow:var(--sh-lg);overflow:hidden;animation:wt-rise .25s ease}
.auth-card--wide{max-width:640px}
.auth-card__top{display:flex;align-items:center;justify-content:space-between;
  padding:18px 22px;border-bottom:1px solid var(--border)}
.auth-card__hero{display:flex;flex-direction:column;align-items:center;gap:8px;padding:30px 26px 8px}
.auth-card__sub{color:var(--text-3);font-size:13px;margin:0}
.auth-card__body{padding:22px 26px 26px;display:flex;flex-direction:column;gap:2px}
.auth-card__body .btn--block{margin-top:6px}
.seg{display:flex;gap:4px;background:var(--surface-2);border:1px solid var(--border);
  border-radius:var(--r);padding:4px;margin-bottom:18px}
.seg__btn{flex:1;border:none;background:transparent;border-radius:9px;padding:9px;font-weight:600;
  font-size:13.5px;color:var(--text-2);cursor:pointer;font-family:inherit;transition:background .15s,color .15s,box-shadow .15s}
.seg__btn.is-active{background:var(--surface);color:var(--brand);box-shadow:var(--sh-sm)}

/* stepper */
.stepper{display:flex;gap:8px;padding:16px 24px;border-bottom:1px solid var(--border)}
.stepper__item{display:flex;align-items:center;gap:8px;flex:1;opacity:.5}
.stepper__item.is-done{opacity:1}
.stepper__dot{width:24px;height:24px;border-radius:50%;background:var(--border);color:var(--text-3);
  display:flex;align-items:center;justify-content:center;font-weight:700;font-size:12px;flex:none}
.stepper__item.is-done .stepper__dot{background:var(--accent);color:#fff}
.stepper__label{font-size:12.5px;font-weight:600;color:var(--text-2)}
@media (max-width:520px){.stepper__label{display:none}}
.steps-list{margin:0;padding-left:18px;line-height:1.9;color:var(--text-2)}
.code-block{position:relative}
.code-block pre{margin:0;background:var(--brand);color:#D7E3F4;padding:16px;border-radius:var(--r);
  font-size:12px;line-height:1.55;overflow:auto;max-height:240px;
  font-family:ui-monospace,Menlo,Consolas,monospace}
.code-block__copy{position:absolute;top:10px;right:10px}

/* ---- logo ---- */
.logo{display:inline-flex;align-items:center;gap:9px;min-width:0}
.logo__mark{width:30px;height:30px;border-radius:9px;background:var(--accent);color:#fff;
  display:flex;align-items:center;justify-content:center;font-weight:800;font-size:16px;flex:none;
  box-shadow:0 2px 6px rgba(212,147,10,.4)}
.logo__text{font-weight:750;font-size:16.5px;color:var(--brand);letter-spacing:-.01em;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.logo__accent{color:var(--accent)}
.logo--light .logo__text{color:#fff}
.logo--lg .logo__mark{width:38px;height:38px;font-size:20px;border-radius:11px}
.logo--lg .logo__text{font-size:20px}

/* ---- statement ---- */
.statement-hero{display:flex;justify-content:space-between;flex-wrap:wrap;gap:16px;
  background:radial-gradient(120% 140% at 100% 0%,#16346A 0%,#0B1D3A 70%);
  color:#fff;border-radius:var(--r-lg);padding:24px;box-shadow:var(--sh-md)}
.statement-hero__eyebrow{font-size:11.5px;font-weight:700;letter-spacing:.08em;
  text-transform:uppercase;color:var(--accent)}
.statement-hero__name{font-size:24px;font-weight:750;margin-top:4px}
.statement-hero__meta{font-size:13px;color:#C7D2E4;margin-top:5px}
.statement-hero__balance{text-align:right}
.statement-hero__balance-label{font-size:12px;color:#C7D2E4;font-weight:600}
.statement-hero__balance-value{font-size:30px;font-weight:800;margin-top:4px;font-variant-numeric:tabular-nums}
.statement-hero__balance-value.is-owed{color:#FCA5A5}
.statement-hero__balance-value.is-clear{color:#86EFAC}
.closing-bar{display:flex;align-items:center;justify-content:space-between;gap:8px;flex-wrap:wrap;
  border-radius:var(--r);padding:16px 22px;color:#fff;font-size:15px;font-weight:700}
.closing-bar.is-owed{background:var(--danger)}
.closing-bar.is-clear{background:var(--success)}
.closing-bar__value{font-size:22px;font-weight:800;font-variant-numeric:tabular-nums}
.statement-foot{text-align:center;color:var(--text-3);font-size:12px}

/* ---- spinner / skeleton ---- */
.spinner{display:inline-block;border:2.5px solid rgba(255,255,255,.4);border-top-color:#fff;
  border-radius:50%;animation:wt-spin .7s linear infinite;vertical-align:middle}
.btn--ghost .spinner,.btn--subtle .spinner{border-color:rgba(15,23,42,.2);border-top-color:var(--text)}
.sk{display:block;background:linear-gradient(90deg,#EaEef3 25%,#F3F6F9 37%,#EaEef3 63%);
  background-size:400% 100%;animation:wt-shimmer 1.4s ease infinite;border-radius:7px}
.sk-row{display:flex;justify-content:space-between;align-items:center;padding:12px 0;
  border-bottom:1px solid var(--border)}
.sk-row:last-child{border-bottom:none}

/* ---- toasts ---- */
.toast-wrap{position:fixed;right:16px;bottom:16px;z-index:9999;display:flex;flex-direction:column;
  gap:10px;padding-bottom:env(safe-area-inset-bottom,0);max-width:calc(100vw - 32px)}
.toast{display:flex;align-items:center;gap:9px;padding:12px 15px;border-radius:var(--r);
  color:#fff;font-size:13.5px;font-weight:600;box-shadow:var(--sh-lg);cursor:pointer;
  animation:wt-toast .25s cubic-bezier(.2,.8,.2,1);max-width:360px}
.toast--success{background:var(--success)}
.toast--error{background:var(--danger)}

/* ---- modal ---- */
.overlay{position:fixed;inset:0;background:rgba(11,29,58,.5);backdrop-filter:blur(2px);
  display:flex;align-items:flex-end;justify-content:center;padding:0;z-index:8000;animation:wt-fade .15s ease}
@media (min-width:560px){.overlay{align-items:center;padding:20px}}
.modal{width:100%;max-width:480px;background:var(--surface);border-radius:var(--r-lg) var(--r-lg) 0 0;
  box-shadow:var(--sh-lg);max-height:92vh;display:flex;flex-direction:column;
  animation:wt-sheet .26s cubic-bezier(.2,.9,.2,1)}
@media (min-width:560px){.modal{border-radius:var(--r-lg);animation:wt-pop .2s ease}}
.modal--md{max-width:480px}
.modal__head{display:flex;align-items:center;justify-content:space-between;gap:8px;
  padding:16px 18px;border-bottom:1px solid var(--border)}
.modal__title{margin:0;font-size:16px;font-weight:700;color:var(--text)}
.modal__body{padding:18px;overflow-y:auto}
.modal__foot{display:flex;justify-content:flex-end;gap:10px;padding:14px 18px;border-top:1px solid var(--border)}
.modal__foot .btn{min-width:96px}

/* ---- motion ---- */
@keyframes wt-spin{to{transform:rotate(360deg)}}
@keyframes wt-shimmer{0%{background-position:100% 50%}100%{background-position:0 50%}}
@keyframes wt-fade{from{opacity:0}to{opacity:1}}
@keyframes wt-rise{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
@keyframes wt-pop{from{opacity:0;transform:scale(.97)}to{opacity:1;transform:none}}
@keyframes wt-sheet{from{transform:translateY(100%)}to{transform:none}}
@keyframes wt-toast{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
@media (prefers-reduced-motion:reduce){
  *,*::before,*::after{animation-duration:.001ms!important;animation-iteration-count:1!important;
    transition-duration:.001ms!important}
}
`;
const styleTag = document.createElement("style");
styleTag.textContent = STYLES;
document.head.appendChild(styleTag);

/* ---------- Mount ---------- */
const root = createRoot(document.getElementById("root"));
root.render(<App />);

export default App;
