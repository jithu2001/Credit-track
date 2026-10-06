// Entry point on Supabase: wires the real Supabase clients into handler.ts.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the Supabase
// Edge runtime. The service-role key never leaves this function.

import { supabaseBackend } from "./backend.ts";
import { handle } from "./handler.ts";

const backend = supabaseBackend(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve((req) => handle(req, backend));
