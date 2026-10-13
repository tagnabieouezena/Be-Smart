# Brief Claude Code — Module 4.8 : Synthèses mensuelle, trimestrielle et annuelle

*Depuis `main` (Modules 4.1 à 4.7 et navigation mergés ; accueil du CEO = `/ecarts`). Branche : `feat/module-4.8-syntheses`.*

## Objectif (CDC 4.8)

> « - Tableaux de synthèse automatiques (plus de recopie manuelle des totaux d'un onglet à l'autre).
> - Calcul du taux de réalisation des objectifs de CA.
> - Historique du solde de caisse en début/fin de période. »

Ancien onglet Excel « Synthese_Mensuelle » (CDC 2.3) : « Regroupe les résultats par trimestre (dépenses réalisées, revenus réels, résultat net, % réalisé vs objectif) avec un total annuel et le suivi du solde de caisse en début/fin de période. »

**Accès réservé au CEO** (CDC 3.2 : le comptable n'a pas accès aux indicateurs stratégiques ; les objectifs de CA sont réservés au CEO, y compris en lecture). Le comptable et la supervision Be Smart n'y ont aucun accès.

Module en **lecture seule** : aucune nouvelle table, aucune écriture, aucune nouvelle policy RLS. Les objectifs et le solde initial continuent de se saisir dans le Paramétrage (4.2).

## Ce qui existe déjà et doit être réutilisé (rien n'est recalculé)

- **Le réel de chaque mois** (CA encaissé, dépenses, résultat net, statut clos / en cours, mois avec ou sans transaction) vient de `comparaison_mensuelle(p_annee, p_date_reference)` (4.7), qui le lit lui-même dans `ecarts_mensuels` (4.6). Le trimestre et l'année sont **des sommes de ces mois**, faites en SQL en `numeric` : aucune nouvelle règle de calcul du réel.
- **Les soldes de caisse** viennent de `ecarts_mensuels` (`solde_debut`, `solde_fin_reel`) : une seule règle du solde dans tout le produit (voir « Solde de caisse »).
- **Les objectifs** viennent de la table `objectifs_ca` (4.2), lue sous RLS (CEO uniquement). C'est la seule donnée nouvelle lue par ce module.
- Côté application : `lib/format.ts` (montants FCFA, vrai signe moins, espaces insécables), `exigerRole()`, la barre de navigation par rôle, le conteneur de tableau défilant (`.tableau-defilant`, avec `position: relative`, leçon du 4.7).

## Définitions

- **CA encaissé** = somme des entrées du mois (base trésorerie, décision du 4.7 : une facture compte au mois de son paiement) ; **Dépenses** = somme des sorties ; **Résultat net** = CA encaissé − Dépenses. Libellés de l'écran : « CA encaissé », « Dépenses », « Résultat net ».
- **Trimestre** : année civile, T1 = janvier à mars, T2 = avril à juin, T3 = juillet à septembre, T4 = octobre à décembre. **Année** = année civile (décision produit n° 6).
- **Périodes affichées**, comme au 4.7 : pour l'année de la date de référence, de janvier au **mois de référence inclus** ; les 12 mois pour une année passée ; **zéro ligne** pour une année future. Un trimestre est affiché s'il contient au moins un mois affiché ; l'année l'est dès qu'un mois l'est.
- **Statut d'une période** : un mois est `clos` s'il est antérieur au mois de référence, `en_cours` s'il est le mois de référence. Un trimestre est `clos` si ses 3 mois sont affichés et clos, sinon `en_cours`. L'année est `clos` si ses 12 mois le sont, sinon `en_cours`. Le trimestre ou l'année en cours est donc calculé « **à date** » (somme des mois affichés, le mois de référence étant lui-même partiel) et porte la mention « à date ».
- **Mois sans aucune transaction** (`a_activite` faux, règle du 4.7) : il reste dans les tableaux avec des 0. Un trimestre ou une année est « avec activité » si **au moins un** de ses mois l'est.

### Objectif de CA et taux de réalisation

**Constat sur le stockage (4.2).** `objectifs_ca` stocke chaque objectif **à sa propre granularité** : `type_periode` ∈ {`mensuel`, `trimestriel`, `annuel`}, avec `annee` et `mois` (1–12) ou `trimestre` (1–4) ; un seul objectif par `(entreprise, type_periode, annee, mois, trimestre)`. Rien n'impose que les niveaux concordent : douze objectifs mensuels peuvent ne pas sommer à l'objectif trimestriel ou annuel de la même année.

**Règle (décision produit n° 1) : chaque période n'affiche que l'objectif saisi à sa propre granularité.** Pas de répartition au prorata d'un objectif annuel sur les mois ou les trimestres, pas de somme de mois présentée comme objectif de trimestre : le module n'invente aucun chiffre que le CEO n'a pas saisi. Un objectif annuel seul ne produit donc un taux qu'au niveau de l'année ; les mois et les trimestres affichent « Pas d'objectif ».

Pour chaque période (mois, trimestre, année) :

| Cas | `statut_objectif` | `taux_realisation` | `verdict_objectif` |
|---|---|---|---|
| Aucun objectif saisi pour cette période | `absent` | `null` | `null` |
| Objectif saisi à **0** | `nul` | `null` (pas de division par zéro) | `null` |
| Objectif > 0 mais **aucune transaction** dans la période (`a_activite` faux) | `defini` | `null` (comme au 4.7 : un mois vide veut dire « pas encore saisi », pas « 0 % de l'objectif ») | `null` |
| Objectif > 0, période avec activité, **clos** | `defini` | CA ÷ objectif × 100 | `atteint` si CA ≥ objectif, sinon `manque` |
| Objectif > 0, période avec activité, **en cours** | `defini` | idem, « à date » (CA à date ÷ objectif de la période entière) | `a_date` (aucun verdict) |

- **Taux au-dessus de 100 %** : affiché tel quel (111,1 %, 102,0 %), sans plafond.
- **Taux tronqué à 1 décimale, jamais arrondi** (choix technique T5) : un CA de 999 999 pour un objectif de 1 000 000 donne 99,9 % et « objectif manqué » ; « 100,0 % » n'apparaît que si l'objectif est atteint. Le verdict se décide sur la comparaison exacte `CA ≥ objectif` en `numeric`.
- Le taux est un `numeric` calculé en SQL ; l'écran l'affiche tel quel (une décimale, virgule française). Le CA est toujours un **CA encaissé**.

### Solde de caisse en début et fin de période

**Constat sur le stockage.** Le solde initial est la colonne `entreprises.solde_initial` (`numeric not null default 0`, Phase 0), éditée dans le Paramétrage. **Aucune date n'y est attachée.** `ecarts_mensuels` (4.6) calcule le solde ainsi : `solde_initial` + résultat net de **toutes** les transactions antérieures au mois, quelle que soit leur date. Conséquences, à connaître :
- une « transaction antérieure à la date du solde initial » **n'existe pas comme cas détectable** : toute transaction compte, il n'y a pas de date de coupure. La saisie rétroactive d'anciennes transactions **après** avoir saisi un solde de caisse « d'aujourd'hui » double-compte donc ces mouvements. Risque traité par la décision produit n° 4 ;
- un solde initial « absent » ne se distingue pas d'un solde à 0 (valeur par défaut) ;
- un solde initial **négatif** est accepté par la base (aucune contrainte) et se propage tel quel ;
- un solde peut devenir négatif en cours d'année (le résultat net cumulé dépasse le solde disponible) : il s'affiche avec son vrai signe moins **et** la mention « solde négatif » (jamais la couleur seule), sans bandeau d'alerte (décision produit n° 7).

**Règles du module** (aucune nouvelle règle de calcul du solde) :
1. `solde_debut` d'un mois **actif** (budget ou transaction) et `solde_fin` = `solde_fin_reel` : lus dans `ecarts_mensuels`.
2. Un mois **sans activité** n'a pas de ligne dans `ecarts_mensuels` : son solde de début est le solde de fin du mois précédent, et son solde de fin est égal à son solde de début (résultat nul).
3. Les mois sans activité **en tête d'année** reprennent le solde d'ouverture de l'année : le `solde_debut` du premier mois actif de l'année (les mois vides avant lui ont un résultat nul, donc le solde ne bouge pas).
4. Une année **sans aucun mois actif** (aucune transaction ni budget) n'a aucune ligne dans `ecarts_mensuels` : son solde d'ouverture est le `solde_fin_reel` du **dernier mois actif de la dernière année antérieure** qui en a un (lu dans `ecarts_mensuels` de cette année-là), et, s'il n'existe aucune année antérieure avec activité, `entreprises.solde_initial`. Ainsi le solde se reporte correctement sur des années vides et au début d'une nouvelle année, sans recopier la règle du 4.6 (choix technique T3).
5. **Trimestre** : `solde_debut` = solde de début de son premier mois affiché, `solde_fin` = solde de fin de son dernier mois affiché (« à date » pour le trimestre en cours). **Année** : début de janvier, fin du dernier mois affiché.

**Identités à prouver par test, à chaque granularité** : `solde_fin = solde_debut + résultat` ; **continuité** : le solde de fin d'une période est le solde de début de la suivante (mois → mois, trimestre → trimestre, année N → année N+1, y compris à travers une année vide).

## Étapes attendues

### 1. Fonction SQL `syntheses_periodes(p_annee int, p_date_reference date default current_date)`

Une fonction pour les trois granularités (choix technique T1), un tableau de lignes :

| Colonne | Contenu |
|---|---|
| `granularite` | `mois`, `trimestre` ou `annee` |
| `periode` | 1 à 12 (mois), 1 à 4 (trimestre), l'année elle-même pour `annee` |
| `statut` | `clos` ou `en_cours` |
| `a_activite` | au moins une transaction dans la période |
| `ca`, `depenses`, `resultat` | `numeric`, sommes des mois (réel du 4.7) |
| `objectif_ca` | `numeric`, `null` si aucun objectif saisi |
| `statut_objectif` | `absent`, `nul` ou `defini` |
| `taux_realisation` | `numeric` tronqué à 1 décimale, `null` selon le tableau ci-dessus |
| `verdict_objectif` | `atteint`, `manque`, `a_date` ou `null` |
| `solde_debut`, `solde_fin` | `numeric`, règles « Solde de caisse » |

Règles de sécurité (identiques au 4.7) :
- `security invoker`, `set search_path = public`, `stable` ;
- requête qui part de la CTE `ent` (`current_entreprise_id()` **et** `current_role_utilisateur() = 'ceo'`) : on ne part jamais d'une série de mois seule, sinon un comptable obtiendrait des lignes de zéros ; **zéro ligne**, pas d'erreur, pour tout autre appelant ;
- les objectifs sont lus dans `objectifs_ca` sous RLS (CEO de l'entreprise uniquement) : aucune policy ajoutée ;
- la fonction naît **sans droit d'exécution** : `revoke all … from public`, `revoke execute … from anon`, `grant execute … to authenticated` explicite. L'ACL réelle est verrouillée par assertion dans le test (aucun droit pour `public` ni `anon`, `authenticated` autorisé ; `service_role` reçoit EXECUTE par les privilèges par défaut de Supabase, comme pour les fonctions du 4.6 et du 4.7, accepté par Ouezz le 2026-10-13) ;
- tous les montants et taux en `numeric`, aucun cast en float.

Aucun nouvel index : `transactions_date_idx (entreprise_id, date)` (4.4) sert les lectures du réel, et l'index unique de `objectifs_ca` couvre la lecture des objectifs ; à confirmer et à signaler dans la PR.

### 2. Écran `/syntheses` (CEO)

- **Un tableau unique groupé par trimestre**, comme l'onglet Excel d'origine (décision produit n° 5) : pour chaque trimestre, ses trois mois puis une ligne « Total T1 » (« Total T3 — à date » si le trimestre est en cours), et en dernière ligne « **Total année {année}** » (« — à date » pour l'année en cours). Les mois futurs n'apparaissent pas.
- Colonnes : **Période**, **CA encaissé**, **Dépenses**, **Résultat net**, **Objectif de CA**, **Taux de réalisation**, **Solde de caisse au début**, **Solde de caisse à la fin**.
- Colonne « Taux de réalisation » : le taux (« 111,1 % ») suivi du verdict **en texte et en icône** (« ✓ Objectif atteint », « ✗ Objectif manqué », « à date ») ; jamais la couleur seule. Cellules sans taux : « Pas d'objectif » (`absent`), « Objectif à 0 » (`nul`), « Aucune saisie » (période sans transaction).
- Soldes négatifs : vrai signe moins (−40 000 FCFA) et mention « solde négatif ».
- Sous le titre, la ligne d'explication du 4.7 (« Base trésorerie : une facture compte au mois de son paiement. ») et un renvoi vers le Paramétrage pour saisir les objectifs et le solde initial (lien CEO).
- Sélecteur d'année comme au 4.7 (année en cours par défaut, année future non proposée).
- Mobile : le tableau défile horizontalement **dans son conteneur** (jamais sur la page ; mesurer `scrollWidth = clientWidth`) ; titres de colonnes en `scope`, première colonne en `th scope="row"`.
- **Pas de graphique** (choix technique T7).
- `exigerRole(["ceo"], "/syntheses")` : 404 pour le comptable et la supervision. Lien « **Synthèses** » ajouté à la barre du **CEO uniquement** (après « Comparaison »), et `/syntheses` ajouté aux pages autorisées du CEO dans `lib/redirection.ts`.
- Formatage : montants en FCFA entiers avec espaces insécables et vrai signe moins (`lib/format.ts` existant) ; le taux, déjà tronqué à 1 décimale en base, s'affiche sans arrondi supplémentaire ; **aucun calcul** côté TypeScript (ni somme, ni taux, ni verdict).

### 3. Libellé du solde initial dans le Paramétrage (petit ajout)

Conséquence de la décision produit n° 4 : sur l'écran `/parametrage`, le champ « Solde de caisse initial » est renommé **« Solde de caisse avant votre première transaction saisie »**, avec une ligne d'aide : « Toutes les transactions saisies s'ajoutent à ce montant, quelle que soit leur date. Si vous saisissez aussi d'anciennes transactions, indiquez le solde d'avant la plus ancienne. » Aucun changement de schéma ni de calcul.

## Jeu de test chiffré (obligatoire)

Chaque scénario s'exécute dans `BEGIN … ROLLBACK`, avec une **entreprise dédiée** (le seed ne doit pas influencer les sommes), en tant que son CEO authentifié. Les résultats sont comparés à des attendus chiffrés écrits en dur ; une valeur `null` doit rester `null`.

### Scénario 1 — année complète 2026, `syntheses_periodes(2026, '2027-01-15')`

Entreprise `Syn1`, **solde initial 100 000**.

Transactions (CA = entrées, dépenses = sorties ; le mois de décembre 2025 est **antérieur** à l'année affichée) :

| Mois | CA | Dépenses |
|---|---|---|
| Décembre 2025 | 40 000 | 90 000 |
| Janvier 2026 | 200 000 | 150 000 |
| Février | 100 000 | 180 000 |
| Mars | 0 | 60 000 |
| Avril | **aucune transaction** | |
| Mai | 300 000 | 120 000 |
| Juin | 250 000 | 100 000 |
| Juillet | 150 000 | 130 000 |
| Août | 80 000 | 50 000 |
| Septembre | 220 000 | 140 000 |
| Octobre | 180 000 | 160 000 |
| Novembre | 260 000 | 90 000 |
| Décembre | 300 000 | 200 000 |

Objectifs de CA 2026 (`objectifs_ca`, chaque niveau saisi indépendamment) :
- mensuels : janvier 180 000 ; février 150 000 ; mars **0** ; avril 100 000 ; juin 250 000 (aucun objectif mensuel en mai, juillet à décembre) ;
- trimestriels : T1 400 000 ; T2 500 000 ; T4 800 000 (aucun pour T3) ;
- annuel : 2 000 000.

Attendus (les 12 mois, les 4 trimestres, l'année ; année passée donc tout `clos`) :

| Période | Statut | Activité | CA | Dépenses | Résultat | Objectif | Statut objectif | Taux | Verdict | Solde début | Solde fin |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Mois 1 | clos | oui | 200 000 | 150 000 | 50 000 | 180 000 | defini | 111,1 | atteint | 50 000 | 100 000 |
| Mois 2 | clos | oui | 100 000 | 180 000 | −80 000 | 150 000 | defini | 66,6 | manque | 100 000 | 20 000 |
| Mois 3 | clos | oui | 0 | 60 000 | −60 000 | 0 | nul | `null` | `null` | 20 000 | −40 000 |
| Mois 4 | clos | non | 0 | 0 | 0 | 100 000 | defini | `null` | `null` | −40 000 | −40 000 |
| Mois 5 | clos | oui | 300 000 | 120 000 | 180 000 | `null` | absent | `null` | `null` | −40 000 | 140 000 |
| Mois 6 | clos | oui | 250 000 | 100 000 | 150 000 | 250 000 | defini | 100,0 | atteint | 140 000 | 290 000 |
| Mois 7 | clos | oui | 150 000 | 130 000 | 20 000 | `null` | absent | `null` | `null` | 290 000 | 310 000 |
| Mois 8 | clos | oui | 80 000 | 50 000 | 30 000 | `null` | absent | `null` | `null` | 310 000 | 340 000 |
| Mois 9 | clos | oui | 220 000 | 140 000 | 80 000 | `null` | absent | `null` | `null` | 340 000 | 420 000 |
| Mois 10 | clos | oui | 180 000 | 160 000 | 20 000 | `null` | absent | `null` | `null` | 420 000 | 440 000 |
| Mois 11 | clos | oui | 260 000 | 90 000 | 170 000 | `null` | absent | `null` | `null` | 440 000 | 610 000 |
| Mois 12 | clos | oui | 300 000 | 200 000 | 100 000 | `null` | absent | `null` | `null` | 610 000 | 710 000 |
| T1 | clos | oui | 300 000 | 390 000 | −90 000 | 400 000 | defini | 75,0 | manque | 50 000 | −40 000 |
| T2 | clos | oui | 550 000 | 220 000 | 330 000 | 500 000 | defini | 110,0 | atteint | −40 000 | 290 000 |
| T3 | clos | oui | 450 000 | 320 000 | 130 000 | `null` | absent | `null` | `null` | 290 000 | 420 000 |
| T4 | clos | oui | 740 000 | 450 000 | 290 000 | 800 000 | defini | 92,5 | manque | 420 000 | 710 000 |
| Année 2026 | clos | oui | 2 040 000 | 1 380 000 | 660 000 | 2 000 000 | defini | 102,0 | atteint | 50 000 | 710 000 |

Ce que le scénario prouve :
- **Objectif atteint** : janvier (111,1 %, > 100 %), juin (**exactement** 100,0 %, atteint car CA ≥ objectif), T2 (110,0 %), année (102,0 %). **Objectif manqué** : février (66,6 %, tronqué et non 66,7), T1 (75,0 %), T4 (92,5 %).
- **Objectif à 0** (mars) : pas de division par zéro, `statut_objectif = nul`, taux et verdict `null`. **Objectif absent** (mai, T3…) : `null`, **sans répartition au prorata de l'objectif annuel** (mai a un CA de 300 000 et aucun taux). **Mois vide avec objectif** (avril, 100 000) : `statut_objectif = defini` mais taux `null` (règle « aucune saisie »).
- **Granularités indépendantes** : les objectifs mensuels de T1 (180 000 + 150 000 + 0) ne somment pas à l'objectif trimestriel (400 000) ; chaque niveau garde le sien.
- **Mois vide** (avril) : présent, à 0, `a_activite` faux, solde de fin = solde de début (−40 000). Le trimestre T2 est « avec activité » grâce à mai et juin.
- **Solde qui devient négatif** : −40 000 à la fin de mars (et de T1), repris en avril, redevenu positif en mai.
- **Transaction antérieure** : celle de décembre 2025 (+40 000 −90 000 = −50 000) fait passer le solde d'ouverture de 2026 de 100 000 à **50 000** (100 000 − 50 000) ; c'est le seul sens que prend « transaction antérieure » tant que le solde initial n'a pas de date (voir « Solde de caisse »).
- **Cohérences** (toutes en `numeric` exact) : somme des 12 CA = somme des 4 trimestres = CA de l'année = 2 040 000 ; dépenses 1 380 000 ; résultat 660 000 = 2 040 000 − 1 380 000 ; **identité** `solde_fin = solde_debut + résultat` sur chacune des 17 lignes ; **continuité** : fin du mois n = début du mois n+1 (11 paires), fin de T1 = début de T2, fin de T2 = début de T3, fin de T3 = début de T4, et solde de fin de l'année (710 000) = solde de fin de T4 = solde de fin de décembre ; les CA, dépenses et résultats mensuels sont identiques à ceux de `comparaison_mensuelle(2026, '2027-01-15')` (4.7), et le CA de l'année est identique à son `ca_cumul` de décembre.

### Scénario 2 — même entreprise, année en cours « à date » : `syntheses_periodes(2026, '2026-08-20')`

Août est le mois de référence. Les mois de janvier à juin et T1, T2 sont **identiques au scénario 1** (clos). Lignes qui changent ou qui illustrent « à date » (juillet reste clos, août devient `en_cours`, T4 et les mois de septembre à décembre n'apparaissent plus) :

| Période | Statut | Activité | CA | Dépenses | Résultat | Objectif | Statut objectif | Taux | Verdict | Solde début | Solde fin |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Mois 7 | clos | oui | 150 000 | 130 000 | 20 000 | `null` | absent | `null` | `null` | 290 000 | 310 000 |
| Mois 8 | en_cours | oui | 80 000 | 50 000 | 30 000 | `null` | absent | `null` | `null` | 310 000 | 340 000 |
| T3 | en_cours | oui | 230 000 | 180 000 | 50 000 | `null` | absent | `null` | `null` | 290 000 | 340 000 |
| Année 2026 | en_cours | oui | 1 080 000 | 790 000 | 290 000 | 2 000 000 | defini | 54,0 | a_date | 50 000 | 340 000 |

Ce que le scénario prouve : un trimestre en cours (T3) et l'année en cours sont calculés **à date** (sommes des mois affichés), avec `statut = en_cours` ; le taux de l'année à date (1 080 000 ÷ 2 000 000 = 54,0 %) est affiché avec le verdict `a_date` (aucun « atteint » ni « manqué ») ; le solde de fin de T3 et de l'année est celui de fin août (340 000) ; T4 et septembre à décembre sont absents (aucune ligne pour le futur).

### Scénario 3 — continuité entre années, y compris années vides (même entreprise, date de référence `2027-01-15`)

| Appel | Attendus |
|---|---|
| `syntheses_periodes(2025, …)` | janvier à novembre 2025 : `a_activite` faux, CA, dépenses, résultat à 0, solde 100 000 → 100 000 ; décembre : CA 40 000, dépenses 90 000, résultat −50 000, solde 100 000 → 50 000 ; T1 à T3 à 0 (solde 100 000 → 100 000) ; T4 : 40 000 / 90 000 / −50 000, solde 100 000 → 50 000 ; année 2025 : 40 000 / 90 000 / −50 000, solde 100 000 → **50 000** ; objectifs `absent` partout |
| `syntheses_periodes(2026, …)` | scénario 1 : solde d'ouverture 2026 = **50 000** = solde de fin 2025 |
| `syntheses_periodes(2027, …)` | janvier 2027 `en_cours`, `a_activite` faux, 0 / 0 / 0, solde **710 000 → 710 000** (report du solde de fin 2026 sur une année sans aucune saisie, règle 4) ; T1 et année `en_cours`, solde 710 000 → 710 000 |
| `syntheses_periodes(2024, …)` | année **entièrement vide** et antérieure à toute activité : 12 mois à 0, `a_activite` faux, solde **100 000 → 100 000** partout (aucune année antérieure avec activité : retombée sur `solde_initial`), année 2024 : 0 / 0 / 0, solde 100 000 → 100 000 |
| `syntheses_periodes(2028, '2027-01-15')` | année future : **zéro ligne** |

Continuité prouvée par test : fin de décembre 2025 (50 000) = début de janvier 2026 ; fin de l'année 2025 = début de l'année 2026 ; fin de l'année 2026 (710 000) = début de l'année 2027 ; fin de 2024 = début de 2025 (100 000).

### Scénario 4 — bords de l'objectif (entreprise `Syn2`, solde initial 0, `syntheses_periodes(2026, '2026-04-15')`)

Aucune dépense. CA : janvier 999 999, février 1 000 000, mars 500 000, aucune transaction en avril. Objectifs : mensuels janvier 1 000 000, février 1 000 000, mars 0 ; trimestriel T1 2 499 999 ; aucun annuel.

| Période | Statut | CA | Objectif | Statut objectif | Taux | Verdict | Solde début | Solde fin |
|---|---|---|---|---|---|---|---|---|
| Janvier | clos | 999 999 | 1 000 000 | defini | **99,9** | **manque** | 0 | 999 999 |
| Février | clos | 1 000 000 | 1 000 000 | defini | **100,0** | atteint | 999 999 | 1 999 999 |
| Mars | clos | 500 000 | 0 | nul | `null` | `null` | 1 999 999 | 2 499 999 |
| Avril | en_cours | 0 | `null` | absent | `null` | `null` | 2 499 999 | 2 499 999 |
| T1 | clos | 2 499 999 | 2 499 999 | defini | **100,0** | atteint | 0 | 2 499 999 |
| T2 | en_cours | 0 | `null` | absent | `null` | `null` | 2 499 999 | 2 499 999 |
| Année 2026 | en_cours | 2 499 999 | `null` | absent | `null` | `null` | 0 | 2 499 999 |

Prouve : la troncature (99,9999 % s'affiche 99,9, jamais 100,0 tant que l'objectif n'est pas atteint), l'égalité stricte (objectif exactement atteint), le trimestre atteint à l'unité près, l'objectif à 0 avec un CA positif.

### Scénario 5 — entreprise sans aucune transaction ni objectif (`Syn3`, solde initial 250 000, `syntheses_periodes(2026, '2026-05-20')`)

Mois 1 à 5 (mai `en_cours`), T1 `clos`, T2 `en_cours`, année `en_cours` : toutes les lignes à 0, `a_activite` faux, `statut_objectif = absent`, taux et verdict `null`, **solde 250 000 → 250 000** partout. Aucune division par zéro, aucune erreur.

## Tests adversariaux (obligatoires, en utilisateur authentifié réel, jamais en `service_role`)

1. Le **comptable** de l'entreprise appelle `syntheses_periodes` : **zéro ligne**, alors que ses transactions lui sont lisibles. Lecture directe de `objectifs_ca` par le comptable : zéro ligne. La restriction vient de la fonction.
2. Le compte de **supervision Be Smart** (claim `super_admin`) : zéro ligne.
3. **Isolation A / B** : deux entreprises avec leurs propres transactions **et leurs propres objectifs** (par exemple A : janvier 180 000, B : janvier 777 000, avec des CA différents) ; le CEO de A ne voit que ses chiffres, ses objectifs et ses soldes, le CEO de B que les siens.
4. **`anon`** : appel refusé (`permission denied`).
5. **ACL réelles** de la fonction assertées dans le script : aucun droit pour `public` ni `anon`, `authenticated` autorisé ; l'audit d'isolation reste vert.
6. **Entreprise sans transaction ni objectif** (scénario 5) : aucune erreur.
7. **Contrôle négatif** : pour chaque règle ci-dessous, le test doit **échouer** si on la retire (à vérifier en local en modifiant temporairement la fonction, puis en la restaurant ; à consigner dans la PR) :
   - restriction au CEO ;
   - garde « objectif à 0 » (sinon division par zéro) ;
   - garde « période sans transaction » sur le taux (sinon avril afficherait 0,0 %) ;
   - troncature à 1 décimale / verdict exact (scénario 4) ;
   - report du solde d'ouverture d'une année vide (scénarios 3 : 2024 et 2027) ;
   - absence de prorata (mai reste sans taux malgré l'objectif annuel).

## Hors de ce module

- Export PDF ou CSV des synthèses : Module 4.13.
- Cashflow prévisionnel et solde prévu sur plusieurs périodes : Module 4.9.
- Comparaison année sur année (CDC 4.14) ; variations d'un mois sur l'autre : déjà faites au 4.7, non répétées ici.
- Tableau de bord KPI (« % de réalisation du CA » d'un indicateur global) : Module 4.11, qui reprendra la fonction de ce module.
- Saisie ou modification des objectifs et du solde initial : restent dans le Paramétrage (4.2).
- Notifications (objectif manqué, solde négatif) : Module 4.12.

## Livrable attendu pour revue

PR depuis `feat/module-4.8-syntheses` vers `main`, avec :
- le SQL complet de la migration en clair dans la description (fonction, GRANT, éventuel index) et les ACL réelles ;
- le résultat réel de chaque scénario chiffré, comparé aux attendus ci-dessus (années, trimestres, mois, soldes) ;
- la preuve des tests adversariaux et des contrôles négatifs ;
- les captures bureau et mobile de `/syntheses` ;
- une nouvelle étape CI pour le test SQL, les nouveaux cas dans `acces_pages.mjs` (`/syntheses` dans la matrice rôle × page, lien de barre du CEO seulement) et dans les tests unitaires de formatage ;
- CI verte. La migration attend l'approbation explicite d'Ouezz avant merge.

## Décisions produit pour Ouezz

Uniquement ce qui change ce que le CEO voit ou comprend, avec ma recommandation.

1. **Objectif à un autre niveau que la période affichée.** Recommandation : chaque période n'affiche que l'objectif saisi à son propre niveau ; **aucun prorata**, aucune somme de mois présentée comme objectif. Conséquence visible : avec un seul objectif annuel, seule l'année affiche un taux ; les mois et trimestres affichent « Pas d'objectif ». Alternatives : répartir l'objectif annuel au prorata (÷12, ÷4), qui fabrique des objectifs mensuels que le CEO n'a pas fixés et ignore la saisonnalité ; ou sommer les objectifs mensuels en objectif de trimestre (faux dès qu'il en manque un).
2. **Période sans aucune transaction.** Recommandation : pas de taux (« Aucune saisie »), cohérent avec le 4.7 où un mois vide est « pas encore saisi ». Alternative : afficher 0,0 % (objectif manqué), qui punit un mois que la comptable n'a pas encore saisi.
3. **Trimestre et année en cours.** Recommandation : taux « à date » (CA à date ÷ objectif de la période entière), **sans verdict** ni couleur « manqué » tant que la période n'est pas close. Alternative : ne pas afficher de taux avant la clôture.
4. **Solde de caisse initial sans date.** Recommandation : ne **pas** ajouter de date en V1 ; renommer le champ du Paramétrage « Solde de caisse avant votre première transaction saisie » avec une ligne d'aide (étape 3 du brief), car toutes les transactions saisies s'ajoutent au solde initial, quelle que soit leur date. Risque assumé : un CEO qui saisit le solde d'aujourd'hui puis d'anciennes transactions double-compte ces mouvements. Alternative : ajouter une colonne `date_solde_initial` (migration sur `entreprises`, modification du calcul du solde du 4.6 pour ignorer les transactions antérieures à cette date, nouveau test) ; plus rigoureux, plus lourd, et c'est une révision d'un module déjà mergé.
5. **Forme de l'écran.** Recommandation : **un tableau unique groupé par trimestre** (mois, puis total du trimestre, puis total de l'année), comme l'onglet Excel d'origine, avec un sélecteur d'année. Alternative : trois onglets mois / trimestres / année (plus de clics, mais un tableau plus court sur mobile).
6. **Exercice = année civile** (T1 = janvier à mars). Recommandation : oui en V1. Si un client a un exercice décalé, ce sera une évolution (paramètre de mois de début d'exercice), pas une adaptation de ce module.
7. **Solde négatif.** Recommandation : afficher le vrai signe moins et la mention « solde négatif », **sans bandeau d'alerte** (les alertes de solde prévisionnel relèvent du 4.6 et du cashflow 4.9). Alternative : bandeau d'alerte en tête de page.

## Choix techniques proposés

Ce que j'ai tranché, avec la justification.

- **T1 — Une seule fonction `syntheses_periodes`** avec une colonne `granularite`, plutôt que trois fonctions : une seule ACL à verrouiller, une seule requête à tester, et la continuité des soldes entre granularités se prouve dans un seul jeu de lignes.
- **T2 — Réutilisation, pas de recalcul.** Réel = `comparaison_mensuelle` (4.7) ; soldes = `ecarts_mensuels` (4.6) ; trimestres et année = sommes SQL des mois. Si le 4.6 ou le 4.7 évolue, le 4.8 suit sans autre modification, et le test recoupe les montants avec `comparaison_mensuelle` et son `ca_cumul`.
- **T3 — Report du solde d'ouverture sans dupliquer la règle du 4.6.** Pour une année sans aucune activité, le solde d'ouverture est le solde de fin du dernier mois actif de la dernière année antérieure ayant une activité, lu dans `ecarts_mensuels` de cette année-là ; à défaut `entreprises.solde_initial`. Alternative écartée : recalculer `solde_initial + somme des résultats antérieurs`, qui dupliquerait la règle du solde (deux endroits à garder cohérents).
- **T4 — Mois sans activité = solde reporté.** Le solde d'un mois vide est celui de la dernière fin connue (ou le solde d'ouverture de l'année) ; sans cela, les mois vides n'auraient pas de solde, car `ecarts_mensuels` ne renvoie aucune ligne pour eux.
- **T5 — Taux tronqué à 1 décimale, verdict exact.** `taux = trunc(CA ÷ objectif × 100, 1)` et `atteint ⇔ CA ≥ objectif`, comparés en `numeric`. Un arrondi afficherait « 100,0 % » pour 99,9999 % tout en disant « manqué ». C'est différent des pourcentages du 4.6 et du 4.7 (arrondis à 2 décimales) parce qu'ici le pourcentage porte un verdict.
- **T6 — `statut_objectif` et `verdict_objectif` calculés en SQL**, pas en TypeScript : la règle vit à un seul endroit, testée, et l'écran ne fait aucun calcul.
- **T7 — Pas de graphique.** Le taux de réalisation et les soldes se lisent mieux dans le tableau, et un graphique de plus ajouterait du code à tester sans information nouvelle par rapport au 4.7. Le composant SVG du 4.7 reste disponible si Ouezz en demande un (par exemple l'évolution du solde de caisse).
- **T8 — Aucune policy ni table nouvelle.** Les objectifs sont lus par `security invoker` sous la RLS existante (CEO uniquement) ; la fonction ajoute sa propre restriction au CEO, comme au 4.6 et au 4.7.
- **T9 — Pas de nouvel index** (`transactions_date_idx` et l'index unique de `objectifs_ca` existent) ; à confirmer dans la PR.
- **T10 — Tests** : même style que le 4.7 (jsonb attendus écrits en dur, `BEGIN … ROLLBACK`, utilisateurs authentifiés réels), contrôles négatifs consignés dans la PR, étape CI dédiée, `/syntheses` dans la matrice de `acces_pages.mjs`.
