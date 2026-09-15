# Be Smart Pilotage — Ways of Working

*Même principe que le document équivalent sur Air Ajjar ERP, adapté à ce projet.*

## Rôles et approbation

- Ouezz est le seul décideur (product owner / architecte) sur ce projet. Claude et Claude Code sont des outils sous sa supervision — jamais des co-décideurs.
- Claude (ce fil, ou toute session de cadrage) rédige des spécifications précises et des instructions pour Claude Code. Claude Code exécute le développement dans le repo. Ouezz revoit et approuve avant tout déploiement.
- **Changements sensibles nécessitent une validation explicite** : toute migration de schéma et toute politique RLS doivent être présentées en SQL réel avant merge — c'est encore plus strict ici que sur Air Ajjar, puisqu'une erreur de politique RLS peut exposer les données financières d'une entreprise cliente à une autre.
- Les corrections d'Ouezz sont directes et spécifiques ; il signale les erreurs d'attribution, de périmètre et de cadrage — à prendre en compte sans discussion superflue.

## Workflow

- Boucle de clarification itérative standard : besoin métier → spécification technique → implémentation → revue → correction.
- Discipline de développement : commits conventionnels (`feat:`, `fix:`, `chore:`, …), branches de fonctionnalité courtes fusionnées sur `main`, CI GitHub Actions obligatoire avant merge.
- Toute nouvelle table ou politique RLS doit être accompagnée d'un test explicite d'isolation multi-tenant (un utilisateur de l'entreprise A ne doit rien voir/modifier de l'entreprise B).
- **Un seul compte Supabase, en prod ; développement et tests 100% en local, gratuit** (décision Ouezz) :
  - Tout le travail de développement et de test se fait contre une stack Supabase locale (`supabase start`, Docker), jamais contre le projet prod.
  - Le cycle est : développer et tester en local → une fois concluant, ouvrir une PR → CI verte contre une stack locale éphémère du runner → revue explicite des migrations/RLS par Ouezz → merge sur `main`.
  - **Merger sur `main` déclenche le déploiement en prod** : un job CI dédié applique les migrations validées via `supabase db push` (identifiants prod détenus uniquement en secret GitHub, jamais en local), pendant que Vercel déploie le frontend.
  - Aucune PR ne merge sans CI verte **et** revue explicite des migrations/RLS par Ouezz, sans exception, même pour un changement qui semble mineur.
  - Toute branche de fonctionnalité qui touche au schéma se teste après un `supabase db reset` (migrations + `supabase/seed.sql`) — jamais de données bricolées à la main dans une base locale qui n'est pas reproductible.
  - Les identifiants de prod (`SUPABASE_ACCESS_TOKEN`, project ref) n'existent qu'en secret GitHub Actions — jamais sur la machine de développement, jamais dans un fichier du repo.

## Principes

- **Sécurité incontournable** : l'isolation multi-tenant (`entreprise_id` + rôle, appliquée en RLS) n'est jamais négociable contre une fonctionnalité, un délai ou une simplification. Voir `00-decision-firebase-vs-supabase.md` — c'est la raison même du choix de Supabase.
- **Exactitude des calculs financiers incontournable** : tout montant est stocké et calculé en `numeric` (jamais en float) ; toute opération qui touche plusieurs tables liées à l'argent (ex. créance → transaction) est transactionnelle ; tout nouveau calcul (KPI, synthèse, cashflow) est vérifié par un cas de test concret avec un résultat attendu chiffré, pas seulement « les tests passent ».
- **Test adversarial concret** : reproduire des scénarios d'échec précis avec preuve avant/après — des tests qui passent ne suffisent pas à établir la correction d'une politique de sécurité ou d'isolation.
- **Multi-tenant assumé dès le départ** (contrairement au principe Air Ajjar « monolithe modulaire, pas de multi-tenant complexe ») : ici, l'isolation par `entreprise_id` est le socle, pas une extension.
- **Un compte prod unique change le niveau d'exigence sur la revue** : sur Air Ajjar, une erreur en dev restait sans conséquence ; ici, toute merge sur `main` touche directement les données réelles des entreprises clientes de Be Smart. La rigueur de revue avant merge — et un développement systématiquement validé en local avant toute PR — sont non négociables.
- **Zéro coût d'infrastructure de test** : le choix du Supabase CLI local (plutôt que le Database Branching payant) doit rester la référence tant qu'il couvre le besoin ; toute proposition d'outil payant doit être justifiée et validée par Ouezz avant adoption.
- **Sobriété fonctionnelle** : construire le périmètre V1 du CDC (sections 4.1 à 4.13), ne pas anticiper les modules hors périmètre (4.14) dans l'implémentation, même si le schéma ne doit pas les rendre impossibles.
- **Fidélité au classeur Excel existant** : la logique métier validée par l'usage (charges fixes/variables, CA prévisionnel, écarts prévu/réel, cashflow) doit être respectée fidèlement, pas réinventée — voir CDC section 2.
- **Pédagogie et simplicité d'usage** : l'utilisateur cible n'a pas de compétence comptable avancée — chaque écran doit rester dans l'esprit de l'onglet README du classeur actuel (CDC 2.7, 5.1).
