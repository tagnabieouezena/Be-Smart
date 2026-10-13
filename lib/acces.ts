import "server-only";
import { notFound, redirect } from "next/navigation";
import { lireContexte, type RoleAffiche } from "@/lib/contexte";

// Garde d'accès d'une page de l'application, appelée en tête de chaque page.
//   - non connecté            : redirection vers /connexion ;
//   - supervision Be Smart    : 404 sur toute page autre que /supervision ;
//   - rôle non autorisé       : 404 (même réponse que pour une page inexistante) ;
//   - compte sans profil      : on laisse la page appliquer son propre traitement.
// C'est un contrôle côté serveur, en plus de la RLS (qui reste inchangée) : la
// page ne rend rien avant d'avoir été autorisée.
export async function exigerRole(rolesAutorises: ("ceo" | "comptable")[]) {
  const contexte = await lireContexte();

  if (!contexte) {
    redirect("/connexion");
  }

  const role: RoleAffiche | null = contexte.role;
  if (role === "supervision" || (role !== null && !rolesAutorises.includes(role))) {
    notFound();
  }

  return contexte;
}
