# Be Smart Pilotage — Stack & Architecture

*Document de cadrage technique — dérivé du process Air Ajjar ERP. Sert de référence pour toute session Claude Code travaillant sur ce projet.*

## 1. Principe

Même stack, mêmes standards de discipline que Air Ajjar ERP, avec deux changements structurants par rapport à Air Ajjar :

- **Multi-tenant dès le premier jour** : une seule instance sert plusieurs entreprises clientes de Be Smart — l'isolation stricte des données par entreprise n'est pas une évolution future, c'est une exigence V1 (CDC section 5.5). Air Ajjar est mono-entreprise (monolithe modulaire, `succursale_id` nullable en prévision).
- **Un seul compte Supabase, en production, développement 100% local et gratuit** — pas de second projet payant comme sur Air Ajjar (dev + prod). Les tests se font en local via le Supabase CLI ; le compte prod n'est touché qu'une fois les changements validés (détail section 3).

## 2. Stack technique

| Couche | Choix | Notes |
|---|---|---|
| Frontend | Next.js, TypeScript strict | Déployé sur Vercel |
| Backend / DB | Supabase (PostgreSQL + Row-Level Security + Storage) | **Un seul projet Supabase (compte prod unique)**. Développement et tests en local via le Supabase CLI (stack Docker gratuite) — voir section 3 |
| Auth | Supabase Auth | Email + mot de passe ; option code PIN pour mobile (CDC 4.1) |
| Offline / PWA | Serwist, Dexie.js, Background Sync | Exigence CDC 5.1 : fonctionnement correct en connexion instable/faible débit — plus critique ici que sur Air Ajjar |
| CI | GitHub Actions | typecheck, lint, tests, build + script d'audit de sécurité dédié (`tenant-isolation-audit.ts`, équivalent du `rls-audit.ts` d'Air Ajjar mais focalisé sur l'étanchéité multi-tenant) — exécuté contre une stack Supabase locale éphémère dans le runner CI, jamais contre prod |
| Génération PDF | Export tableau de bord mensuel (CDC 4.13) | Bibliothèque à trancher en phase d'implémentation |
| Devise | FCFA uniquement en V1, code prévu pour multi-devise future (CDC 5.4) | |
| Agent de développement | Claude Code, sous la direction d'Ouezz | Claude (chat) rédige les spécifications et les instructions précises pour Claude Code ; Claude Code exécute dans ce repo |

## 3. Environnement Supabase : compte unique, développement local, zéro coût

Décision d'Ouezz : un seul compte Supabase en production, aucun service payant supplémentaire. Le Database Branching de Supabase (payant) est écarté au profit du **Supabase CLI en local**, qui est gratuit et couvre le même besoin : développer et tester sans jamais toucher la prod, avant de pousser sur `main`.

**Mécanisme retenu : stack Supabase locale via Docker (Supabase CLI).**

- `supabase init` une fois dans le repo, puis `supabase start` lance en local une stack Postgres + Auth + Storage + Studio identique à la prod (gratuit, tourne sur la machine du développeur via Docker).
- Le schéma vit entièrement dans `supabase/migrations/*.sql`, versionné dans le repo. `supabase migration new <nom>` crée une migration ; `supabase db reset` reconstruit la base locale à partir de zéro (migrations + seed) pour repartir d'un état propre à tout moment.
- `supabase/seed.sql` (versionné) recrée systématiquement une ou deux entreprises de test complètes (catégories, budget, transactions, créances) à chaque `db reset` — c'est le jeu de fixtures de test, exécuté uniquement en local/CI, jamais en prod.
- Les clés locales (URL `http://localhost:54321`, clés anon/service_role) sont des valeurs fixes et génériques fournies par le CLI — elles ne pointent jamais vers un projet réel, donc aucun risque de toucher la prod par erreur pendant le développement.

**CI (gratuite) :** le job GitHub Actions lance lui aussi `supabase start` dans le runner (Docker inclus gratuitement dans GitHub Actions), applique les migrations + le seed, puis exécute les tests et l'audit d'isolation multi-tenant contre cette instance locale éphémère du CI. Aucune dépendance à un service Supabase payant.

**Promotion vers la prod — seulement quand c'est concluant en local :**

1. Ouezz développe et teste entièrement en local (`supabase start`, `db reset`, tests, audit RLS) sur une branche de fonctionnalité.
2. Une fois concluant, la PR est ouverte : CI verte (contre la stack locale éphémère du runner) + revue explicite des migrations/RLS par Ouezz (SQL réel, voir ways-of-working).
3. Merge sur `main`. Un job GitHub Actions dédié se déclenche alors et exécute `supabase db push` (CLI, lié au projet prod via `supabase link` + un `SUPABASE_ACCESS_TOKEN` stocké en secret GitHub) pour appliquer les migrations validées sur la prod. Vercel déploie le frontend en parallèle.
4. Aucune étape manuelle sur la machine de Ouezz ne doit jamais utiliser les identifiants de prod — seul le job CI dédié au merge sur `main` les détient (en secret GitHub, jamais en clair dans le repo ni en local).

## 4. Architecture multi-tenant

- Toute table métier porte une colonne `entreprise_id` (non nullable, dès la création — pas de migration a posteriori comme le `succursale_id` d'Air Ajjar).
- Isolation stricte via RLS : chaque politique filtre systématiquement sur `entreprise_id = auth.jwt() ->> 'entreprise_id'` (ou équivalent via une fonction `current_entreprise_id()`), en plus du filtrage par rôle.
- Espace Be Smart (super-admin) : rôle transverse de supervision, **lecture seule** sur les métadonnées des entreprises clientes et la liste de leurs utilisateurs — jamais sur les données financières détaillées (décision Ouezz, détail dans `03-modele-de-donnees.md`).
- Le script d'audit CI doit vérifier, pour chaque table et chaque politique, qu'aucun chemin ne permet une lecture/écriture cross-entreprise — c'est le risque de sécurité le plus critique de ce projet (données financières de plusieurs entreprises clientes dans une même base), renforcé par le fait qu'il n'y a qu'une seule base de production.

## 5. Séparation des rôles (rappel CDC section 3)

- **CEO / gérant** : accès complet à son entreprise — paramétrage, budgets, KPI, création du compte comptable.
- **Comptable** : accès restreint à son entreprise — saisie des transactions et créances, lecture de ses propres saisies, lecture des lignes prévisionnelles pour rapprochement (sans droit de modification), aucun accès aux KPI stratégiques globaux ni aux paramètres.
- Ces deux niveaux (rôle + entreprise) doivent être appliqués en RLS, pas seulement côté UI — même principe qu'Air Ajjar : le cloisonnement des droits est une exigence de sécurité, pas une simple option d'affichage.

## 6. Ce qui reste hors périmètre V1 (CDC 4.14)

Facturation client intégrée, API Mobile Money (Orange Money, Moov Money), comptabilité SYSCOHADA complète, application mobile native (V1 = web responsive), dettes fournisseurs, profil « Lecteur », comparaison année sur année. Ne pas concevoir de schéma qui les empêche, mais ne pas les construire en V1.

## 7. Questions techniques encore ouvertes (à trancher avant le premier sprint)

- Bibliothèque de génération PDF.
- Modèle de tarification (CDC section 7) → impacte le schéma si la gestion d'abonnement doit être intégrée dès la V1 ou gérée hors produit dans un premier temps.
- Docker doit être installé sur la machine de développement (gratuit) pour faire tourner la stack Supabase locale — à vérifier/installer en tout début de projet.
