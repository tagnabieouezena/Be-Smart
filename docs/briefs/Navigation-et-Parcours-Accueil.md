# Brief Claude Code — Navigation par rôle et parcours d'accueil

*Depuis `main` (Modules 4.1 à 4.6 et durcissement des droits `anon` mergés). Branche : `feat/navigation-et-accueil`.*

## Objectif

Rendre l'outil utilisable sans connaître les URL, et faire fonctionner tous les chemins par lesquels un utilisateur entre dans l'outil : inscription avec confirmation d'e-mail, acceptation d'une invitation, mot de passe oublié. C'est un préalable à toute démonstration (CDC 5.1 : interface simple pour un non-spécialiste).

Aucune nouvelle table. Une migration seulement si `creer_entreprise_et_ceo` doit être rendue idempotente (point 3).

## 1. Navigation par rôle

- Barre de navigation commune à toutes les pages authentifiées, construite **côté serveur** à partir du rôle :
  - CEO : Écarts, Budget, Transactions, Créances, Paramétrage, Utilisateurs ;
  - comptable : Transactions, Créances ;
  - supervision Be Smart : ses pages de supervision uniquement.
- Elle affiche le nom de l'entreprise, le nom et le rôle de l'utilisateur, et un bouton de déconnexion.
- Page d'accueil après connexion, selon le rôle : CEO → `/ecarts` (en attendant le tableau de bord KPI du 4.11), comptable → `/transactions`, supervision → sa page.
- Masquer un lien n'est pas une mesure de sécurité : les contrôles de rôle côté serveur de chaque page restent inchangés. Un comptable qui tape `/ecarts` obtient toujours une 404.
- Sur mobile : menu repliable, utilisable d'une main, sans défilement horizontal de la page.

## 2. Acceptation d'une invitation (comptable)

- Route de confirmation (par exemple `/auth/confirm`) qui lit le jeton du lien reçu par e-mail et le vérifie avec Supabase Auth (type `invite`), puis redirige vers une page **« Choisir mon mot de passe »**. Une fois le mot de passe défini, le comptable est connecté et arrive sur `/transactions`.
- Lien expiré ou déjà utilisé : message clair (« Ce lien n'est plus valide, demandez à votre gérant de vous renvoyer une invitation »), jamais une page blanche ou une erreur technique.
- Sur `/utilisateurs`, le CEO voit si un comptable invité n'a pas encore activé son compte, et dispose d'un bouton **« Renvoyer l'invitation »**.
- Mettre à jour `supabase/config.toml` (URL de redirection et modèle d'e-mail d'invitation) pour que le lien local pointe vers cette route. Lister dans la PR les réglages équivalents à reporter à la main dans le dashboard Supabase de prod le jour de la mise en ligne.

## 3. Inscription avec confirmation d'e-mail

- Activer la confirmation d'e-mail en local (`config.toml`), pour reproduire le comportement par défaut de la prod. Constater et documenter dans la PR ce que devient le parcours actuel.
- Parcours attendu :
  1. Le futur CEO s'inscrit (nom de l'entreprise, secteur, son nom, e-mail, mot de passe).
  2. Il reçoit un e-mail de confirmation, et l'écran le lui dit clairement.
  3. En cliquant sur le lien, il passe par la route de confirmation (type `signup`). L'entreprise et son profil CEO sont alors créés via `creer_entreprise_et_ceo`.
  4. Il arrive sur `/parametrage`, la première étape logique (catégories et solde initial).
- Les informations saisies à l'inscription peuvent transiter par les métadonnées de l'utilisateur, mais elles ne servent **qu'à nommer** (nom de l'entreprise, nom du CEO). Elles ne déterminent jamais un rôle ni un `entreprise_id`.
- `creer_entreprise_et_ceo` doit être **idempotente** : un second appel par le même utilisateur (double clic, lien rouvert) ne crée ni une seconde entreprise ni une erreur bloquante. Si une migration est nécessaire, mets son SQL en clair dans la PR.

## 4. Mot de passe oublié

- Lien « Mot de passe oublié ? » sur la page de connexion → saisie de l'e-mail → e-mail de réinitialisation → route de confirmation (type `recovery`) → page de nouveau mot de passe → connexion.
- Message identique, que l'e-mail existe ou non (pas de divulgation des comptes existants).

## 5. Sécurité des redirections

- Tout paramètre de redirection (`next` ou équivalent) n'accepte qu'un chemin relatif interne commençant par un seul `/`. Rejeter `//…`, `http…` et toute URL absolue. Test explicite : un lien forgé avec `next=https://exemple.com` ou `next=//exemple.com` redirige vers la page d'accueil du rôle, jamais vers l'extérieur.

## 6. Preuves attendues (dans le navigateur, avec les vrais e-mails de Mailpit)

**Aucun raccourci par l'API admin** : chaque parcours doit passer par le lien réellement reçu dans Mailpit.

1. Inscription → e-mail de confirmation → clic → entreprise et CEO créés → arrivée sur `/parametrage`.
2. Rouvrir le même lien de confirmation : aucune seconde entreprise (vérifié en base), message propre.
3. Le CEO invite un comptable → e-mail → clic → choix du mot de passe → arrivée sur `/transactions`. Statut « non activé » visible côté CEO avant l'activation, plus après.
4. Lien d'invitation réutilisé après activation : message « lien plus valide ».
5. « Renvoyer l'invitation » fonctionne pour un comptable non activé.
6. Mot de passe oublié de bout en bout, plus le message identique pour un e-mail inconnu.
7. Navigation : captures CEO, comptable et supervision (les liens diffèrent) ; le comptable qui tape `/ecarts` obtient toujours une 404 ; affichage mobile.
8. Les redirections forgées du point 5 restent internes.
9. Régression complète (scripts SQL, test de concurrence, `tsc`, `lint`, `build`) et audit d'isolation verts.

## Hors de ce brief

- Le design global de l'application (couleurs, typographie, identité Be Smart) : ce sera un chantier dédié. Ici, une présentation propre et sobre suffit.
- Le code PIN mobile (CDC 4.1) : il dépend de la couche hors ligne de la Phase 5.
- La configuration réelle de la prod : rien n'existe encore, on liste seulement les réglages à reporter.

## Livrable

PR depuis `feat/navigation-et-accueil`, avec : le SQL éventuel, la liste des réglages Auth à reporter en prod, les preuves des 9 points ci-dessus, et une CI verte.
