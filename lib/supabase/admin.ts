import "server-only";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";

// Client privilégié (service_role) : contourne RLS. Ne jamais importer
// depuis un composant client ni utiliser sans avoir d'abord vérifié le rôle
// de l'appelant avec le client "session" (voir app/api/comptable/inviter).
export function createAdminClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}
