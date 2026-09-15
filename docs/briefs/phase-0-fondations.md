# Brief Claude Code — Phase 0 : Fondations

*À donner tel quel à Claude Code. Lire d'abord `CLAUDE.md` et les docs listées dedans — ce brief n'en est que la mise en œuvre.*

## Objectif de cette phase

Poser les fondations techniques du projet : repo Next.js, environnement Supabase 100% local, première migration (entreprises, utilisateurs, isolation multi-tenant), script de seed, squelette CI. Aucune fonctionnalité métier encore — juste une base saine et testée sur laquelle brancher le Module 4.1 ensuite.

## Étapes attendues

1. **Scaffolding Next.js**
   - Next.js (App Router), TypeScript en mode strict.
   - Structure de dossiers standard (`app/`, `lib/`, `components/`), rien de superflu.

2. **Init Supabase local**
   - `supabase init` à la racine du repo.
   - Vérifier/documenter la présence de Docker (prérequis pour `supabase start`) — si absent, l'indiquer clairement plutôt que d'échouer silencieusement.
   - `supabase start` doit fonctionner de bout en bout sans configuration manuelle supplémentaire.

3. **Première migration** (`supabase/migrations/`)
   - Table `entreprises` : `id`, `nom`, `secteur`, `devise` (défaut `'FCFA'`), `solde_initial numeric not null default 0`, `created_at`.
   - Table `utilisateurs` : `id`, `nom`, `email`, `role` (enum ou check constraint `'ceo' | 'comptable'`), `entreprise_id uuid not null references entreprises(id)`, `created_at`.
   - Fonction `current_entreprise_id()` (SQL, `security definer` si besoin) qui extrait l'`entreprise_id` du JWT de l'utilisateur connecté.
   - RLS activé sur les deux tables dès leur création :
     - `utilisateurs` : un utilisateur ne voit/modifie que les lignes de sa propre `entreprise_id` ; un CEO peut créer des lignes `comptable` pour son entreprise, un comptable ne peut rien créer.
     - `entreprises` : un CEO voit/modifie uniquement la sienne. Le rôle super-admin Be Smart voit **en lecture seule** toutes les lignes, mais uniquement les colonnes `nom`, `secteur`, `created_at` (pas de colonne financière sur cette table de toute façon à ce stade — poser la politique en lecture seule dès maintenant pour ne pas avoir à la durcir plus tard).
   - Montants toujours en `numeric`, jamais en `float`/`real` — non négociable (voir `docs/00-decision-firebase-vs-supabase.md`).

4. **Script de seed** (`supabase/seed.sql`)
   - Crée une entreprise de test (« Boutique Test SARL » ou équivalent), un utilisateur CEO et un utilisateur comptable rattachés à cette entreprise.
   - Doit être idempotent avec `supabase db reset` (reproductible à volonté).

5. **Test d'isolation multi-tenant (obligatoire dès cette migration)**
   - Créer une deuxième entreprise de test dans le seed, avec son propre CEO.
   - Écrire un test (SQL ou script, à intégrer dans la CI) qui prouve concrètement que le CEO de l'entreprise A ne peut ni lire ni modifier aucune ligne de l'entreprise B dans `utilisateurs` ni `entreprises`. Un test qui « passe » sans ce scénario explicite ne compte pas (voir principe de test adversarial concret).

6. **Squelette CI** (`.github/workflows/`)
   - Job qui : installe les dépendances, lance `supabase start` dans le runner, applique migrations + seed, exécute typecheck + lint + le test d'isolation ci-dessus + build Next.js.
   - Pas encore de job de déploiement vers la prod à ce stade (ce sera ajouté quand la première fonctionnalité réelle sera prête à être promue) — le documenter comme prochaine étape dans le workflow lui-même (commentaire) plutôt que de l'improviser maintenant.

## Ce qui n'est PAS dans cette phase

- Pas d'écran, pas d'UI au-delà d'une page d'accueil minimale de vérification.
- Pas de module fonctionnel (authentification complète, paramétrage, etc.) — c'est le Module 4.1, qui viendra juste après.
- Pas de job CI de promotion vers la prod (`supabase db push`) — prématuré tant qu'il n'y a rien à déployer.

## Livrable attendu pour revue

Une PR unique, avec :
- Le SQL des migrations en clair dans la description (pas seulement dans les fichiers) — pour la revue explicite d'Ouezz.
- Le résultat du test d'isolation multi-tenant (avant/après, ou capture de l'échec attendu si la politique RLS était absente) — preuve concrète, pas juste "les tests passent".
- La CI verte.
