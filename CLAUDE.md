# Be Smart Pilotage — Instructions projet pour Claude Code

Ce repo implémente **Be Smart Pilotage**, un SaaS multi-tenant de pilotage financier pour TPE/PME, développé par Be Smart (Ouagadougou). Même process et même discipline que le projet Air Ajjar ERP, avec un compte Supabase unique et un développement 100% local (voir règles ci-dessous).

**Avant toute implémentation, lire dans l'ordre** :
1. `docs/00-decision-firebase-vs-supabase.md` — pourquoi Supabase, et ce que ça implique en sécurité/exactitude
2. `docs/01-stack-et-architecture.md` — stack, architecture multi-tenant, environnement Supabase local
3. `docs/02-ways-of-working.md` — rôles, workflow, principes
4. `docs/03-modele-de-donnees.md` — schéma de données draft
5. `docs/04-roadmap-suivi-modules.md` — modules à construire, par phase

Le cahier des charges complet (CDC_BeSmart_Pilotage_TPME) vit dans le projet claude.ai « Be smart » — s'y référer pour le détail fonctionnel de chaque module.

## Règles non négociables

- **Ouezz est le seul décideur.** Ne jamais merger un changement de schéma ou de politique RLS sans son approbation explicite, SQL à l'appui.
- **Sécurité incontournable.** Isolation multi-tenant stricte : toute nouvelle table métier a `entreprise_id` non nullable et une politique RLS dès sa création, jamais seulement une vérification côté UI. Toute nouvelle politique RLS est accompagnée d'un test qui prouve qu'un utilisateur de l'entreprise A ne peut rien lire/écrire de l'entreprise B. Séparation des rôles CEO / Comptable appliquée en RLS (voir CDC section 3). Aucune fonctionnalité, aucun délai ne justifie une exception.
- **Exactitude des calculs financiers incontournable.** Tout montant est stocké et calculé en `numeric` (jamais en float). Toute opération qui touche plusieurs tables liées à l'argent (ex. créance → transaction) est transactionnelle. Tout nouveau calcul (KPI, synthèse, cashflow) est vérifié par un cas de test concret avec un résultat attendu chiffré, pas seulement « les tests passent ».
- **Un seul compte Supabase, en production. Développement et tests 100% en local via le Supabase CLI (`supabase start`, Docker), gratuit.** Jamais de service payant (ex. Database Branching) sans validation explicite d'Ouezz.
- **Cycle obligatoire : local → PR → CI → revue → merge.** Développer et tester en local (`supabase db reset` = migrations + `supabase/seed.sql`) jusqu'à ce que ce soit concluant, puis seulement ouvrir une PR. **Merger sur `main` déploie directement en prod** (job CI dédié `supabase db push` + déploiement Vercel) — jamais de push direct sur `main`, jamais de PR mergée sans CI verte et sans revue explicite des migrations/RLS par Ouezz.
- **Jamais d'identifiants de prod en local.** Le développement local utilise exclusivement les clés génériques du Supabase CLI (`localhost:54321`). Les identifiants prod (`SUPABASE_ACCESS_TOKEN`, project ref) n'existent qu'en secret GitHub Actions.
- **Commits conventionnels**, branches courtes, CI (typecheck/lint/tests/build + audit d'isolation multi-tenant) verte avant merge.
- **Ne pas construire les modules hors périmètre V1** (CDC 4.14) sans validation explicite d'Ouezz.
