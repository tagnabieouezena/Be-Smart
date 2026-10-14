# Be Smart Pilotage — Roadmap & Suivi des modules

*Version markdown du suivi.*

## Phase 0 — Fondations ✅ mergée dans `main` (PR #1, commit `0c3c0d4`)
- [x] Infra multi-tenant (`entreprises`, `utilisateurs`, RLS, `current_entreprise_id()`, `current_role_utilisateur()`)
- [x] Init Supabase CLI local (`supabase init`, `supabase start` via Docker) — compte prod unique, zéro service payant
- [x] Script de seed versionné (`supabase/seed.sql`) — deux entreprises de test + CEO/comptable de chacune + compte supervision Be Smart
- [x] Vues de supervision Be Smart lecture seule (`v_entreprises_supervision`, `v_utilisateurs_supervision`)
- [x] Job CI de test (typecheck, lint, build, `supabase start`/`db reset`, test d'isolation adversarial) — CI verte
- [ ] Job CI de promotion vers prod (`supabase db push` sur merge `main`) — volontairement pas encore fait, à ajouter quand une première fonctionnalité réelle sera prête à être déployée

## Phase 1 ✅ terminée
- [x] Module 4.1 — Authentification et gestion des comptes (CEO, comptable, super-admin Be Smart) ✅ mergée dans `main` (PR #2, commit `6a0e26b`)
  - Dette technique mineure, non bloquante, à traiter lors d'un prochain passage sur ce module : utilisateur Auth orphelin si l'insert `utilisateurs` échoue après un `inviteUserByEmail` réussi (pas de risque RLS, juste un résidu) ; champ `nom` du comptable invité non validé/assaini (sans conséquence tant qu'il n'est qu'affiché).
- [x] Module 4.2 — Paramétrage (catégories, objectifs CA, solde initial, modes de paiement) ✅ mergée dans `main` (PR #3, commit `efe1dfa`)
  - Décision produit tranchée par Ouezz : modes de paiement en liste fixe (`cash`/`mobile_money`/`virement`/`cheque`), pas de table dédiée — à respecter dans la colonne `mode_paiement` du Module 4.4.

- [x] Brief transverse — Navigation par rôle et parcours d'accueil ✅ mergée dans `main` (PR #12, merge `c87048d`, migration approuvée par Ouezz le 2026-10-13)
  - Contenu : barre de navigation selon le rôle, confirmation d'e-mail à l'inscription (route `/auth/confirm`, jeton vérifié au clic seulement), acceptation d'invitation, mot de passe oublié, redirections internes uniquement (`next` filtré), `creer_entreprise_et_ceo` idempotente et refusée aux comptes invités et à la supervision.
  - Sécurité des accès : garde serveur `exigerRole()` sur chaque page de module (404 hors du rôle, y compris pour la supervision hors `/supervision`) ; un compte connecté sans profil est renvoyé vers `/` (jamais `/connexion`) qui recrée l'espace ou affiche « Compte non rattaché » ; test de route en CI (`supabase/tests/acces_pages.mjs`).
  - Dette restante : réglages Auth de prod à reporter à la main (note `docs/05-deploiement-prod-reglages-auth.md`) ; parcours changement d'e-mail et lien magique non construits, modèles d'e-mail à créer avant de les activer ; compte invité orphelin (dette du 4.1) refusé avec un message, à réinviter par le CEO ; parcours d'e-mails testé uniquement en local (Mailpit).
  - Dépend de : fournisseur SMTP (Phase 5) ; tableau de bord KPI (4.11) pour remplacer `/ecarts` comme accueil du CEO ; chantier design global (décisions dans `docs/06-design-principes-et-tokens.md` : accent indigo, thème clair seul en V1, police Inter, pas de recherche globale en V1 ; implémentation à faire).

- [x] Brief transverse — Solde de caisse initial daté (prérequis du Module 4.8) ✅ mergée dans `main` (PR #20, merge `b2c9cd9`, migration approuvée par Ouezz le 2026-10-14)
  - Décisions actées par Ouezz (2026-10-13) : le solde initial est **daté** (option A) ; `solde_initial` est le solde de caisse à la **fin** de la journée `date_solde_initial` ; défaut `2000-01-01` (écran : « Aucune date renseignée ») ; date future refusée ; pas d'historique des modifications en V1 ; aucune restriction de lecture du solde pour le comptable en V1.
  - Réalisation : règle unique `solde_caisse_a(date)` (solde à la fin d'une journée, valable avant comme après la date du solde, aucun double comptage quel que soit l'ordre de saisie) ; `ecarts_mensuels` (4.6) l'appelle, seule fonction modifiée ; Paramétrage : montant et date saisis ensemble ; test SQL (scénarios chiffrés, trois ordres de saisie, contrôles négatifs) et test de route en CI.
  - À retenir : tout nouveau module qui a besoin d'un solde de caisse (4.8, 4.9, 4.11) appelle `solde_caisse_a`, il ne recalcule pas le solde.

## Phase 2 — Cœur du pilotage
- [x] Module 4.3 — Budget prévisionnel mensuel ✅ mergée dans `main` (PR #4, commit `c6b2e66`)
  - Point de sécurité à retenir pour les modules suivants : la cohérence entre tables liées (budget/catégorie/entreprise) doit être vérifiée par trigger `BEFORE INSERT/UPDATE`, pas seulement par RLS — une policy `entreprise_id = current_entreprise_id()` seule laisse passer une ligne pointant vers un budget ou une catégorie d'une autre entreprise tant que la ligne elle-même porte le bon `entreprise_id`. Testé explicitement (test adversarial #4 de ce module) ; à reproduire pour toute nouvelle table qui référence plusieurs tables scopées par entreprise.
  - Décision produit tranchée par Ouezz : `statut = 'valide'` sur un budget n'entraîne aucun verrouillage des lignes en V1 (le CDC ne l'exige pas) — à réévaluer plus tard si un besoin opérationnel réel apparaît, sans effort de migration majeur puisque c'est un simple flag.
- [x] Module 4.4 — Journal des transactions réelles ✅ mergée dans `main` (PR #5, commits `a0ee741` + `321f7c7`)
  - Décisions actées par Ouezz : aucune modification ni suppression d'une transaction saisie (correction = nouvelle transaction) ; lecture élargie à toute l'entreprise pour le comptable ; justificatif joint uniquement à la création (pas d'ajout après coup en V1) ; import/export CSV reporté à un brief dédié.
  - Sécurité : `justificatif_path` contraint en SQL au préfixe `{entreprise_id}/{id}/` ; rapprochement via trigger `security definer` limité à l'entreprise et aux lignes `en_attente` ; `saisi_par` forcé à `auth.uid()` ; non-accès de la supervision Be Smart prouvé par test.
  - Storage refuse les noms de fichier accentués (`400 InvalidKey`) → fichiers renommés `justificatif.<ext>`. À appliquer à tout futur upload (ex. Module 4.13).
  - À retenir pour le Module 4.6 : une transaction rapprochée passe la ligne de CA prévisionnel à `ok` même en cas de paiement partiel → les écarts Prévu/Réel doivent se calculer sur les montants des transactions, jamais sur le statut des lignes.
  - Backlog non bloquant : envoyer les montants en chaîne plutôt que via `Number()` (formulaires 4.3 et 4.4), à harmoniser lors d'un passage de nettoyage.
- [x] Module 4.6 — Suivi des écarts (Prévu vs Réel) ✅ mergée dans `main` (PR #7, commit `f53f738`)
  - Décisions actées par Ouezz : seuil d'écart significatif fixe à 10 % (inclusif, `>=`), défini dans la seule fonction `seuil_ecart_significatif()` ; alerte uniquement sur écart défavorable d'un mois clos ; solde prévu de début de mois = solde réel de fin du mois précédent (la chaîne 100 % prévisionnelle relève du 4.9) ; mois sans budget → prévu `null`, aucune alerte.
  - Changement de comportement assumé : `v_budget_mensuel_totaux` (4.3) exclut désormais les lignes `annule` → les totaux de l'écran Budget changent en conséquence. Une seule règle du prévu dans tout le produit.
  - Sécurité : `ecarts_mensuels` en `security invoker`, zéro ligne hors rôle CEO (comptable, supervision), `revoke execute from public` vérifié sur les ACL réelles et verrouillé par assertion ; cumul du solde prouvé sur plusieurs années.
  - Manque identifié : aucune barre de navigation dans l'application (écrans accessibles uniquement par URL) → brief « navigation par rôle » à faire avant toute démonstration.

## Phase 3 — Créances et vision consolidée
- [x] Module 4.5 — Suivi des créances clients ✅ mergée dans `main` (PR #9, commit `edac215`)
  - Décisions actées par Ouezz : statut et montant encaissé jamais stockés, calculés depuis les transactions liées ; encaissement = une transaction d'entrée liée (paiements partiels = plusieurs transactions) ; surpaiement bloqué par verrou de ligne (concurrence prouvée avec deux sessions) ; suppression d'une créance impossible dès qu'un paiement existe (`on delete restrict`, testé hors RLS).
  - À décider avant commercialisation : sort des données d'une entreprise cliente qui quitte le service (toutes les tables sont en `on delete cascade` sur `entreprise_id`).
- [x] Module 4.7 — Comparaison mensuelle CA/Dépenses/Résultat net ✅ mergée dans `main` (PR #17, merge `58ec45d`, migration approuvée par Ouezz le 2026-10-13)
  - Décisions actées par Ouezz : CA encaissé (base trésorerie : une facture compte au mois de son paiement) et résultat net, libellés « CA encaissé » / « Résultat net » avec ligne d'explication ; variation en % pour le CA et les dépenses, en FCFA seulement pour le résultat ; un mois sans transaction n'est comparable ni comme référence ni comme point de comparaison ; janvier sans variation sur le tableau annuel ; bandeau d'accueil = dernier mois clos contre le mois calendaire précédent (année précédente comprise) ; flèche selon le sens, couleur selon le caractère favorable, toujours avec signe et libellé ; graphique SVG écrit à la main (sans dépendance) ; ligne « Total année à date ».
  - Réalisation : trois fonctions `security invoker` — `variation_mensuelle` (pure, seule source des règles de variation), `comparaison_mensuelle` (écran `/comparaison`), `comparaison_accueil` (bandeau en haut de `/ecarts`) — le réel étant lu uniquement dans `ecarts_mensuels` (4.6). CEO uniquement ; test SQL chiffré et adversarial ; formatage dans `lib/format.ts` (aucun calcul de montant côté TypeScript).
  - À retenir : le bandeau est provisoire et sera repris tel quel par le tableau de bord KPI (4.11) ; `service_role` figure dans l'ACL des fonctions (privilèges par défaut Supabase, comme `ecarts_mensuels`), accepté par Ouezz.
- [ ] Module 4.8 — Synthèses mensuelle, trimestrielle, annuelle — brief mergé (PR #19, `docs/briefs/Module-4.8-Syntheses.md`), prérequis « solde initial daté » mergé (PR #20) ; implémentation à faire
- [ ] Module 4.9 — Cashflow prévisionnel

## Phase 4 — Tableau de bord et alertes
- [ ] Module 4.10 — Répartition des dépenses par catégorie
- [ ] Module 4.11 — Tableau de bord KPI
- [ ] Module 4.12 — Notifications et rappels

## Phase 5 — Finalisation V1
- [ ] Module 4.13 — Export et rapports (PDF, CSV/Excel) — bibliothèque PDF encore à trancher
- [ ] Couche PWA offline (Serwist, Dexie, Background Sync)
- [ ] Audit de sécurité multi-tenant complet (équivalent du 6-phase audit Air Ajjar), incluant la vérification que le pipeline local→CI→prod n'expose jamais les identifiants prod
- [ ] Premier job CI de promotion vers prod (`supabase db push`)
- [ ] Réglages Auth à reporter à la main dans le dashboard de prod avant la mise en ligne : voir [docs/05-deploiement-prod-reglages-auth.md](05-deploiement-prod-reglages-auth.md) (PR #13)

## Hors périmètre V1 (CDC 4.14 — ne pas construire maintenant)
Facturation intégrée, API Mobile Money, comptabilité SYSCOHADA, app mobile native, dettes fournisseurs, profil Lecteur, comparaison année sur année.
