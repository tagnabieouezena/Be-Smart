// Test de route (adversarial) : accès aux pages de l'application par rôle.
//
// Exécuté contre un serveur Next démarré (npx next start) et la stack Supabase
// locale, avec des utilisateurs authentifiés réels (jetons obtenus par mot de
// passe, session transmise par cookie comme le fait le navigateur). Seule la
// création du compte « sans profil » passe par l'API admin : c'est un jeu de
// données, pas le comportement testé.
//
// Variables : APP_URL, NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY,
// SUPABASE_SERVICE_ROLE_KEY. Prévu pour une base fraîchement réinitialisée
// (seed), comme les autres tests : il ajoute une transaction de test.

const APP = process.env.APP_URL ?? "http://localhost:3010";
const SB = process.env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;

let echecs = 0;
function verifier(libelle, ok, detail = "") {
  console.log(`${ok ? "OK   " : "ECHEC"} | ${libelle}${detail ? ` — ${detail}` : ""}`);
  if (!ok) echecs += 1;
}

async function json(url, options = {}) {
  const reponse = await fetch(url, options);
  const texte = await reponse.text();
  let corps = null;
  try {
    corps = JSON.parse(texte);
  } catch {
    corps = texte;
  }
  return { status: reponse.status, corps };
}

async function connexion(email, motDePasse) {
  const { status, corps } = await json(`${SB}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: motDePasse }),
  });
  if (status !== 200) throw new Error(`connexion ${email} : HTTP ${status}`);
  return corps;
}

// Même nom de cookie que @supabase/ssr : sb-<premier label du nom d'hôte>-auth-token.
function cookie(session) {
  const cle = `sb-${new URL(SB).hostname.split(".")[0]}-auth-token`;
  return `${cle}=base64-${Buffer.from(JSON.stringify(session)).toString("base64url")}`;
}

async function page(chemin, session) {
  const reponse = await fetch(`${APP}${chemin}`, {
    redirect: "manual",
    headers: session ? { Cookie: cookie(session) } : {},
  });
  const texte = await reponse.text();
  return { status: reponse.status, location: reponse.headers.get("location"), texte };
}

const PAGES = ["/ecarts", "/budgets", "/transactions", "/creances", "/parametrage", "/utilisateurs", "/supervision"];

// Statut attendu de chaque page, par rôle.
const ATTENDU = {
  ceo: { "/ecarts": 200, "/budgets": 200, "/transactions": 200, "/creances": 200, "/parametrage": 200, "/utilisateurs": 200, "/supervision": 404 },
  comptable: { "/ecarts": 404, "/budgets": 404, "/transactions": 200, "/creances": 200, "/parametrage": 404, "/utilisateurs": 404, "/supervision": 404 },
  supervision: { "/ecarts": 404, "/budgets": 404, "/transactions": 404, "/creances": 404, "/parametrage": 404, "/utilisateurs": 404, "/supervision": 200 },
};

const COMPTES = {
  ceo: "ceo-a@test.besmart.local",
  comptable: "comptable-a@test.besmart.local",
  supervision: "supervision@besmart.local",
};

const sessions = {};
for (const [role, email] of Object.entries(COMPTES)) {
  sessions[role] = await connexion(email, "mot-de-passe-test");
}

// 1. Matrice rôle x page : même réponse (404) pour toute page interdite.
for (const [role, attendus] of Object.entries(ATTENDU)) {
  for (const chemin of PAGES) {
    const { status } = await page(chemin, sessions[role]);
    verifier(`${role} ${chemin}`, status === attendus[chemin], `HTTP ${status}, attendu ${attendus[chemin]}`);
  }
}

// 2. Sans session : redirection vers /connexion sur les pages de module.
for (const chemin of PAGES.filter((c) => c !== "/supervision")) {
  const { status, location } = await page(chemin, null);
  verifier(`sans session ${chemin}`, status === 307 && (location ?? "").endsWith("/connexion"), `HTTP ${status} -> ${location}`);
}

// 3. Accueil : redirection vers l'accueil du rôle.
for (const [role, cible] of [["ceo", "/ecarts"], ["comptable", "/transactions"], ["supervision", "/supervision"]]) {
  const { status, location } = await page("/", sessions[role]);
  verifier(`accueil ${role}`, status === 307 && (location ?? "").endsWith(cible), `HTTP ${status} -> ${location}`);
}

// 4. Barre de navigation : liens affichés par rôle.
for (const [role, chemin, liens, absents] of [
  ["comptable", "/transactions", ["/transactions", "/creances"], ["/ecarts", "/budgets", "/parametrage", "/utilisateurs"]],
  ["ceo", "/ecarts", ["/ecarts", "/budgets", "/transactions", "/creances", "/parametrage", "/utilisateurs"], ["/supervision"]],
]) {
  const { texte } = await page(chemin, sessions[role]);
  const nav = texte.match(/<nav[\s\S]*?<\/nav>/)?.[0] ?? "";
  verifier(`barre ${role} : liens présents`, liens.every((l) => nav.includes(`href="${l}"`)));
  verifier(`barre ${role} : liens absents`, absents.every((l) => !nav.includes(`href="${l}"`)));
}

// 5. Rapprochement en comptable : la lecture des lignes de revenu prévu (RLS
//    inchangée) et l'écriture d'une transaction rapprochée fonctionnent
//    toujours, alors que /budgets est fermé au comptable.
const entetes = (session) => ({ apikey: ANON, Authorization: `Bearer ${session.access_token}`, "Content-Type": "application/json" });
const LIGNE = "a6000000-0000-0000-0000-000000000001";
{
  const lecture = await json(`${SB}/rest/v1/lignes_revenu_prevu?id=eq.${LIGNE}&select=id,statut`, { headers: entetes(sessions.comptable) });
  verifier("comptable lit la ligne de revenu prévu (RLS inchangée)", lecture.status === 200 && lecture.corps?.[0]?.statut === "en_attente", JSON.stringify(lecture.corps));

  const insertion = await json(`${SB}/rest/v1/transactions`, {
    method: "POST",
    headers: { ...entetes(sessions.comptable), Prefer: "return=representation" },
    body: JSON.stringify({
      entreprise_id: "a0000000-0000-0000-0000-000000000001",
      date: "2026-09-20",
      description: "Rapprochement test de route",
      categorie_id: "a2000000-0000-0000-0000-000000000003",
      type: "entree",
      montant: "800000",
      mode_paiement: "virement",
      ligne_revenu_prevu_id: LIGNE,
    }),
  });
  verifier("comptable saisit une transaction rapprochée", insertion.status === 201, `HTTP ${insertion.status} ${typeof insertion.corps === "string" ? insertion.corps : ""}`);

  const apres = await json(`${SB}/rest/v1/lignes_revenu_prevu?id=eq.${LIGNE}&select=statut`, { headers: entetes(sessions.ceo) });
  verifier("la ligne rapprochée passe à « ok »", apres.corps?.[0]?.statut === "ok", JSON.stringify(apres.corps));
}

// 6. Messages : page signup-echec et écran « Compte non rattaché ».
{
  const echec = await page("/auth/lien-invalide?type=signup-echec", null);
  verifier("signup-echec : bouton « Réessayer » vers /", echec.texte.includes("Réessayer") && /href="\/"/.test(echec.texte));
  verifier("signup-echec : pas de « Connectez-vous »", !echec.texte.includes("Connectez-vous") && !echec.texte.includes("Se connecter"));
  verifier("signup-echec : dit que l'espace n'a pas été créé", echec.texte.includes("n&#x27;a pas abouti") || echec.texte.includes("n'a pas abouti"));

  const admin = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" };
  const email = `sans-profil-${Date.now()}@test.besmart.local`;
  const cree = await json(`${SB}/auth/v1/admin/users`, {
    method: "POST",
    headers: admin,
    body: JSON.stringify({ email, password: "mot-de-passe-test", email_confirm: true }),
  });
  verifier("compte de test sans profil créé", cree.status === 200 || cree.status === 201, `HTTP ${cree.status}`);
  try {
    const session = await connexion(email, "mot-de-passe-test");
    const accueil = await page("/", session);
    const texte = accueil.texte.replace(/&#x27;/g, "'");
    verifier("« Compte non rattaché » : affiché", accueil.status === 200 && texte.includes("Compte non rattaché"), `HTTP ${accueil.status}`);
    verifier("« Compte non rattaché » : « la personne qui vous a invité(e) », sans « gérant »", texte.includes("la personne qui vous a invité(e)") && !texte.includes("gérant"));
    verifier("« Compte non rattaché » : pas de « Connectez-vous »", !texte.includes("Connectez-vous"));
  } finally {
    await fetch(`${SB}/auth/v1/admin/users/${cree.corps.id}`, { method: "DELETE", headers: admin });
  }
}

if (echecs > 0) {
  console.log(`\n${echecs} vérification(s) en échec`);
  process.exit(1);
}
console.log("\nOK — accès aux pages par rôle, rapprochement du comptable et messages");
