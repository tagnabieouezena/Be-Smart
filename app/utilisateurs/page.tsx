import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { FormulaireInvitationComptable } from "@/components/formulaire-invitation-comptable";

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

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Utilisateurs de mon entreprise</h1>
      <ul>
        {utilisateurs?.map((u) => (
          <li key={u.id}>
            {u.nom} — {u.email} ({u.role})
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
