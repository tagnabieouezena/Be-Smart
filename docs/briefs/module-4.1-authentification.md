# Brief Claude Code — Module 4.1 : Authentification et gestion des comptes

*À donner tel quel à Claude Code, depuis `main` (Phase 0 mergée). Branche courte dédiée : `feat/module-4.1-authentification`.*

## Objectif de ce module (CDC 4.1)

Rendre possible, de bout en bout :
1. L'inscription d'une nouvelle entreprise cliente avec son premier compte CEO.
2. La création par ce CEO de comptes comptable pour son entreprise.
3. La connexion sécurisée des deux rôles.
4. Un espace de supervision en lecture seule pour Be Smart (déjà préparé côté base en Phase 0 — `v_entreprises_supervision`, `v_utilisateurs_supervision`).

## Étapes attendues

### 1. RPC de bootstrap entreprise + premier CEO (nouvelle migration)

- Fonction `public.creer_entreprise_et_ceo(p_nom text, p_secteur text, p_nom_utilisateur text)`, `security definer`, `language plpgsql`.
- Vérifie d'abord qu'aucune ligne `utilisateurs` n'existe déjà pour `auth.uid()` — sinon lève une exception explicite (`'Ce compte est déjà rattaché à une entreprise.'`). Un utilisateur ne doit jamais pouvoir créer une deuxième entreprise ni changer d'entreprise via cette fonction.
- Crée la ligne `entreprises` (nom, secteur, devise par défaut `'FCFA'`), puis la ligne `utilisateurs` (`id = auth.uid()`, `role = 'ceo'`, `entreprise_id` = celle qui vient d'être créée). Les deux insertions dans la même fonction PL/pgSQL : soit tout réussit, soit rien n'est créé (pas d'entreprise orpheline sans CEO).
- `grant execute` à `authenticated` uniquement, jamais à `anon`.
- **Test adversarial obligatoire** : appeler deux fois la fonction avec le même `auth.uid()` et prouver que la deuxième tentative échoue proprement (pas d'entreprise fantôme créée entre-temps — vérifier avec un `rollback` ou un compte de lignes avant/après).

### 2. Invitation d'un comptable — route serveur, jamais côté client

- Un Next.js Route Handler (ou Server Action) `POST /api/comptable/inviter`, appelé uniquement depuis une session authentifiée.
- Vérifie côté serveur, avant toute action, que l'appelant a bien `role = 'ceo'` pour son `entreprise_id` (requête normale via le client Supabase de la session, pas via service_role) — **rejet explicite sinon**, pas juste un bouton caché côté UI.
- Utilise ensuite un client Supabase `service_role` (variable d'environnement serveur uniquement, jamais `NEXT_PUBLIC_*`, jamais commité) pour créer l'utilisateur via l'API Admin Auth de Supabase (`inviteUserByEmail` ou équivalent), puis insère la ligne `utilisateurs` (`role = 'comptable'`, `entreprise_id` = celle du CEO appelant).
- **Test adversarial obligatoire** : un utilisateur avec `role = 'comptable'` qui appelle cette route doit être rejeté avec une erreur claire (403), pas planter silencieusement.

### 3. Écrans

- Page d'inscription : formulaire (nom entreprise, secteur, nom du CEO, email, mot de passe) → `supabase.auth.signUp` puis appel de la RPC de bootstrap. Gérer l'échec de la RPC après un signUp réussi (ex. re-tentative, message clair) plutôt que de laisser un compte Auth sans entreprise.
- Page de connexion : email + mot de passe (`supabase.auth.signInWithPassword`).
- Écran CEO « Utilisateurs » : liste des comptables de son entreprise (lecture via RLS existante) + formulaire d'invitation (appelle la route serveur du point 2).
- Écran supervision Be Smart : liste en lecture seule des entreprises (`v_entreprises_supervision`) — accès contrôlé côté serveur par la vérification de `app_metadata.super_admin`, pas seulement une route cachée dans la nav.

### 4. Explicitement hors de ce module

- Code PIN mobile (CDC 4.1) : différé — la V1 est web responsive, pas d'application mobile native (CDC 4.14). Ne pas construire maintenant.
- Statut de compte entreprise activable/suspendable par le super-admin : pas exigé explicitement par le CDC en 4.1, à réévaluer plus tard si Be Smart en a besoin opérationnellement — ne pas l'ajouter sans validation.
- Récupération de mot de passe, 2FA : non demandés par le CDC à ce stade, à ne pas anticiper.

## Sécurité incontournable pour ce module (rappel `CLAUDE.md`)

- Le `service_role` n'est jamais appelé depuis un composant client — uniquement depuis une route serveur.
- La RPC de bootstrap ne doit permettre ni double rattachement, ni auto-attribution du rôle CEO d'une entreprise existante.
- Chaque contrôle de rôle (CEO vs comptable, super-admin ou non) doit être vérifié côté serveur/base — jamais seulement côté UI.

## Livrable attendu pour revue

PR depuis `feat/module-4.1-authentification` vers `main`, avec :
- Le SQL de la nouvelle migration en clair dans la description.
- La preuve des deux tests adversariaux (double bootstrap rejeté, invitation par un comptable rejetée) — avant/après ou message d'erreur explicite, comme en Phase 0.
- CI verte (le job existant doit continuer à passer, plus les nouveaux tests).
