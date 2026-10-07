import { NextResponse, type NextRequest } from "next/server";
import type { EmailOtpType } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { cheminInterneSur } from "@/lib/redirection";

const TYPES_ACCEPTES: EmailOtpType[] = ["signup", "invite", "recovery"];

// 303 : le navigateur rejoue la destination en GET après ce POST.
function vers(request: NextRequest, chemin: string) {
  return NextResponse.redirect(new URL(chemin, request.url), 303);
}

// Vérification du jeton, uniquement en POST : le lien de l'e-mail ouvre la page
// /auth/confirm (GET), qui ne consomme rien ; seul le clic sur « Confirmer »
// arrive ici. Un scanner ou un client de messagerie qui pré-ouvre le lien ne
// peut donc plus consommer le jeton à usage unique.
export async function POST(request: NextRequest) {
  const formulaire = await request.formData();
  const tokenHash = formulaire.get("token_hash");
  const type = formulaire.get("type") as EmailOtpType | null;
  // `next` n'est suivi que s'il s'agit d'un chemin interne ; sinon on garde
  // la destination par défaut du type de lien.
  const next = cheminInterneSur(typeof formulaire.get("next") === "string" ? (formulaire.get("next") as string) : null);

  if (typeof tokenHash !== "string" || !tokenHash || !type || !TYPES_ACCEPTES.includes(type)) {
    return vers(request, `/auth/lien-invalide?type=${type && TYPES_ACCEPTES.includes(type) ? type : "inconnu"}`);
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });

  if (error || !data.user) {
    return vers(request, `/auth/lien-invalide?type=${type}`);
  }

  if (type === "invite") {
    return vers(request, "/auth/definir-mot-de-passe");
  }

  if (type === "recovery") {
    return vers(request, "/auth/nouveau-mot-de-passe");
  }

  // type === "signup" : e-mail confirmé, on crée l'entreprise et le profil CEO.
  // Les métadonnées ne servent qu'à nommer ; le rôle et l'entreprise sont fixés
  // par la fonction SQL (idempotente : un lien rouvert ne crée rien de plus).
  const meta = data.user.user_metadata ?? {};
  const nomEntreprise =
    typeof meta.nom_entreprise === "string" && meta.nom_entreprise.trim() !== "" ? meta.nom_entreprise : "Mon entreprise";
  const nomCeo =
    typeof meta.nom_ceo === "string" && meta.nom_ceo.trim() !== "" ? meta.nom_ceo : (data.user.email ?? "CEO");

  const { error: rpcError } = await supabase.rpc("creer_entreprise_et_ceo", {
    p_nom: nomEntreprise,
    p_secteur: typeof meta.secteur === "string" ? meta.secteur : "",
    p_nom_utilisateur: nomCeo,
  });

  if (rpcError) {
    return vers(request, "/auth/lien-invalide?type=signup-echec");
  }

  return vers(request, next ?? "/parametrage");
}
