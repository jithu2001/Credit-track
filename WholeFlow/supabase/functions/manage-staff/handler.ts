// manage-staff: owner-only staff account management for the WholeFlow mobile app.
//
// The mobile app only has the anon key, so it cannot create Supabase Auth users.
// This function holds the service-role key and does it on the owner's behalf,
// producing the same shape as the sync service's Cloud Sync page
// (WholeFlow/internal/cloud/supabase/users.go): an email-confirmed Auth user
// plus a public.users row, rolled back if the row cannot be written. Disabling
// sets users.is_active = false and bans the Auth user.
//
// All logic lives here behind the Backend interface so it can be tested without
// a Supabase project; index.ts wires the real clients.

export type Role = "OWNER" | "STAFF";

export interface UserRow {
  id: string;
  business_id: string;
  role: Role;
  name: string;
  email: string | null;
  is_active: boolean;
}

/** Per company: the whole company, or only the shops in the listed sites. */
export interface CompanyAccess {
  company_id: string;
  full_company: boolean;
  site_ids: string[];
  can_view_transactions: boolean;
}

export interface SiteRef {
  id: string;
  company_id: string;
}

export interface Backend {
  /** Resolves the caller's JWT to an Auth user id, or null when invalid. */
  authUserId(jwt: string): Promise<string | null>;
  getUser(id: string): Promise<UserRow | null>;
  companyIdsOfBusiness(businessId: string): Promise<string[]>;
  sitesOfBusiness(businessId: string): Promise<SiteRef[]>;
  /** Throws ApiError("EMAIL_TAKEN") when the address is registered already. */
  createAuthUser(p: { email: string; password: string; metadata: Record<string, unknown> }): Promise<string>;
  deleteAuthUser(id: string): Promise<void>;
  getAuthMetadata(id: string): Promise<Record<string, unknown>>;
  updateAuthUser(
    id: string,
    attrs: { password?: string; ban_duration?: string; user_metadata?: Record<string, unknown> },
  ): Promise<void>;
  /** users row + staff_company_access rows in one transaction (admin_insert_staff). */
  insertStaff(
    p: { id: string; business_id: string; name: string; email: string; created_by: string; companies: CompanyAccess[] },
  ): Promise<void>;
  /** Replaces the assignment set in one transaction (admin_set_staff_companies). */
  setStaffCompanies(userId: string, businessId: string, actor: string, companies: CompanyAccess[]): Promise<void>;
  updateUserRow(
    id: string,
    businessId: string,
    patch: { name?: string; is_active?: boolean; requires_check_in?: boolean },
  ): Promise<void>;
}

export type ErrorCode = "UNAUTHENTICATED" | "NOT_OWNER" | "INVALID_INPUT" | "EMAIL_TAKEN" | "NOT_FOUND" | "INTERNAL";

const STATUS: Record<ErrorCode, number> = {
  UNAUTHENTICATED: 401,
  NOT_OWNER: 403,
  INVALID_INPUT: 400,
  EMAIL_TAKEN: 409,
  NOT_FOUND: 404,
  INTERNAL: 500,
};

export class ApiError extends Error {
  constructor(readonly code: ErrorCode, message: string) {
    super(message);
  }
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const BAN_FOREVER = "876000h"; // ~100 years, same as the sync service
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MIN_PASSWORD = 8;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export async function handle(req: Request, backend: Backend, log: (msg: string) => void = console.error): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: { code: "INVALID_INPUT", message: "Use POST." } });
  try {
    const caller = await requireOwner(req, backend);
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      throw new ApiError("INVALID_INPUT", "Body must be JSON.");
    }
    if (typeof body !== "object" || body === null) throw new ApiError("INVALID_INPUT", "Body must be a JSON object.");
    const data = await dispatch(body, caller, backend);
    return json(200, { data });
  } catch (e) {
    if (e instanceof ApiError) return json(STATUS[e.code], { error: { code: e.code, message: e.message } });
    // Never log request bodies: they can contain passwords.
    log(`manage-staff: unexpected error: ${e instanceof Error ? e.message : String(e)}`);
    return json(500, { error: { code: "INTERNAL", message: "Something went wrong. Please try again." } });
  }
}

async function requireOwner(req: Request, backend: Backend): Promise<UserRow> {
  const auth = req.headers.get("Authorization") ?? "";
  const jwt = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!jwt) throw new ApiError("UNAUTHENTICATED", "Sign in again.");
  const uid = await backend.authUserId(jwt);
  if (!uid) throw new ApiError("UNAUTHENTICATED", "Sign in again.");
  const caller = await backend.getUser(uid);
  if (!caller || caller.role !== "OWNER" || !caller.is_active) {
    throw new ApiError("NOT_OWNER", "Only the business owner can manage staff.");
  }
  return caller;
}

async function dispatch(body: Record<string, unknown>, caller: UserRow, backend: Backend): Promise<unknown> {
  switch (body.action) {
    case "create_staff":
      return await createStaff(body, caller, backend);
    case "update_staff": {
      const target = await requireStaff(body.user_id, caller, backend);
      const name = requireName(body.name);
      await backend.updateUserRow(target.id, caller.business_id, { name });
      return { id: target.id };
    }
    case "set_companies": {
      const target = await requireStaff(body.user_id, caller, backend);
      const companies = await parseCompanies(body.companies, caller, backend, false);
      await backend.setStaffCompanies(target.id, caller.business_id, caller.id, companies);
      return { id: target.id, companies };
    }
    case "set_check_in": {
      const target = await requireStaff(body.user_id, caller, backend);
      if (typeof body.required !== "boolean") throw new ApiError("INVALID_INPUT", "required must be true or false.");
      await backend.updateUserRow(target.id, caller.business_id, { requires_check_in: body.required });
      return { id: target.id, requires_check_in: body.required };
    }
    case "set_active": {
      const target = await requireStaff(body.user_id, caller, backend);
      if (typeof body.active !== "boolean") throw new ApiError("INVALID_INPUT", "active must be true or false.");
      await backend.updateUserRow(target.id, caller.business_id, { is_active: body.active });
      await backend.updateAuthUser(target.id, { ban_duration: body.active ? "none" : BAN_FOREVER });
      return { id: target.id, is_active: body.active };
    }
    case "reset_password": {
      const target = await requireStaff(body.user_id, caller, backend);
      const password = requirePassword(body.password);
      const metadata = await backend.getAuthMetadata(target.id);
      await backend.updateAuthUser(target.id, { password, user_metadata: { ...metadata, must_change_password: true } });
      return { id: target.id };
    }
    default:
      throw new ApiError("INVALID_INPUT", "Unknown action.");
  }
}

async function createStaff(body: Record<string, unknown>, caller: UserRow, backend: Backend) {
  const name = requireName(body.name);
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  if (!EMAIL.test(email) || email.length > 254) throw new ApiError("INVALID_INPUT", "Enter a valid email address.");
  const password = requirePassword(body.password);
  const companies = await parseCompanies(body.companies, caller, backend, true);
  const checkIn = body.requires_check_in ?? false;
  if (typeof checkIn !== "boolean") throw new ApiError("INVALID_INPUT", "requires_check_in must be true or false.");

  const id = await backend.createAuthUser({
    email,
    password,
    metadata: { name, business_id: caller.business_id, role: "STAFF", must_change_password: true },
  });
  try {
    await backend.insertStaff({ id, business_id: caller.business_id, name, email, created_by: caller.id, companies });
    if (checkIn) await backend.updateUserRow(id, caller.business_id, { requires_check_in: true });
  } catch (e) {
    try {
      await backend.deleteAuthUser(id);
    } catch {
      // Best effort, as in the sync service; the original error matters more.
    }
    throw e;
  }
  return { id, email, name, role: "STAFF", is_active: true, requires_check_in: checkIn, companies };
}

async function requireStaff(userId: unknown, caller: UserRow, backend: Backend): Promise<UserRow> {
  if (typeof userId !== "string" || !UUID.test(userId)) throw new ApiError("INVALID_INPUT", "user_id is missing.");
  const target = await backend.getUser(userId);
  // Another business's user and an unknown id look the same to the caller.
  if (!target || target.business_id !== caller.business_id) throw new ApiError("NOT_FOUND", "No such staff member.");
  if (target.role !== "STAFF") throw new ApiError("NOT_OWNER", "Owner accounts cannot be changed here.");
  return target;
}

function requireName(v: unknown): string {
  const name = typeof v === "string" ? v.trim() : "";
  if (!name || name.length > 100) throw new ApiError("INVALID_INPUT", "Enter a name (up to 100 characters).");
  return name;
}

function requirePassword(v: unknown): string {
  if (typeof v !== "string" || v.length < MIN_PASSWORD || v.length > 72) {
    throw new ApiError("INVALID_INPUT", `Password must be ${MIN_PASSWORD} to 72 characters.`);
  }
  return v;
}

async function parseCompanies(v: unknown, caller: UserRow, backend: Backend, requireOne: boolean): Promise<CompanyAccess[]> {
  if (!Array.isArray(v)) throw new ApiError("INVALID_INPUT", "companies must be a list.");
  if (requireOne && v.length === 0) throw new ApiError("INVALID_INPUT", "Assign at least one company.");
  const allowed = new Set(await backend.companyIdsOfBusiness(caller.business_id));
  const siteCompany = new Map(
    (await backend.sitesOfBusiness(caller.business_id)).map((s) => [s.id.toLowerCase(), s.company_id.toLowerCase()]),
  );
  const seen = new Set<string>();
  const out: CompanyAccess[] = [];
  for (const item of v) {
    if (typeof item !== "object" || item === null) throw new ApiError("INVALID_INPUT", "Invalid company entry.");
    const c = item as Record<string, unknown>;
    const id = typeof c.company_id === "string" ? c.company_id.toLowerCase() : "";
    if (!UUID.test(id) || !allowed.has(id)) {
      throw new ApiError("INVALID_INPUT", "A selected company does not belong to your business.");
    }
    if (seen.has(id)) continue;
    seen.add(id);
    const full = c.full_company ?? true;
    if (typeof full !== "boolean") throw new ApiError("INVALID_INPUT", "full_company must be true or false.");
    const sitesIn = c.site_ids ?? [];
    if (!Array.isArray(sitesIn) || sitesIn.some((s) => typeof s !== "string")) {
      throw new ApiError("INVALID_INPUT", "site_ids must be a list.");
    }
    const siteIds = full ? [] : [...new Set((sitesIn as string[]).map((s) => s.toLowerCase()))];
    if (siteIds.some((s) => siteCompany.get(s) !== id)) {
      throw new ApiError("INVALID_INPUT", "A selected site does not belong to that company.");
    }
    if (!full && siteIds.length === 0) {
      throw new ApiError("INVALID_INPUT", "Choose at least one site, or give the full company.");
    }
    const cvt = c.can_view_transactions ?? true;
    if (typeof cvt !== "boolean") throw new ApiError("INVALID_INPUT", "can_view_transactions must be true or false.");
    out.push({ company_id: id, full_company: full, site_ids: siteIds, can_view_transactions: cvt });
  }
  return out;
}
