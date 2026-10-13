# Brief Claude Code — Module 4.7 : Comparaison mensuelle CA / Dépenses / Résultat net

*Depuis `main` (Modules 4.1 à 4.6 mergés, PR #12 « navigation et parcours d'accueil » mergée : l'accueil du CEO est `/ecarts`). Branche : `feat/module-4.7-comparaison-mensuelle`.*

## Objectif (CDC 4.7)

> « Nouveau module limité, par choix, à ces trois indicateurs globaux (pas de détail par catégorie de dépense) :
> - Graphique d'évolution mensuelle du CA réel, des dépenses réelles et du résultat net sur l'année en cours.
> - Variation en % d'un mois sur l'autre pour chacun des trois indicateurs (ex. "CA +12% vs mois précédent", "Résultat net -8 000 FCFA vs mois précédent").
> - Indicateur visuel simple (flèche verte hausse / rouge baisse) sur le tableau de bord du CEO.
> - Vue tableau récapitulatif mois par mois sur toute l'année en cours. »

**Accès réservé au CEO** (CDC 3.2 : indicateurs stratégiques). Le comptable et la supervision Be Smart n'y ont aucun accès.

Module en **lecture seule** : aucune nouvelle table, aucune écriture. Hors périmètre V1 (CDC 4.14) : comparaison année sur année.

## Définitions

Le mois d'une transaction est celui de `transactions.date`.

- **CA encaissé** (« CA réel » du CDC) = somme des `transactions.montant` avec `type = 'entree'`.
- **Dépenses réelles** = somme des `transactions.montant` avec `type = 'sortie'` (fixes et variables confondues).
- **Résultat net** = CA encaissé − Dépenses réelles.

**Ces trois définitions sont déjà celles du Module 4.6** (`revenus_reel`, `depenses_reel`, `resultat_reel` de `ecarts_mensuels`). Elles ne sont pas réécrites : voir « Réutilisation du 4.6 » ci-dessous.

**Pas de double comptage d'une créance payée.** Vérification faite sur le brief du 4.5 : une créance n'est jamais une transaction (table `creances` distincte, ni statut ni montant encaissé stockés). Quand le client paie, la comptable insère **une** transaction d'entrée liée (`creance_id`) : c'est la seule ligne qui compte dans le CA, au mois de la date du paiement. La fonction de ce module ne lit donc jamais la table `creances`. Conséquence assumée : le CA est un **CA encaissé** (base trésorerie), pas un CA facturé. Une facture émise en février et payée en mars apparaît en mars. C'est la même règle que le 4.6, et le « résultat net » est donc un résultat de trésorerie, pas un résultat comptable (SYSCOHADA hors V1). Décidé le 2026-10-13 : les libellés de l'écran sont **« CA encaissé »** et **« Résultat net »**, avec une ligne d'explication sous le titre de l'écran (voir §2).

## Réutilisation du 4.6 (ne pas dupliquer)

La fonction du 4.7 s'appuie sur `ecarts_mensuels(p_annee, p_date_reference)` pour les trois montants réels (`revenus_reel`, `depenses_reel`, `resultat_reel`) et le `statut_mois`. Une seule règle du réel dans tout le produit : si le 4.6 change, le 4.7 suit sans autre modification.

Pièges à éviter :
- `ecarts_mensuels` ne renvoie une ligne que pour un mois qui a un budget ou au moins une transaction. Les mois vides (CA = 0, dépenses = 0, résultat = 0) doivent être reconstitués côté 4.7 (voir la fonction ci-dessous), sans inventer de ligne pour les mois futurs.
- `a_activite` ne se déduit pas de la présence d'une ligne dans `ecarts_mensuels` : un mois qui a un budget mais aucune transaction y figure aussi. Elle se calcule par une existence de transaction du mois (agrégat mensuel sur `transactions`, une seule passe).
- Ne jamais partir d'une série de mois (`generate_series`) seule : un comptable obtiendrait 12 lignes de zéros au lieu de zéro ligne. La restriction au CEO doit figurer dans la requête du 4.7 elle-même (même CTE `ent` que le 4.6), et pas seulement dans la fonction sous-jacente.

## Étapes attendues

### 1. Fonction SQL `comparaison_mensuelle(p_annee int, p_date_reference date default current_date)`

Une ligne par mois, de janvier jusqu'au **mois de la date de référence inclus** si `p_annee` est l'année de référence ; les 12 mois si l'année est passée ; **zéro ligne** si l'année est future. L'écran n'a donc jamais à filtrer les mois futurs.

Colonnes :
- `mois` (1 à 12), `statut_mois` (`clos` / `en_cours`), `a_activite` (au moins une transaction dans le mois) ;
- `ca`, `depenses`, `resultat` : numeric ;
- pour le CA et les dépenses : `ca_variation` et `depenses_variation` (en FCFA, courant − précédent), `ca_variation_pct` et `depenses_variation_pct` ;
- pour le résultat net : `resultat_variation` (en FCFA) **uniquement**, aucun pourcentage ;
- `ca_cumul`, `depenses_cumul`, `resultat_cumul` : somme cumulative des mois renvoyés depuis janvier (fonction de fenêtre, en `numeric`). La dernière ligne alimente la ligne « Total année à date » de l'écran : aucune somme de montants n'est faite côté JavaScript.

Règles de variation (toutes les variations sont `null` quand la comparaison n'a pas de sens, jamais 0 par défaut). Les règles 2 à 5 sont implémentées **une seule fois**, dans la fonction pure `variation_mensuelle` (voir §1 bis), que cette fonction appelle :
1. **Janvier** : pas de mois précédent dans l'année demandée, donc toutes les variations sont `null`. Pas de comparaison avec décembre de l'année précédente (décision du 2026-10-13).
2. **Mois sans aucune transaction, des deux côtés** : toutes les variations sont `null` si le mois courant **ou** le mois précédent a `a_activite = false`. Un mois vide signifie le plus souvent « pas encore saisi » : il n'est comparable ni comme référence ni comme point de comparaison (décision du 2026-10-13). Le mois vide reste présent dans le résultat, avec CA = dépenses = résultat = 0.
3. **Mois précédent à 0 mais avec activité** (ex. CA précédent = 0 alors qu'il y a eu des dépenses) : la variation en FCFA est calculée, le pourcentage est `null` (pas de division par zéro, pas d'infini).
4. **Cas général** : `variation = courant − précédent` ; `variation_pct = variation / précédent × 100` si précédent > 0.
5. **Résultat net** : variation en FCFA seulement. Un pourcentage n'a pas de sens quand le résultat change de signe ou passe par zéro (CDC : l'exemple est en FCFA).
6. **Mois en cours** : calculé « à date » comme au 4.6. Il porte `statut_mois = 'en_cours'` ; ses variations sont fournies mais l'écran les marque « à date » (voir §3).

Arrondi et format :
- `variation_pct` est un `numeric` arrondi à 2 décimales dans la fonction (même convention que le 4.6) ; l'écran l'affiche avec **1 décimale**, séparateur décimal français (« +33,3 % »).
- Les montants sont affichés en FCFA entiers, espace insécable comme séparateur de milliers (« 1 250 000 FCFA »), signe explicite sur les variations (« +90 000 FCFA », « −60 000 FCFA » avec le vrai signe moins).
- Tous les montants et pourcentages sont en `numeric`, sans aucun cast en float.

Sécurité (identique au 4.6, mêmes règles) :
- `security invoker`, jamais `security definer` ; `set search_path = public` ;
- filtre `entreprise_id = current_entreprise_id()` ;
- **zéro ligne** si `current_role_utilisateur() <> 'ceo'` (comptable, supervision) : un résultat vide, pas une erreur ;
- la fonction naît **sans droit d'exécution** : `revoke execute … from public`, `grant execute` explicite à `authenticated` uniquement. Les ACL réelles sont vérifiées et verrouillées par assertion dans le test, et l'audit d'isolation doit rester vert.

Aucun index à ajouter a priori : l'index `transactions (entreprise_id, date)` existe depuis le 4.6 ; à confirmer et à signaler dans la PR.

### 1 bis. Fonctions pour le bandeau

Deux fonctions, pour que le calcul du réel et les règles de variation n'existent qu'une fois.

**`variation_mensuelle(courant, precedent, a_courant, a_precedent)`** : fonction **pure** (aucun accès aux tables, `immutable`) qui porte les règles 2, 3 et 4 et l'arrondi : renvoie la variation en FCFA et le pourcentage (2 décimales), tous deux `null` si l'un des deux mois est sans activité, et pourcentage `null` si le précédent vaut 0. `comparaison_mensuelle` et `comparaison_accueil` l'appellent toutes les deux : une seule règle dans tout le produit, aucun risque de divergence entre l'écran annuel et le bandeau. Elle naît elle aussi **sans droit d'exécution**, puis `grant execute` explicite à `authenticated` (les fonctions `security invoker` qui l'appellent s'exécutent avec les droits de l'appelant) ; aucun droit pour `public` ni `anon`. Elle ne lit aucune donnée, donc aucun risque d'isolation.

**`comparaison_accueil(p_date_reference)`** : une ligne pour le CEO, **zéro ligne** pour tout autre rôle.
- Elle détermine le dernier mois clos et le mois précédent (tableau ci-dessus), puis lit leur réel dans `ecarts_mensuels` pour les **une ou deux années** concernées (`ecarts_mensuels(N, date)` et, en février seulement, `ecarts_mensuels(N−1, date)`). Un mois absent du résultat vaut 0, avec `a_activite = false` (existence de transaction du mois, comme pour la fonction annuelle).
- Colonnes : `annee_clos`, `mois_clos`, `annee_precedent`, `mois_precedent` ; `ca`, `depenses`, `resultat` du mois clos et leurs équivalents `*_precedent` ; `a_activite`, `a_activite_precedent` ; `ca_variation`, `ca_variation_pct`, `depenses_variation`, `depenses_variation_pct`, `resultat_variation` (FCFA seulement pour le résultat).
- Mêmes règles de sécurité que `comparaison_mensuelle` : requête qui part de la CTE `ent` (CEO uniquement, filtre `current_entreprise_id()`), `security invoker`, `set search_path = public`, née sans droit d'exécution, `revoke execute … from public`, `grant execute` explicite à `authenticated` uniquement, ACL réelles verrouillées par assertion.

**Pourquoi cette approche plutôt que les alternatives** :
- *Appeler `comparaison_mensuelle` deux fois depuis l'application* : les règles de variation seraient recopiées en TypeScript, avec des montants manipulés en nombres JavaScript (flottants), contre la règle `numeric` du projet.
- *Ajouter un paramètre à `comparaison_mensuelle` pour qu'elle compare janvier à décembre* : cela ferait disparaître la décision 5 (janvier sans variation sur le tableau annuel) en la rendant dépendante d'un drapeau.
- *Fonction dédiée et fonction pure partagée* : un peu plus de SQL à relire, mais chaque règle a un seul endroit, et le test de cohérence (bandeau = ligne correspondante du tableau annuel, quand les deux mois sont dans la même année) prouve qu'elles ne divergent pas.

### 2. Écran dédié `/comparaison` (CEO)

- Titre de l'écran suivi d'une ligne d'explication : « Base trésorerie : une facture compte au mois de son paiement. »
- Sélecteur d'année (année en cours par défaut). Année future non proposée.
- **Graphique** d'évolution mensuelle (SVG écrit à la main, composant serveur, sans dépendance : décidé le 2026-10-13) : CA encaissé, dépenses et résultat net, un point par mois affiché. Le graphique s'arrête au mois en cours (pas de mois futurs). Alternative textuelle : le tableau est lisible sans le graphique, et le graphique porte un titre et un résumé accessible.
- **Tableau récapitulatif mois par mois** sur l'année : pour chaque mois, CA, Dépenses, Résultat net, et les variations (% et FCFA pour le CA et les dépenses, FCFA pour le résultat). Le mois en cours porte la mention « à date ». Une variation `null` s'affiche « — ». Quand le pourcentage est `null` mais la variation en FCFA existe (règle 3), l'écran affiche la valeur en FCFA seule. Une ligne **« Total année à date »** clôt le tableau (CA encaissé, dépenses, résultat net), alimentée par les colonnes de cumul de la dernière ligne.
- Tableau utilisable sur mobile : défilement horizontal dans son conteneur, jamais sur la page.
- Contrôle du rôle CEO côté serveur (404 pour les autres rôles, comme `/ecarts`). Lien « Comparaison » ajouté à la navigation du CEO uniquement.

### 3. Indicateur à flèches sur l'accueil du CEO (solution provisoire)

Le tableau de bord KPI (Module 4.11) n'existe pas encore, et l'accueil du CEO est `/ecarts` depuis la PR #12.

**Solution provisoire retenue (décidé le 2026-10-13)** : un bandeau de trois indicateurs (CA, Dépenses, Résultat net) en haut de `/ecarts`, calculé sur le **dernier mois clos** par rapport au mois qui le précède. Le mois en cours n'est jamais comparé sur l'accueil : un CA à date n'est pas comparable à un mois complet (même logique que l'absence d'alerte d'écart sur un mois non clos au 4.6). Chaque indicateur affiche : la valeur du dernier mois clos, la variation (« CA +12,0 % vs mois précédent », « Résultat net −8 000 FCFA vs mois précédent ») et une flèche.

Ce bandeau sera repris tel quel par le tableau de bord du 4.11.

**Règle de comparaison (décidé le 2026-10-13).** Le bandeau compare toujours le **dernier mois clos** au **mois calendaire qui le précède**, même si ce mois est dans l'année précédente. Le tableau annuel de `/comparaison` ne change pas : janvier y reste sans variation (décision 5).

| Date de référence | Dernier mois clos | Mois précédent | Années concernées |
|---|---|---|---|
| Janvier N | décembre N−1 | novembre N−1 | N−1 |
| **Février N** | **janvier N** | **décembre N−1** | **N et N−1** |
| Mars à décembre N | mois précédent le mois en cours | celui d'avant | N |

Les règles de mois vide (règle 2 symétrique) s'appliquent : si l'un des deux mois n'a aucune transaction, le bandeau affiche la valeur du dernier mois clos sans flèche et la mention « Pas de comparaison ». Idem si le dernier mois clos n'a pas de variation pour une autre raison (aucune donnée du tout).

**Source des données : fonction `comparaison_accueil(p_date_reference date default current_date)`** (voir §1 bis). Le bandeau fait un seul appel, sans aucun calcul côté JavaScript.

### 4. Sens des flèches (décidé le 2026-10-13)

Le CDC dit « flèche verte hausse / rouge baisse ». Pris à la lettre, une hausse des **dépenses** serait verte, alors qu'elle est défavorable. Décision :
- **la flèche suit le sens de la variation** : ▲ hausse, ▼ baisse, « = » stable (variation nulle) ;
- **la couleur suit le caractère favorable** : hausse du CA ou du résultat = favorable (vert), baisse = défavorable (rouge) ; hausse des dépenses = défavorable (rouge), baisse = favorable (vert) ; stable = neutre.

Le signal ne repose **jamais sur la couleur seule** : signe + ou − explicite sur la valeur, flèche, et un libellé accessible (« hausse favorable », « baisse défavorable »). Couleurs : jetons `--color-positif` et `--color-negatif` de `docs/06-design-principes-et-tokens.md` (PR #15) une fois les tokens implémentés ; d'ici là, des vert et rouge sobres avec un contraste d'au moins 4.5:1 sur le fond.

### 5. Jeu de test chiffré (obligatoire, règle du projet)

Dans le script de test, créer une **entreprise dédiée** dans `BEGIN … ROLLBACK` (le seed ne doit pas influencer les sommes), puis appeler `comparaison_mensuelle(2026, '2026-05-20')` en tant que son CEO. Mai 2026 est le mois en cours ; juin à décembre n'apparaissent pas.

Cinq mois, chacun prouvant une règle distincte (avec 4 mois, une des règles resterait sans preuve) :

| Mois | Transactions |
|---|---|
| Janvier | entrées 200 000 ; sorties 100 000 (fixe) et 50 000 (variable) |
| Février | **aucune transaction** (une créance « Alpha » de 100 000 facturée le 2026-02-05, échéance 2026-03-31, sans paiement) |
| Mars | entrée de 200 000 (vente) ; **entrée de 100 000 liée à la créance Alpha** (paiement du 2026-03-10) ; sorties 80 000 (fixe) et 40 000 (variable) |
| Avril | aucune entrée ; sortie de 60 000 |
| Mai (en cours) | entrée de 90 000 ; sortie de 80 000 |

Attendus de `comparaison_mensuelle(2026, '2026-05-20')` :

| Mois | CA | Dépenses | Résultat | Var. CA | Var. CA % | Var. dép. | Var. dép. % | Var. résultat |
|---|---|---|---|---|---|---|---|---|
| Janvier | 200 000 | 150 000 | 50 000 | `null` | `null` | `null` | `null` | `null` |
| Février | 0 | 0 | 0 | `null` | `null` | `null` | `null` | `null` |
| Mars | 300 000 | 120 000 | 180 000 | `null` | `null` | `null` | `null` | `null` |
| Avril | 0 | 60 000 | −60 000 | −300 000 | −100,00 | −60 000 | −50,00 | −240 000 |
| Mai (à date) | 90 000 | 80 000 | 10 000 | +90 000 | `null` | +20 000 | +33,33 | +70 000 |

Ce que chaque ligne prouve :
- **Janvier** : pas de mois précédent, variations `null` (règle 1).
- **Février** : règle 2 côté mois courant. Le mois sans transaction (`a_activite = false`) est bien présent dans le résultat, avec CA = dépenses = résultat = 0, et toutes ses variations sont `null` (pas de −100 % par rapport à janvier).
- **Mars** : règle 2 côté mois précédent : le mois précédent (février) n'a aucune transaction, donc toutes les variations sont `null`. Le CA vaut 300 000 : 200 000 de vente + **un seul** paiement de créance de 100 000. Le CA de février vaut 0 alors que la créance existe déjà : la créance n'est pas comptée à sa facturation, et le paiement n'est pas compté deux fois (une seule ligne `transactions`, la créance n'en ajoute aucune).
- **Avril** : CA qui tombe à 0 (−100,00 %), dépenses divisées par deux (−50,00 %), résultat qui **change de signe** (180 000 → −60 000, soit −240 000 FCFA, sans pourcentage).
- **Mai** : le mois précédent a un CA de 0 mais avec activité (dépenses de 60 000) : variation de CA +90 000 FCFA, **pourcentage `null`** (règle 3). Variation des dépenses +33,33 % (20 000 / 60 000 = 0,33333… arrondi à 2 décimales) : cas d'arrondi. Résultat de −60 000 à +10 000 : +70 000 FCFA.

Contrôles de cohérence, tous en `numeric` exact :
- somme des CA des cinq mois = 590 000 ; somme des dépenses = 410 000 ; somme des résultats = 180 000 = 590 000 − 410 000 (inchangées par la règle 2 : elle ne touche que les variations, pas les montants) ;
- cumuls attendus (`ca_cumul` / `depenses_cumul` / `resultat_cumul`) :

| Mois | CA cumulé | Dépenses cumulées | Résultat cumulé |
|---|---|---|---|
| Janvier | 200 000 | 150 000 | 50 000 |
| Février | 200 000 | 150 000 | 50 000 |
| Mars | 500 000 | 270 000 | 230 000 |
| Avril | 500 000 | 330 000 | 170 000 |
| Mai | 590 000 | 410 000 | 180 000 |

  La ligne « Total année à date » de l'écran affiche donc 590 000 / 410 000 / 180 000 ;
- pour chaque mois, `ca`, `depenses` et `resultat` sont **identiques** à `revenus_reel`, `depenses_reel` et `resultat_reel` de `ecarts_mensuels(2026, '2026-05-20')` (preuve de la réutilisation du 4.6) ;
- mois en cours : `statut_mois = 'en_cours'` pour mai, `clos` pour janvier à avril ;
- `comparaison_mensuelle(2027, '2026-05-20')` renvoie zéro ligne ; `comparaison_mensuelle(2025, '2026-05-20')` renvoie 12 lignes, toutes `clos`.

Cas de l'accueil : avec cette date de référence, le bandeau compare avril (dernier mois clos) à mars : CA encaissé −300 000 FCFA (−100,0 %), Dépenses −60 000 FCFA (−50,0 %), Résultat net −240 000 FCFA. Mai n'est pas utilisé.

**Cas du bandeau** (fonction `comparaison_accueil`). Chaque scénario ci-dessous utilise une **entreprise dédiée** dans `BEGIN … ROLLBACK`.

*Cohérence avec le tableau annuel (scénario des cinq mois, mois de mars à décembre).* `comparaison_accueil('2026-05-20')` renvoie le dernier mois clos **avril 2026** comparé à mars : **identique** à la ligne d'avril du tableau annuel (CA −300 000 / −100,00 %, dépenses −60 000 / −50,00 %, résultat −240 000). Preuve que les deux fonctions appliquent la même règle.

*Scénario 1 : date de référence en janvier (`2027-01-15`).* Transactions :

| Mois | Transactions |
|---|---|
| Octobre 2026 | aucune |
| Novembre 2026 | entrée de 400 000 ; sortie de 150 000 |
| Décembre 2026 | entrée de 500 000 ; sortie de 120 000 |
| Janvier 2027 (en cours) | entrée de 10 000 |

Le bandeau compare décembre 2026 (dernier mois clos) à novembre 2026. Attendus :

| Mois | CA encaissé | Dépenses | Résultat | Var. CA | Var. CA % | Var. dép. | Var. dép. % | Var. résultat |
|---|---|---|---|---|---|---|---|---|
| Décembre 2026 (bandeau) | 500 000 | 120 000 | 380 000 | +100 000 | +25,00 | −30 000 | −20,00 | +130 000 |

Affichage : CA encaissé 500 000 FCFA, « +100 000 FCFA (+25,0 %) vs mois précédent », ▲ hausse favorable ; Dépenses 120 000 FCFA, « −30 000 FCFA (−20,0 %) vs mois précédent », ▼ baisse favorable ; Résultat net 380 000 FCFA, « +130 000 FCFA vs mois précédent », ▲ hausse favorable. L'entrée de 10 000 de janvier 2027 n'intervient pas (mois en cours). Ce résultat est identique à la ligne de décembre de `comparaison_mensuelle(2026, '2027-01-15')` (12 lignes, toutes `clos`), dont la ligne de novembre a des variations `null` (octobre vide).

*Scénario 2 : date de référence en février (`2027-02-10`), deux années concernées.* Transactions :

| Mois | Transactions |
|---|---|
| Décembre 2026 | entrée de 300 000 ; sortie de 200 000 |
| Janvier 2027 | entrée de 450 000 ; sortie de 180 000 |
| Février 2027 (en cours) | entrée de 5 000 |

Le bandeau compare **janvier 2027** (dernier mois clos) à **décembre 2026** (année précédente). Attendus :

| Mois | CA encaissé | Dépenses | Résultat | Var. CA | Var. CA % | Var. dép. | Var. dép. % | Var. résultat |
|---|---|---|---|---|---|---|---|---|
| Janvier 2027 (bandeau) | 450 000 | 180 000 | 270 000 | +150 000 | +50,00 | −20 000 | −10,00 | +170 000 |

Précédent (décembre 2026) : 300 000 / 200 000 / 100 000, `a_activite_precedent = true`. Affichage : ▲ CA +50,0 % (+150 000 FCFA), ▼ Dépenses −10,0 % (−20 000 FCFA), ▲ Résultat +170 000 FCFA, tous favorables. L'entrée de 5 000 de février n'intervient pas.

Contraste voulu avec le tableau annuel, qui ne change pas (décision 5) : `comparaison_mensuelle(2027, '2027-02-10')` renvoie deux lignes. **Janvier 2027** : 450 000 / 180 000 / 270 000, **toutes variations `null`** (pas de comparaison avec décembre dans le tableau annuel). **Février 2027** (en cours, « à date ») : 5 000 / 0 / 5 000, variations −445 000 (−98,89 %), −180 000 (−100,00 %), −265 000.

*Scénario 3 : « décembre vide » (`2027-02-10`).* Transactions : janvier 2027 seulement, entrée de 450 000 et sortie de 180 000 ; rien en décembre 2026. Attendus du bandeau : janvier 2027 = 450 000 / 180 000 / 270 000, `a_activite = true`, `a_activite_precedent = false`, **toutes les variations `null`** : le bandeau affiche les valeurs sans flèche et la mention « Pas de comparaison » (règle 2 symétrique, y compris à cheval sur deux années).

### 6. Tests adversariaux (obligatoires, en utilisateur authentifié réel, jamais en `service_role`)

Les cinq premiers tests s'appliquent **à chacune des deux fonctions** de lecture, `comparaison_mensuelle` et `comparaison_accueil` (la fonction auxiliaire `variation_mensuelle` ne lit aucune donnée : seuls ses droits d'exécution sont vérifiés, au test 5).

1. Le **comptable** de l'entreprise les appelle : **zéro ligne**, alors que ses transactions lui sont lisibles. C'est la preuve que la restriction au CEO vient des fonctions elles-mêmes.
2. Le compte de **supervision Be Smart** : zéro ligne.
3. Le CEO de l'**entreprise B** (avec ses propres transactions) les appelle pour la même période : il ne voit que ses chiffres, rien de A (y compris dans le bandeau). Le CEO de A ne voit rien de B.
4. **`anon`** : appel refusé (`permission denied`), pour les deux fonctions.
5. ACL réelles des **trois** fonctions (`comparaison_mensuelle`, `comparaison_accueil`, `variation_mensuelle`) : aucun droit pour `public` ni `anon`, droit d'exécution pour `authenticated` ; assertion verrouillée dans le script, et audit d'isolation vert.
6. Le CEO d'une entreprise **sans aucune transaction** obtient, pour `comparaison_mensuelle`, les mois jusqu'au mois de référence, tous à 0, `a_activite = false` partout, **toutes les variations `null`, dès janvier** (règles 1 et 2 : aucun mois n'est comparable à un autre) ; pour `comparaison_accueil`, une ligne à 0 avec toutes les variations `null`. Aucune division par zéro.

## Hors de ce module

- Détail par catégorie de dépense : Module 4.10 (répartition des dépenses).
- Comparaison année sur année (CDC 4.14).
- Synthèses mensuelle, trimestrielle et annuelle : Module 4.8.
- Cashflow prévisionnel et comparaison avec le prévu : Modules 4.9 et 4.6.
- Tableau de bord KPI complet : Module 4.11 (le bandeau de ce module y sera repris).
- Export PDF ou CSV du tableau : Module 4.13.
- Notifications en cas de baisse : Module 4.12 ; ici, les indicateurs sont uniquement visuels.

## Livrable attendu pour revue

PR depuis `feat/module-4.7-comparaison-mensuelle` vers `main`, avec :
- le SQL complet de la migration en clair dans la description (les trois fonctions, GRANT, éventuel index) ;
- le résultat réel du jeu de test, ligne par ligne, comparé aux attendus ci-dessus ;
- la preuve des six tests adversariaux, pour les deux fonctions de lecture ;
- les captures de l'écran `/comparaison` et du bandeau, en version bureau et mobile ;
- CI verte.

## Décisions (Ouezz, 2026-10-13)

1. **Flèches** : la flèche suit le sens de la variation (▲ hausse, ▼ baisse, « = » stable), la couleur suit le caractère favorable (une hausse des dépenses est défavorable), toujours avec signe et libellé.
2. **Libellés** : « CA encaissé » et « Résultat net », avec une ligne d'explication sous le titre de l'écran (base trésorerie, une facture compte au mois de son paiement).
3. **Accueil** : bandeau provisoire en haut de `/ecarts`, repris ensuite par le tableau de bord 4.11. Il compare toujours le dernier mois clos au mois calendaire précédent, même dans l'année précédente (en février : janvier contre décembre) ; voir la décision 8.
4. **Graphique** : option A, SVG écrit à la main en composant serveur, sans dépendance. Recharts écarté.
5. **Janvier** : aucune variation, **uniquement sur le tableau annuel de `/comparaison`** (pas de comparaison avec décembre de l'année précédente dans ce tableau). Cette décision ne concerne pas le bandeau d'accueil (décision 8).
6. **Mois vide** : pas de comparaison, des deux côtés (règle 2).
7. **Ligne « Total année à date »** : ajoutée sous le tableau, vérifiée par le test (590 000 / 410 000 / 180 000).
8. **Bandeau d'accueil à cheval sur deux années** : il compare toujours le dernier mois clos au mois calendaire précédent, y compris dans l'année précédente (en février, janvier N contre décembre N−1). Les règles de mois vide s'appliquent des deux côtés. Réalisé par la fonction `comparaison_accueil` et la fonction pure `variation_mensuelle` (§1 bis).

## Décisions ouvertes pour Ouezz

Aucune.
