import Link from "next/link";
import { redirect } from "next/navigation";
import { BoutonDeconnexion } from "@/components/bouton-deconnexion";
import { lireContexte } from "@/lib/contexte";
import { accueilPourRole } from "@/lib/redirection";
import { createClient } from "@/lib/supabase/server";

// Point d'entrée unique : redirige chacun vers l'accueil de son rôle.
export default async function Accueil() {
  const contexte = await lireContexte();

  if (!contexte) {
    return (
      <main style={{ padding: "2rem", maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
        <h1>Be Smart Pilotage</h1>
        <p>Le pilotage financier simple pour votre entreprise.</p>
        <p style={{ display: "flex", gap: "1rem", marginTop: "1rem" }}>
          <Link href="/connexion">Se connecter</Link>
          <Link href="/inscription">Créer mon entreprise</Link>
        </p>
      </main>
    );
  }

  if (contexte.role) {
    redirect(accueilPourRole(contexte.role));
  }

  // Compte authentifié sans profil : inscription confirmée mais entreprise non
  // créée (étape interrompue). La fonction est idempotente : on la rejoue à
  // partir des noms saisis à l'inscription (ils ne servent qu'à nommer).
  const meta = contexte.user.user_metadata ?? {};
  if (typeof meta.nom_entreprise === "string" && meta.nom_entreprise.trim() !== "") {
    const supabase = await createClient();
    const { error } = await supabase.rpc("creer_entreprise_et_ceo", {
      p_nom: meta.nom_entreprise,
      p_secteur: typeof meta.secteur === "string" ? meta.secteur : "",
      p_nom_utilisateur: typeof meta.nom_ceo === "string" && meta.nom_ceo.trim() !== "" ? meta.nom_ceo : (contexte.user.email ?? "CEO"),
    });
    if (!error) {
      redirect("/parametrage");
    }
  }

  return (
    <main style={{ padding: "2rem", maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
      <h1>Compte non rattaché</h1>
      <p>
        Votre compte n&apos;est rattaché à aucune entreprise. Si vous avez été invité(e), demandez à votre
        gérant de vous renvoyer une invitation.
      </p>
      <BoutonDeconnexion />
    </main>
  );
}
