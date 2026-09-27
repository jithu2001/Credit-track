// deno test supabase/functions/manage-staff/handler_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { ApiError, type Backend, type CompanyAccess, handle, type UserRow } from "./handler.ts";

const BIZ_A = "b0000000-0000-0000-0000-00000000000a";
const BIZ_B = "b0000000-0000-0000-0000-00000000000b";
const OWNER_A = "a0000000-0000-0000-0000-000000000001";
const STAFF_A = "a0000000-0000-0000-0000-000000000002";
const OWNER_A2 = "a0000000-0000-0000-0000-000000000003";
const STAFF_B = "a0000000-0000-0000-0000-000000000004";
const CO_A1 = "c0000000-0000-0000-0000-0000000000a1";
const CO_A2 = "c0000000-0000-0000-0000-0000000000a2";
const CO_B1 = "c0000000-0000-0000-0000-0000000000b1";

class FakeBackend implements Backend {
  users = new Map<string, UserRow>();
  authUsers = new Map<string, { email: string; password: string; metadata: Record<string, unknown>; ban?: string }>();
  access = new Map<string, CompanyAccess[]>();
  companies: Record<string, string[]> = { [BIZ_A]: [CO_A1, CO_A2], [BIZ_B]: [CO_B1] };
  failInsert = false;
  failSetCompanies = false;
  next = 100;

  constructor() {
    const add = (id: string, business_id: string, role: "OWNER" | "STAFF", is_active = true) => {
      this.users.set(id, { id, business_id, role, name: id, email: `${id}@x.io`, is_active });
      this.authUsers.set(id, { email: `${id}@x.io`, password: "old-password", metadata: { name: id } });
    };
    add(OWNER_A, BIZ_A, "OWNER");
    add(STAFF_A, BIZ_A, "STAFF");
    add(OWNER_A2, BIZ_A, "OWNER");
    add(STAFF_B, BIZ_B, "STAFF");
    this.access.set(STAFF_A, [{ company_id: CO_A1, areas: [], can_view_transactions: true }]);
  }

  authUserId(jwt: string) {
    return Promise.resolve(jwt.startsWith("jwt-") ? jwt.slice(4) : null);
  }
  getUser(id: string) {
    return Promise.resolve(this.users.get(id) ?? null);
  }
  companyIdsOfBusiness(b: string) {
    return Promise.resolve(this.companies[b] ?? []);
  }
  createAuthUser(p: { email: string; password: string; metadata: Record<string, unknown> }) {
    for (const u of this.authUsers.values()) {
      if (u.email === p.email) return Promise.reject(new ApiError("EMAIL_TAKEN", "taken"));
    }
    const id = `a0000000-0000-0000-0000-000000000${this.next++}`;
    this.authUsers.set(id, { ...p });
    return Promise.resolve(id);
  }
  deleteAuthUser(id: string) {
    this.authUsers.delete(id);
    return Promise.resolve();
  }
  getAuthMetadata(id: string) {
    return Promise.resolve(this.authUsers.get(id)!.metadata);
  }
  updateAuthUser(id: string, a: { password?: string; ban_duration?: string; user_metadata?: Record<string, unknown> }) {
    const u = this.authUsers.get(id)!;
    if (a.password) u.password = a.password;
    if (a.ban_duration) u.ban = a.ban_duration;
    if (a.user_metadata) u.metadata = a.user_metadata;
    return Promise.resolve();
  }
  insertStaff(
    p: { id: string; business_id: string; name: string; email: string; created_by: string; companies: CompanyAccess[] },
  ) {
    if (this.failInsert) return Promise.reject(new Error("db down"));
    this.users.set(p.id, { id: p.id, business_id: p.business_id, role: "STAFF", name: p.name, email: p.email, is_active: true });
    this.access.set(p.id, p.companies);
    return Promise.resolve();
  }
  setStaffCompanies(userId: string, _b: string, _actor: string, companies: CompanyAccess[]) {
    // Mirrors the SQL function: all or nothing.
    if (this.failSetCompanies) return Promise.reject(new Error("check_violation"));
    this.access.set(userId, companies);
    return Promise.resolve();
  }
  updateUserRow(id: string, _b: string, patch: { name?: string; is_active?: boolean }) {
    Object.assign(this.users.get(id)!, patch);
    return Promise.resolve();
  }
}

function call(body: unknown, as: string | null = OWNER_A) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (as) headers.Authorization = `Bearer jwt-${as}`;
  return new Request("http://localhost/manage-staff", { method: "POST", headers, body: JSON.stringify(body) });
}

async function run(backend: Backend, body: unknown, as: string | null = OWNER_A) {
  const res = await handle(call(body, as), backend, () => {});
  return { status: res.status, body: await res.json() };
}

const validCreate = {
  action: "create_staff",
  email: "  Ravi@Example.com ",
  password: "s3cret-pass",
  name: "Ravi",
  companies: [{ company_id: CO_A1 }, { company_id: CO_A2, areas: [" Pala ", "", "Pala"], can_view_transactions: false }],
};

Deno.test("missing JWT is rejected", async () => {
  const r = await run(new FakeBackend(), validCreate, null);
  assertEquals(r.status, 401);
  assertEquals(r.body.error.code, "UNAUTHENTICATED");
});

Deno.test("non-owner gets 403", async () => {
  const r = await run(new FakeBackend(), validCreate, STAFF_A);
  assertEquals(r.status, 403);
  assertEquals(r.body.error.code, "NOT_OWNER");
});

Deno.test("disabled owner gets 403", async () => {
  const b = new FakeBackend();
  b.users.get(OWNER_A)!.is_active = false;
  assertEquals((await run(b, validCreate)).status, 403);
});

Deno.test("create_staff creates auth user, row and normalised assignments", async () => {
  const b = new FakeBackend();
  const r = await run(b, validCreate);
  assertEquals(r.status, 200);
  const id = r.body.data.id;
  assertEquals(b.users.get(id)!.email, "ravi@example.com");
  assertEquals(b.users.get(id)!.role, "STAFF");
  assertEquals(b.authUsers.get(id)!.metadata.must_change_password, true);
  assertEquals(b.access.get(id), [
    { company_id: CO_A1, areas: [], can_view_transactions: true },
    { company_id: CO_A2, areas: ["Pala"], can_view_transactions: false },
  ]);
});

Deno.test("create_staff without companies is rejected", async () => {
  const b = new FakeBackend();
  const r = await run(b, { ...validCreate, companies: [] });
  assertEquals(r.status, 400);
  assertEquals(r.body.error.code, "INVALID_INPUT");
  assertEquals(b.authUsers.size, 4, "no auth user was created");
});

Deno.test("company of another business is rejected", async () => {
  const b = new FakeBackend();
  const r = await run(b, { ...validCreate, companies: [{ company_id: CO_B1 }] });
  assertEquals(r.status, 400);
  assertEquals(b.authUsers.size, 4);
});

Deno.test("owners cannot create owners (role is not an input)", async () => {
  const b = new FakeBackend();
  const r = await run(b, { ...validCreate, role: "OWNER" });
  assertEquals(r.status, 200);
  assertEquals(b.users.get(r.body.data.id)!.role, "STAFF");
});

Deno.test("duplicate email maps to EMAIL_TAKEN", async () => {
  const r = await run(new FakeBackend(), { ...validCreate, email: `${STAFF_A}@x.io` });
  assertEquals(r.status, 409);
  assertEquals(r.body.error.code, "EMAIL_TAKEN");
});

Deno.test("row insert failure rolls back the auth user", async () => {
  const b = new FakeBackend();
  b.failInsert = true;
  const r = await run(b, validCreate);
  assertEquals(r.status, 500);
  assertEquals(r.body.error.code, "INTERNAL");
  assertEquals(b.authUsers.size, 4);
  assert(![...b.authUsers.values()].some((u) => u.email === "ravi@example.com"));
});

Deno.test("short password is rejected and never echoed", async () => {
  const r = await run(new FakeBackend(), { ...validCreate, password: "short" });
  assertEquals(r.status, 400);
  assert(!JSON.stringify(r.body).includes('short"'));
});

Deno.test("set_companies replaces the set; empty list allowed", async () => {
  const b = new FakeBackend();
  let r = await run(b, { action: "set_companies", user_id: STAFF_A, companies: [{ company_id: CO_A2, areas: ["Kply"] }] });
  assertEquals(r.status, 200);
  assertEquals(b.access.get(STAFF_A), [{ company_id: CO_A2, areas: ["Kply"], can_view_transactions: true }]);
  r = await run(b, { action: "set_companies", user_id: STAFF_A, companies: [] });
  assertEquals(r.status, 200);
  assertEquals(b.access.get(STAFF_A), []);
});

Deno.test("failed set_companies leaves previous set", async () => {
  const b = new FakeBackend();
  b.failSetCompanies = true;
  const r = await run(b, { action: "set_companies", user_id: STAFF_A, companies: [{ company_id: CO_A2 }] });
  assertEquals(r.status, 500);
  assertEquals(b.access.get(STAFF_A), [{ company_id: CO_A1, areas: [], can_view_transactions: true }]);
});

Deno.test("cross-business user_id looks like not found", async () => {
  for (const action of ["update_staff", "set_companies", "set_active", "reset_password"]) {
    const r = await run(new FakeBackend(), {
      action,
      user_id: STAFF_B,
      name: "x",
      companies: [],
      active: false,
      password: "12345678",
    });
    assertEquals(r.status, 404, action);
    assertEquals(r.body.error.code, "NOT_FOUND");
  }
});

Deno.test("owner accounts cannot be changed", async () => {
  for (const action of ["update_staff", "set_companies", "set_active", "reset_password"]) {
    const r = await run(new FakeBackend(), {
      action,
      user_id: OWNER_A2,
      name: "x",
      companies: [],
      active: false,
      password: "12345678",
    });
    assertEquals(r.status, 403, action);
  }
});

Deno.test("set_active disables row and bans, enabling unbans", async () => {
  const b = new FakeBackend();
  await run(b, { action: "set_active", user_id: STAFF_A, active: false });
  assertEquals(b.users.get(STAFF_A)!.is_active, false);
  assertEquals(b.authUsers.get(STAFF_A)!.ban, "876000h");
  await run(b, { action: "set_active", user_id: STAFF_A, active: true });
  assertEquals(b.users.get(STAFF_A)!.is_active, true);
  assertEquals(b.authUsers.get(STAFF_A)!.ban, "none");
});

Deno.test("reset_password sets password and must_change_password, keeps metadata", async () => {
  const b = new FakeBackend();
  const r = await run(b, { action: "reset_password", user_id: STAFF_A, password: "brand-new-1" });
  assertEquals(r.status, 200);
  assertEquals(b.authUsers.get(STAFF_A)!.password, "brand-new-1");
  assertEquals(b.authUsers.get(STAFF_A)!.metadata, { name: STAFF_A, must_change_password: true });
});

Deno.test("update_staff renames", async () => {
  const b = new FakeBackend();
  await run(b, { action: "update_staff", user_id: STAFF_A, name: "  Suresh " });
  assertEquals(b.users.get(STAFF_A)!.name, "Suresh");
});

Deno.test("unknown action and non-POST", async () => {
  assertEquals((await run(new FakeBackend(), { action: "drop_tables" })).status, 400);
  const res = await handle(new Request("http://x", { method: "GET" }), new FakeBackend());
  assertEquals(res.status, 405);
  await res.body?.cancel();
});
