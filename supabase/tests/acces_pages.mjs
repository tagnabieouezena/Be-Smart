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

// 6. Comptes connectés SANS profil (inscription non finalisée, invitation sans
//    rattachement) : jamais renvoyés vers /connexion ; « / » recrée l'espace
//    ou affiche « Compte non rattaché » ; `next` est suivi seulement s'il est
//    interne et autorisé pour le rôle.
const MOT_PROSCRIT = "g\u00e9rant"; // écrit en échappement pour garder `grep -ri` vide dans le dépôt
const MODULES = ["/ecarts", "/budgets", "/transactions", "/creances", "/parametrage", "/utilisateurs"];
{
  const echec = await page("/auth/lien-invalide?type=signup-echec", null);
  verifier("signup-echec : bouton « Réessayer » vers /", echec.texte.includes("Réessayer") && /href="\/"/.test(echec.texte));
  verifier("signup-echec : pas de « Connectez-vous »", !echec.texte.includes("Connectez-vous") && !echec.texte.includes("Se connecter"));
  verifier("signup-echec : dit que l'espace n'a pas été créé", echec.texte.includes("n&#x27;a pas abouti") || echec.texte.includes("n'a pas abouti"));
  const expire = await page("/auth/lien-invalide?type=invite", null);
  verifier("lien d'invitation expiré : « la personne qui vous a invité(e) »", expire.texte.replace(/&#x27;/g, "'").includes("la personne qui vous a invité(e)") && !expire.texte.includes(MOT_PROSCRIT));

  const admin = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" };
  const motDePasse = "mot-de-passe-test";
  const suffixe = Date.now();
  const aSupprimer = [];

  async function creer(etiquette, corps) {
    const reponse = await json(`${SB}/auth/v1/admin/users`, { method: "POST", headers: admin, body: JSON.stringify({ password: motDePasse, email_confirm: true, ...corps }) });
    verifier(`compte « ${etiquette} » créé`, reponse.status === 200 || reponse.status === 201, `HTTP ${reponse.status}`);
    aSupprimer.push(reponse.corps.id);
    return reponse.corps;
  }
  const sansBruit = (texte) => texte.replace(/&#x27;/g, "'");
  const NU = `sans-profil-${suffixe}@test.besmart.local`;
  const META = `sans-profil-meta-${suffixe}@test.besmart.local`;
  const META2 = `sans-profil-meta2-${suffixe}@test.besmart.local`;
  const META3 = `sans-profil-meta3-${suffixe}@test.besmart.local`;
  const INVITE = `sans-profil-invite-${suffixe}@test.besmart.local`;
  try {
    await creer("sans profil, sans métadonnées", { email: NU });
    await creer("sans profil, avec métadonnées", { email: META, user_metadata: { nom_entreprise: "Retour Test SARL", secteur: "Services", nom_ceo: "Retour Test" } });
    await creer("sans profil, avec métadonnées (2)", { email: META2, user_metadata: { nom_entreprise: "Retour Test Deux SARL", secteur: "Services", nom_ceo: "Retour Deux" } });
    await creer("sans profil, avec métadonnées (3)", { email: META3, user_metadata: { nom_entreprise: "Retour Test Trois SARL", secteur: "Services", nom_ceo: "Retour Trois" } });

    // Compte invité sans entreprise : vraie invitation (invited_at posé) portant des métadonnées
    // d'inscription forgées, puis mot de passe posé en admin.
    const invitation = await json(`${SB}/auth/v1/invite`, { method: "POST", headers: admin, body: JSON.stringify({ email: INVITE, data: { nom_entreprise: "Entreprise Forgee SARL", nom_ceo: "Invite Forge" } }) });
    verifier("compte invité sans entreprise créé (invited_at posé)", invitation.status === 200 && Boolean(invitation.corps?.invited_at), `HTTP ${invitation.status}`);
    aSupprimer.push(invitation.corps.id);
    await json(`${SB}/auth/v1/admin/users/${invitation.corps.id}`, { method: "PUT", headers: admin, body: JSON.stringify({ password: motDePasse, email_confirm: true }) });

    // a) sans profil, sans métadonnées : aucune boucle vers /connexion ; « Compte non rattaché ».
    const nu = await connexion(NU, motDePasse);
    for (const chemin of MODULES) {
      const { status, location } = await page(chemin, nu);
      verifier(`sans profil ${chemin} : renvoi vers « / » (pas /connexion)`, status === 307 && (location ?? "").startsWith(`/?next=${encodeURIComponent(chemin)}`), `HTTP ${status} -> ${location}`);
    }
    const accueilNu = await page(`/?next=${encodeURIComponent("/transactions")}`, nu);
    const texteNu = sansBruit(accueilNu.texte);
    verifier("sans profil : « Compte non rattaché » affiché (pas de redirection)", accueilNu.status === 200 && texteNu.includes("Compte non rattaché"), `HTTP ${accueilNu.status}`);
    verifier("sans profil : « la personne qui vous a invité(e) », sans le mot proscrit ni « Connectez-vous »", texteNu.includes("la personne qui vous a invité(e)") && !texteNu.includes(MOT_PROSCRIT) && !texteNu.includes("Connectez-vous"));

    // b) invité sans entreprise : « Compte non rattaché », message d'invitation.
    const invite = await connexion(INVITE, motDePasse);
    const accueilInvite = await page("/", invite);
    const texteInvite = sansBruit(accueilInvite.texte);
    verifier("invité sans entreprise : « Compte non rattaché » (message d'invitation)", accueilInvite.status === 200 && texteInvite.includes("Compte non rattaché") && texteInvite.includes("créé par invitation") && texteInvite.includes("contactez la personne qui vous a invité(e)") && !texteInvite.includes(MOT_PROSCRIT));
    const moduleInvite = await page("/transactions", invite);
    verifier("invité sans entreprise : /transactions renvoie vers « / » (pas /connexion)", moduleInvite.status === 307 && (moduleInvite.location ?? "").startsWith("/?next="), `HTTP ${moduleInvite.status} -> ${moduleInvite.location}`);
    const suiteInvite = await page(moduleInvite.location, invite);
    verifier("invité sans entreprise : « / » affiche « Compte non rattaché » même avec des métadonnées forgées", suiteInvite.status === 200 && sansBruit(suiteInvite.texte).includes("Compte non rattaché"));
    const profilInvite = await json(`${SB}/rest/v1/utilisateurs?select=id`, { headers: { apikey: ANON, Authorization: `Bearer ${invite.access_token}` } });
    const entreprisesInvite = await json(`${SB}/rest/v1/entreprises?select=nom`, { headers: { apikey: ANON, Authorization: `Bearer ${invite.access_token}` } });
    verifier("invité sans entreprise : aucun profil ni entreprise créés (la fonction a refusé)", Array.isArray(profilInvite.corps) && profilInvite.corps.length === 0 && Array.isArray(entreprisesInvite.corps) && entreprisesInvite.corps.length === 0, JSON.stringify({ profils: profilInvite.corps, entreprises: entreprisesInvite.corps }));

    // c) avec métadonnées : /transactions -> « / » -> espace créé -> /transactions.
    const meta = await connexion(META, motDePasse);
    const etape1 = await page("/transactions", meta);
    verifier("avec métadonnées : /transactions renvoie vers « / » en gardant la page", etape1.status === 307 && etape1.location === "/?next=%2Ftransactions", `HTTP ${etape1.status} -> ${etape1.location}`);
    const etape2 = await page(etape1.location, meta);
    verifier("avec métadonnées : « / » crée l'espace puis suit next vers /transactions", etape2.status === 307 && etape2.location === "/transactions", `HTTP ${etape2.status} -> ${etape2.location}`);
    const etape3 = await page("/transactions", meta);
    verifier("avec métadonnées : /transactions s'ouvre ensuite (200, plus de renvoi)", etape3.status === 200, `HTTP ${etape3.status}`);
    const profil = await json(`${SB}/rest/v1/utilisateurs?email=eq.${encodeURIComponent(META)}&select=role,entreprises(nom)`, { headers: { apikey: ANON, Authorization: `Bearer ${meta.access_token}` } });
    verifier("avec métadonnées : le compte est CEO de « Retour Test SARL »", profil.corps?.[0]?.role === "ceo" && profil.corps?.[0]?.entreprises?.nom === "Retour Test SARL", JSON.stringify(profil.corps));

    // d) next non autorisé ou forgé : accueil du rôle (CEO) ; next autorisé : suivi.
    for (const [valeur, attendu] of [["/supervision", "/ecarts"], ["//evil.com", "/ecarts"], ["https://evil.com", "/ecarts"], ["/budgets", "/budgets"]]) {
      const { status, location } = await page(`/?next=${encodeURIComponent(valeur)}`, meta);
      verifier(`CEO : /?next=${valeur} -> ${attendu}`, status === 307 && location === attendu, `HTTP ${status} -> ${location}`);
    }

    // e) compte sans profil + next forgé : l'espace est créé, le next forgé n'est jamais suivi.
    const meta2 = await connexion(META2, motDePasse);
    const forge = await page(`/?next=${encodeURIComponent("//evil.com")}`, meta2);
    verifier("sans profil + next forgé : espace créé, accueil du CEO (jamais l'extérieur)", forge.status === 307 && forge.location === "/ecarts", `HTTP ${forge.status} -> ${forge.location}`);

    // f) avec métadonnées, sans next : accueil du rôle CEO.
    const meta3 = await connexion(META3, motDePasse);
    const sansNext = await page("/", meta3);
    verifier("avec métadonnées, sans next : espace créé, accueil du CEO", sansNext.status === 307 && sansNext.location === "/ecarts", `HTTP ${sansNext.status} -> ${sansNext.location}`);
  } finally {
    for (const id of aSupprimer) {
      await fetch(`${SB}/auth/v1/admin/users/${id}`, { method: "DELETE", headers: admin });
    }
  }
}

if (echecs > 0) {
  console.log(`\n${echecs} vérification(s) en échec`);
  process.exit(1);
}
console.log("\nOK — accès aux pages par rôle, rapprochement du comptable et messages");
