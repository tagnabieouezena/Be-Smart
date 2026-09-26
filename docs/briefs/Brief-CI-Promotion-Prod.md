# Brief Claude Code — Job CI de promotion vers la prod (`supabase db push`)

*À donner tel quel à Claude Code, depuis `main` (PR #5 / Module 4.4 mergée). Branche courte dédiée : `chore/ci-promotion-prod`.*

## Objectif

Mettre en place le seul chemin autorisé vers la base de production (`01-Stack-et-Architecture.md`, section 3) : un job GitHub Actions qui applique les migrations validées sur le projet Supabase de prod, **uniquement** après un merge sur `main` dont les tests sont verts. Les identifiants de prod n'existent qu'en secrets GitHub, jamais sur la machine de développement ni dans le repo.

Ce brief ne touche ni au schéma ni au code applicatif. Il n'ajoute aucune migration.

## Étapes attendues

### 1. Workflow en lecture seule d'abord : état de la prod (`workflow_dispatch`)

Avant tout déploiement réel, on ne sait pas dans quel état est la base de prod : vide, Phase 0 appliquée manuellement, ou historique de migrations incohérent. Le premier livrable est donc un workflow **déclenché manuellement uniquement**, qui n'écrit rien :

- `.github/workflows/prod-etat.yml`, déclencheur `workflow_dispatch` seul.
- Étapes : `supabase link --project-ref "$SUPABASE_PROJECT_REF"`, puis `supabase migration list`, puis `supabase db push --dry-run`.
- Sortie attendue dans les logs : la liste des migrations déjà appliquées en prod, et celles que le vrai push appliquerait.
- **Aucune** commande d'écriture dans ce workflow.

Ouezz le lance une fois à la main, lit le résultat, et décide seulement ensuite d'activer le point 2.

### 2. Job de promotion sur merge dans `main`

- `.github/workflows/deploy-prod.yml`, déclencheur `push` sur `main` uniquement. Jamais sur `pull_request` : une PR ne doit jamais avoir accès aux secrets de prod.
- **Le job de déploiement dépend des jobs de test** (`needs:`) : typecheck, lint, build, `supabase start`/`db reset`, test d'isolation multi-tenant, tests de modules. Ces jobs sont rejoués sur le commit de `main`. Si l'un d'eux échoue, rien n'est poussé en prod.
  - Raison : si le repo est privé sur un compte GitHub gratuit, la protection de branche (« CI verte obligatoire avant merge ») n'est pas disponible. Rien n'empêcherait alors techniquement un merge avec une CI rouge. Le `needs:` est le vrai garde-fou.
- `concurrency: { group: deploy-prod, cancel-in-progress: false }` : deux merges rapprochés ne doivent jamais pousser en parallèle, ni s'annuler en plein milieu d'une migration.
- Séquence du job :
  1. `supabase link --project-ref "$SUPABASE_PROJECT_REF"`.
  2. `supabase db push --dry-run` (trace dans les logs de ce qui va être appliqué).
  3. `supabase db push`.
- **Interdit : `--include-seed`**. Le seed (entreprises de test, comptes CEO/comptable fictifs) ne doit jamais atteindre la prod. Ajoute un commentaire explicite dans le YAML.
- Si `db push` signale un historique de migrations incohérent, le job échoue sans tenter de réparation (`migration repair` interdit en automatique). C'est à Ouezz de trancher.

### 3. Secrets

- Secrets GitHub Actions attendus : `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`.
- **Ouezz les crée lui-même** dans les paramètres du repo. Claude Code ne les voit jamais, ne les demande pas et ne les écrit dans aucun fichier.
- Le YAML référence uniquement `${{ secrets.X }}`. Aucune valeur en clair, aucun `echo` d'un secret, aucun `set -x` dans les étapes qui les utilisent.

### 4. Vérification que les identifiants ne fuient pas

- Aucun fichier du repo ne contient un project ref ou un token de prod : recherche explicite dans le diff et dans l'historique de la branche.
- `supabase/.temp/` (créé par `supabase link`) est bien dans le `.gitignore`.
- Les workflows déclenchés par `pull_request` ne référencent aucun des trois secrets.

## Explicitement hors de ce brief

- Paramètres Auth de prod (URL du site, URLs de redirection des invitations du Module 4.1, modèles d'emails) : `db push` ne les applique pas. Ouezz les vérifie manuellement dans le dashboard Supabase avant d'ouvrir l'accès au premier client.
- Liaison Vercel ↔ projet Supabase de prod (variables d'environnement) : configuration faite par Ouezz dans Vercel.
- Sauvegarde des données de prod avant push : pas de dump de données en artefact GitHub (données financières clientes). Le rollback se fait par migration corrective (fix-forward), jamais par migration descendante automatique.
- Ordre de déploiement frontend/base : Vercel peut déployer le frontend quelques instants avant la fin du `db push`. C'est acceptable tant qu'aucun client n'est en production ; à revoir avant la commercialisation.

## Livrable attendu pour revue

PR depuis `chore/ci-promotion-prod` vers `main`, avec :
- Les deux YAML en clair dans la description.
- La preuve que les workflows `pull_request` n'ont pas accès aux secrets.
- La preuve que `--include-seed` est absent et que `supabase/.temp/` est ignoré.
- Une note rappelant l'ordre d'activation : secrets créés par Ouezz → `prod-etat` lancé à la main et lu → merge de cette PR (qui déclenche le premier vrai push).

**Attention :** merger cette PR déclenche elle-même le job de promotion, donc le premier vrai `db push` avec toutes les migrations de la Phase 0 au Module 4.4. Ne la merger qu'après avoir lu la sortie de `prod-etat`.
