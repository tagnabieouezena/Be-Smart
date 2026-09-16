import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

// Client "session utilisateur" : respecte les policies RLS de la personne
// connectée. À utiliser pour toute lecture/écriture normale côté serveur —
// jamais pour contourner une vérification de rôle.
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Appelé depuis un Server Component : les cookies ne peuvent
            // pas y être modifiés. Sans conséquence si un middleware de
            // rafraîchissement de session existe par ailleurs.
          }
        },
      },
    },
  );
}
