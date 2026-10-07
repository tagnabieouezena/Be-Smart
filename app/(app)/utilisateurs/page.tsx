import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { FormulaireInvitationComptable } from "@/components/formulaire-invitation-comptable";
import { BoutonRenvoyerInvitation } from "@/components/bouton-renvoyer-invitation";
import { createAdminClient } from "@/lib/supabase/admin";

export default async function UtilisateursPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/connexion");
  }

  const { data: profil } = await supabase
    .from("utilisateurs")
    .select("role, entreprise_id")
    .eq("id", user.id)
    .single();

  // La liste elle-même reste filtrée par RLS (isolation_entreprise_lecture_utilisateurs) :
  // ceci n'est pas le contrôle de sécurité, juste l'affichage.
  const { data: utilisateurs } = await supabase
    .from("utilisateurs")
    .select("id, nom, email, role, created_at")
    .order("created_at", { ascending: true });

  // Statut d'activation des comptables (visible du CEO seulement). Il vit dans
  // Supabase Auth, hors de portée de la RLS : lecture avec le client admin,
  // uniquement après avoir vérifié le rôle CEO ci-dessus, et seulement pour
  // les comptables que la RLS a déjà restreints à l'entreprise du CEO.
  const nonActives = new Set<string>();
  if (profil?.role === "ceo") {
    const admin = createAdminClient();
    for (const u of utilisateurs ?? []) {
      if (u.role !== "comptable") continue;
      const { data } = await admin.auth.admin.getUserById(u.id);
      const compte = data?.user;
      if (!compte) continue;
      const active =
        Boolean(compte.email_confirmed_at) && (!compte.invited_at || compte.user_metadata?.mot_de_passe_defini === true);
      if (!active) nonActives.add(u.id);
    }
  }

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Utilisateurs de mon entreprise</h1>
      <ul>
        {utilisateurs?.map((u) => (
          <li key={u.id}>
            {u.nom} — {u.email} ({u.role})
            {nonActives.has(u.id) && (
              <>
                {" "}
                <strong>— invitation envoyée, compte non activé</strong>{" "}
                <BoutonRenvoyerInvitation utilisateurId={u.id} />
              </>
            )}
          </li>
        ))}
      </ul>

      {profil?.role === "ceo" && (
        <>
          <h2>Inviter un comptable</h2>
          <FormulaireInvitationComptable />
        </>
      )}
    </main>
  );
}
