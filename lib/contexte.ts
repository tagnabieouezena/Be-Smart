import "server-only";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";

export type RoleAffiche = "ceo" | "comptable" | "supervision";

export type Contexte = {
  user: User;
  role: RoleAffiche | null; // null : compte authentifié sans profil (inscription non finalisée)
  nom: string;
  entrepriseNom: string | null;
};

// Contexte de l'utilisateur connecté, lu côté serveur. Sert à construire la
// navigation et la page d'accueil : ce n'est PAS un contrôle d'accès, chaque
// page garde son propre contrôle de rôle.
export async function lireContexte(): Promise<Contexte | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return null;

  if (user.app_metadata?.super_admin === true) {
    return { user, role: "supervision", nom: user.email ?? "Supervision", entrepriseNom: null };
  }

  const { data: profil } = await supabase
    .from("utilisateurs")
    .select("nom, role, entreprises(nom)")
    .eq("id", user.id)
    .maybeSingle();

  if (!profil) {
    return { user, role: null, nom: user.email ?? "", entrepriseNom: null };
  }

  const entreprise = profil.entreprises as unknown as { nom: string } | null;

  return {
    user,
    role: profil.role as RoleAffiche,
    nom: profil.nom,
    entrepriseNom: entreprise?.nom ?? null,
  };
}
