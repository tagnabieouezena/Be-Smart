// Redirections : seul un chemin relatif interne (un seul « / » initial) est
// accepté. Tout le reste (URL absolue, « //hote », « /\hote », caractères de
// contrôle) est refusé : l'appelant retombe alors sur l'accueil du rôle.
export function cheminInterneSur(valeur: string | null | undefined): string | null {
  if (!valeur || !valeur.startsWith("/")) return null;
  if (valeur.startsWith("//")) return null;
  if (/[\\\u0000-\u001f\u007f]/.test(valeur)) return null;

  try {
    const base = "http://interne.invalid";
    if (new URL(valeur, base).origin !== base) return null;
  } catch {
    return null;
  }

  return valeur;
}

export function accueilPourRole(role: "ceo" | "comptable" | "supervision"): string {
  if (role === "ceo") return "/ecarts";
  if (role === "comptable") return "/transactions";
  return "/supervision";
}

// Pages que chaque rôle peut ouvrir. Sert à décider si un `next` interne est
// suivi après la création de l'espace ; ce n'est PAS le contrôle d'accès (chaque
// page garde son propre contrôle de rôle côté serveur, et la RLS reste inchangée).
const PAGES_PAR_ROLE: Record<"ceo" | "comptable" | "supervision", string[]> = {
  ceo: ["/ecarts", "/budgets", "/transactions", "/creances", "/parametrage", "/utilisateurs"],
  comptable: ["/transactions", "/creances"],
  supervision: ["/supervision"],
};

export function cheminAutorisePourRole(
  chemin: string | null | undefined,
  role: "ceo" | "comptable" | "supervision",
): boolean {
  const interne = cheminInterneSur(chemin);
  if (!interne) return false;
  const base = interne.split(/[?#]/)[0];
  return PAGES_PAR_ROLE[role].some((page) => base === page || base === `${page}/`);
}

// Destination après connexion ou création de l'espace : `next` s'il est interne
// ET autorisé pour ce rôle, sinon l'accueil du rôle.
export function destinationPourRole(
  next: string | null | undefined,
  role: "ceo" | "comptable" | "supervision",
): string {
  return cheminAutorisePourRole(next, role) ? (cheminInterneSur(next) as string) : accueilPourRole(role);
}
