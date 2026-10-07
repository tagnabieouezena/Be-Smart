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
