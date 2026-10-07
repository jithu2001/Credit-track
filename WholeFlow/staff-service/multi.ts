// Entry point on the WholeFlow server: one staff service for every business.
// nginx sends /b/<slug>/functions/v1/manage-staff here; the business's
// address and service key come from the control service on this machine
// (cached for a minute). handler.ts is unchanged.
//
//   CONTROL_URL     http://127.0.0.1:8100
//   INTERNAL_TOKEN  shared with the control service
//   PORT            8200

import { apiBackend } from "./backend.ts";
import { type Backend, corsHeaders, handle } from "./handler.ts";

const controlUrl = Deno.env.get("CONTROL_URL") ?? "http://127.0.0.1:8100";
const token = Deno.env.get("INTERNAL_TOKEN") ?? "";
const port = Number(Deno.env.get("PORT") ?? "8200");

const PATH = /^\/b\/([a-z][a-z0-9]{1,19})\/functions\/v1\/manage-staff\/?$/;
const cache = new Map<string, { backend: Backend; until: number }>();

async function backendFor(slug: string): Promise<Backend | null> {
  const hit = cache.get(slug);
  if (hit && hit.until > Date.now()) return hit.backend;
  const res = await fetch(`${controlUrl}/control/internal/tenant/${slug}`, { headers: { "X-Internal-Token": token } });
  if (!res.ok) return null;
  const t = await res.json() as { base_url: string; service_key: string };
  const backend = apiBackend(t.base_url, t.service_key);
  cache.set(slug, { backend, until: Date.now() + 60_000 });
  return backend;
}

Deno.serve({ hostname: "127.0.0.1", port }, async (req) => {
  const m = PATH.exec(new URL(req.url).pathname);
  const backend = m ? await backendFor(m[1]) : null;
  if (!backend) {
    return new Response(JSON.stringify({ error: { code: "NOT_FOUND", message: "No such business." } }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  return handle(req, backend);
});
