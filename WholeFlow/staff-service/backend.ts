// The real Backend behind handler.ts, for one business on the WholeFlow
// server: its login (GoTrue admin API) and data API (PostgREST), reached with
// the business's service key through the supabase-js client library.
// Used by multi.ts.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { ApiError, type Backend, type CompanyAccess, type UserRow } from "./handler.ts";

function fail(op: string, err: { message?: string } | null): never {
  throw new Error(`${op}: ${err?.message ?? "unknown error"}`);
}

/** The Backend for one business (its base URL + service key). */
export function apiBackend(url: string, serviceKey: string): Backend {
  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return {
    async authUserId(jwt) {
      const { data, error } = await admin.auth.getUser(jwt);
      return error || !data.user ? null : data.user.id;
    },

    async getUser(id) {
      const { data, error } = await admin.from("users")
        .select("id,business_id,role,name,email,is_active")
        .eq("id", id)
        .maybeSingle();
      if (error) fail("get-user", error);
      return data as UserRow | null;
    },

    async companyIdsOfBusiness(businessId) {
      const { data, error } = await admin.from("tally_companies").select("id").eq("business_id", businessId);
      if (error) fail("list-companies", error);
      return (data ?? []).map((r: { id: string }) => r.id.toLowerCase());
    },

    async sitesOfBusiness(businessId) {
      const { data, error } = await admin.from("sites").select("id,company_id").eq("business_id", businessId);
      if (error) fail("list-sites", error);
      return (data ?? []) as { id: string; company_id: string }[];
    },

    async createAuthUser({ email, password, metadata }) {
      const { data, error } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: metadata,
      });
      if (error) {
        const code = (error as { code?: string }).code;
        if (code === "email_exists" || code === "user_already_exists" || /already (been )?registered/i.test(error.message)) {
          throw new ApiError("EMAIL_TAKEN", "An account with this email already exists.");
        }
        if (code === "weak_password") throw new ApiError("INVALID_INPUT", "Choose a stronger password.");
        fail("create-auth-user", error);
      }
      return data.user!.id;
    },

    async deleteAuthUser(id) {
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) fail("delete-auth-user", error);
    },

    async getAuthMetadata(id) {
      const { data, error } = await admin.auth.admin.getUserById(id);
      if (error) fail("get-auth-user", error);
      return (data.user?.user_metadata ?? {}) as Record<string, unknown>;
    },

    async updateAuthUser(id, attrs) {
      const { error } = await admin.auth.admin.updateUserById(id, attrs);
      if (error) fail("update-auth-user", error);
    },

    async insertStaff(p) {
      const { error } = await admin.rpc("admin_insert_staff", {
        p_id: p.id,
        p_business_id: p.business_id,
        p_name: p.name,
        p_email: p.email,
        p_created_by: p.created_by,
        p_companies: p.companies,
      });
      if (error) fail("insert-staff", error);
    },

    async setStaffCompanies(userId: string, businessId: string, actor: string, companies: CompanyAccess[]) {
      const { error } = await admin.rpc("admin_set_staff_companies", {
        p_user_id: userId,
        p_business_id: businessId,
        p_actor: actor,
        p_companies: companies,
      });
      if (error) fail("set-staff-companies", error);
    },

    async updateUserRow(id, businessId, patch) {
      const { error } = await admin.from("users").update(patch).eq("id", id).eq("business_id", businessId).eq("role", "STAFF");
      if (error) fail("update-user", error);
    },
  };
}
