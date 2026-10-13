import "server-only";
import { notFound, redirect } from "next/navigation";
import { lireContexte, type RoleAffiche } from "@/lib/contexte";
import { cheminInterneSur } from "@/lib/redirection";

// Garde d'accès d'une page de l'application, appelée en tête de chaque page.
//   - non connecté            : redirection vers /connexion ;
//   - supervision Be Smart    : 404 sur toute page autre que /supervision ;
//   - rôle non autorisé       : 404 (même réponse que pour une page inexistante) ;
//   - compte sans profil      : redirection vers « / » en conservant la page demandée
//     (`next`) : « / » recrée l'espace ou affiche « Compte non rattaché ». Jamais
//     de renvoi vers /connexion pour une session valide.
// C'est un contrôle côté serveur, en plus de la RLS (qui reste inchangée) : la
// page ne rend rien avant d'avoir été autorisée.
export async function exigerRole(rolesAutorises: ("ceo" | "comptable")[], chemin: string) {
  const contexte = await lireContexte();

  if (!contexte) {
    redirect("/connexion");
  }

  const role: RoleAffiche | null = contexte.role;
  if (role === null) {
    const suite = cheminInterneSur(chemin);
    redirect(suite ? `/?next=${encodeURIComponent(suite)}` : "/");
  }
  if (role === "supervision" || !rolesAutorises.includes(role)) {
    notFound();
  }

  return contexte;
}
