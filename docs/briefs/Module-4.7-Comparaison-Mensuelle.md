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

## Définitions (décisions proposées, à valider)

Le mois d'une transaction est celui de `transactions.date`.

- **CA réel** = somme des `transactions.montant` avec `type = 'entree'`.
- **Dépenses réelles** = somme des `transactions.montant` avec `type = 'sortie'` (fixes et variables confondues).
- **Résultat net** = CA réel − Dépenses réelles.

**Ces trois définitions sont déjà celles du Module 4.6** (`revenus_reel`, `depenses_reel`, `resultat_reel` de `ecarts_mensuels`). Elles ne sont pas réécrites : voir « Réutilisation du 4.6 » ci-dessous.

**Pas de double comptage d'une créance payée.** Vérification faite sur le brief du 4.5 : une créance n'est jamais une transaction (table `creances` distincte, ni statut ni montant encaissé stockés). Quand le client paie, la comptable insère **une** transaction d'entrée liée (`creance_id`) : c'est la seule ligne qui compte dans le CA, au mois de la date du paiement. La fonction de ce module ne lit donc jamais la table `creances`. Conséquence assumée : le CA est un **CA encaissé** (base trésorerie), pas un CA facturé. Une facture émise en février et payée en mars apparaît en mars. C'est la même règle que le 4.6, et le « résultat net » est donc un résultat de trésorerie, pas un résultat comptable (SYSCOHADA hors V1). Voir la décision ouverte n° 2 sur le libellé.

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
- pour le résultat net : `resultat_variation` (en FCFA) **uniquement**, aucun pourcentage.

Règles de variation (toutes les variations sont `null` quand la comparaison n'a pas de sens, jamais 0 par défaut) :
1. **Janvier** : pas de mois précédent dans l'année demandée, donc toutes les variations sont `null`. Pas de comparaison avec décembre de l'année précédente en V1 (décision ouverte n° 5).
2. **Mois précédent sans aucune transaction** (`a_activite = false`) : toutes les variations du mois courant sont `null`. Un mois vide signifie le plus souvent « pas encore saisi » : comparer avec lui produirait un pourcentage trompeur.
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

### 2. Écran dédié `/comparaison` (CEO)

- Sélecteur d'année (année en cours par défaut). Année future non proposée.
- **Graphique** d'évolution mensuelle : CA, dépenses et résultat net, un point par mois affiché. Le graphique s'arrête au mois en cours (pas de mois futurs). Alternative textuelle : le tableau est lisible sans le graphique, et le graphique porte un titre et un résumé accessible.
- **Tableau récapitulatif mois par mois** sur l'année : pour chaque mois, CA, Dépenses, Résultat net, et les variations (% et FCFA pour le CA et les dépenses, FCFA pour le résultat). Le mois en cours porte la mention « à date ». Une variation `null` s'affiche « — ». Quand le pourcentage est `null` mais la variation en FCFA existe (règle 3), l'écran affiche la valeur en FCFA seule.
- Tableau utilisable sur mobile : défilement horizontal dans son conteneur, jamais sur la page.
- Contrôle du rôle CEO côté serveur (404 pour les autres rôles, comme `/ecarts`). Lien « Comparaison » ajouté à la navigation du CEO uniquement.

### 3. Indicateur à flèches sur l'accueil du CEO (solution provisoire)

Le tableau de bord KPI (Module 4.11) n'existe pas encore, et l'accueil du CEO est `/ecarts` depuis la PR #12.

**Proposition provisoire** : un bandeau de trois indicateurs (CA, Dépenses, Résultat net) en haut de `/ecarts`, calculé sur le **dernier mois clos** par rapport au mois qui le précède. Le mois en cours n'est jamais comparé sur l'accueil : un CA à date n'est pas comparable à un mois complet (même logique que l'absence d'alerte d'écart sur un mois non clos au 4.6). Chaque indicateur affiche : la valeur du dernier mois clos, la variation (« CA +12,0 % vs mois précédent », « Résultat net −8 000 FCFA vs mois précédent ») et une flèche.

Ce bandeau sera repris tel quel par le tableau de bord du 4.11. L'autre option est de ne rien afficher sur l'accueil avant le 4.11 : décision ouverte n° 3.

Si le dernier mois clos n'a pas de variation (règles 1 et 2), le bandeau affiche la valeur sans flèche et la mention « Pas de comparaison ».

### 4. Sens des flèches (décision ouverte n° 1, proposition)

Le CDC dit « flèche verte hausse / rouge baisse ». Pris à la lettre, une hausse des **dépenses** serait verte, alors qu'elle est défavorable. Proposition :
- **la flèche suit le sens de la variation** : ▲ hausse, ▼ baisse, « = » stable (variation nulle) ;
- **la couleur suit le caractère favorable** : hausse du CA ou du résultat = favorable (vert), baisse = défavorable (rouge) ; hausse des dépenses = défavorable (rouge), baisse = favorable (vert) ; stable = neutre.

Le signal ne repose **jamais sur la couleur seule** : signe + ou − explicite sur la valeur, flèche, et un libellé accessible (« hausse favorable », « baisse défavorable »). Couleurs : jetons `--color-positif` et `--color-negatif` de `docs/06-design-principes-et-tokens.md` (proposition, PR #15 en revue) une fois les tokens implémentés ; d'ici là, des vert et rouge sobres avec un contraste d'au moins 4.5:1 sur le fond.

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
| Février | 0 | 0 | 0 | −200 000 | −100,00 | −150 000 | −100,00 | −50 000 |
| Mars | 300 000 | 120 000 | 180 000 | `null` | `null` | `null` | `null` | `null` |
| Avril | 0 | 60 000 | −60 000 | −300 000 | −100,00 | −60 000 | −50,00 | −240 000 |
| Mai (à date) | 90 000 | 80 000 | 10 000 | +90 000 | `null` | +20 000 | +33,33 | +70 000 |

Ce que chaque ligne prouve :
- **Janvier** : pas de mois précédent, variations `null` (règle 1).
- **Février** : un mois à 0 sans activité (`a_activite = false`) est bien présent dans le résultat, avec CA = dépenses = résultat = 0, et sa variation par rapport à janvier est calculée normalement (−100 %).
- **Mars** : le mois précédent n'a aucune transaction, donc toutes les variations sont `null` (règle 2). Le CA vaut 300 000 : 200 000 de vente + **un seul** paiement de créance de 100 000. Le CA de février vaut 0 alors que la créance existe déjà : la créance n'est pas comptée à sa facturation, et le paiement n'est pas compté deux fois (une seule ligne `transactions`, la créance n'en ajoute aucune).
- **Avril** : CA qui tombe à 0 (−100,00 %), dépenses divisées par deux (−50,00 %), résultat qui **change de signe** (180 000 → −60 000, soit −240 000 FCFA, sans pourcentage).
- **Mai** : le mois précédent a un CA de 0 mais avec activité (dépenses de 60 000) : variation de CA +90 000 FCFA, **pourcentage `null`** (règle 3). Variation des dépenses +33,33 % (20 000 / 60 000 = 0,33333… arrondi à 2 décimales) : cas d'arrondi. Résultat de −60 000 à +10 000 : +70 000 FCFA.

Contrôles de cohérence, tous en `numeric` exact :
- somme des CA des cinq mois = 590 000 ; somme des dépenses = 410 000 ; somme des résultats = 180 000 = 590 000 − 410 000 ;
- pour chaque mois, `ca`, `depenses` et `resultat` sont **identiques** à `revenus_reel`, `depenses_reel` et `resultat_reel` de `ecarts_mensuels(2026, '2026-05-20')` (preuve de la réutilisation du 4.6) ;
- mois en cours : `statut_mois = 'en_cours'` pour mai, `clos` pour janvier à avril ;
- `comparaison_mensuelle(2027, '2026-05-20')` renvoie zéro ligne ; `comparaison_mensuelle(2025, '2026-05-20')` renvoie 12 lignes, toutes `clos`.

Cas de l'accueil : avec cette date de référence, le bandeau compare avril (dernier mois clos) à mars : CA −300 000 FCFA (−100,0 %), Dépenses −60 000 FCFA (−50,0 %), Résultat net −240 000 FCFA. Mai n'est pas utilisé.

### 6. Tests adversariaux (obligatoires, en utilisateur authentifié réel, jamais en `service_role`)

1. Le **comptable** de l'entreprise appelle `comparaison_mensuelle` : **zéro ligne**, alors que ses transactions lui sont lisibles. C'est la preuve que la restriction au CEO vient de la fonction.
2. Le compte de **supervision Be Smart** : zéro ligne.
3. Le CEO de l'**entreprise B** (avec ses propres transactions) appelle la fonction pour la même année : il ne voit que ses chiffres, rien de A. Le CEO de A ne voit rien de B.
4. **`anon`** : appel refusé (`permission denied`).
5. ACL réelles de la fonction : aucun droit pour `public` ni `anon`, droit d'exécution pour `authenticated` ; assertion verrouillée dans le script, et audit d'isolation vert.
6. Le CEO d'une entreprise **sans aucune transaction** obtient les mois jusqu'au mois de référence, tous à 0, toutes variations `null` (règle 2 appliquée dès février). Aucune division par zéro.

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
- le SQL complet de la migration en clair dans la description (fonction, GRANT, éventuel index) ;
- le résultat réel du jeu de test, ligne par ligne, comparé aux attendus ci-dessus ;
- la preuve des six tests adversariaux ;
- les captures de l'écran `/comparaison` et du bandeau, en version bureau et mobile ;
- CI verte.

## Décisions ouvertes pour Ouezz

1. **Sens et couleur des flèches.** Le CDC dit « flèche verte hausse / rouge baisse ». Proposition du brief : la flèche suit le sens de la variation, la couleur suit le caractère favorable (une hausse des dépenses est rouge), le tout doublé d'un signe et d'un libellé. Alternative : suivre le CDC à la lettre (vert pour toute hausse), au risque de colorer en vert une hausse de dépenses. À trancher.
2. **Libellé du CA et du résultat.** Le CA est un CA **encaissé** (base trésorerie, comme au 4.6), pas un CA facturé : une facture émise en février et payée en mars compte en mars. Garder les libellés du CDC (« CA réel », « Résultat net ») avec une note explicative sur l'écran, ou les renommer (« Encaissements », « Résultat de trésorerie ») ? Le calcul ne change pas.
3. **Indicateur sur l'accueil avant le 4.11.** Bandeau provisoire de trois indicateurs en haut de `/ecarts` (proposition du brief, repris ensuite par le 4.11), ou rien sur l'accueil avant le tableau de bord ?
4. **Bibliothèque de graphique** (deux options).
   - **A. Graphique SVG écrit à la main, composant serveur.** Aucune dépendance, aucun JavaScript envoyé pour le graphique, rendu identique côté serveur (imprimable, accessible avec un `<title>` et un tableau de repli). Coût : environ une centaine de lignes à écrire et à tester ; pas d'infobulle au survol en V1 (le tableau donne les valeurs exactes).
   - **B. Recharts** (MIT, version 3.10.1 au moment de la rédaction). Rendu SVG, composant client (donc JavaScript envoyé au navigateur et hydratation), infobulles et légendes prêtes à l'emploi. Poids indicatif : 11 dépendances directes et 7,5 Mo une fois installé sur disque (taille de développement, **pas** le poids envoyé au navigateur, qui n'a pas été mesuré : à mesurer au build avant de décider).
   - Recommandation : **A** pour la V1 (graphique à trois courbes sur douze points, usage sur mobile, aucune dépendance ajoutée), B seulement si l'interactivité devient un besoin réel.
5. **Janvier et décembre de l'année précédente.** Proposition : janvier n'a pas de variation (le CDC parle de « l'année en cours »). Alternative : comparer janvier à décembre de l'année précédente (ce n'est pas la comparaison année sur année du CDC 4.14, mais une variation de mois à mois), au prix d'un mois de calcul en plus et d'une lecture hors de l'année affichée.
6. **Mois vide comme précédent.** Proposition : si le mois précédent n'a aucune transaction, on ne compare pas (variations `null`), car un mois vide veut surtout dire « pas encore saisi ». Alternative : le traiter comme un vrai mois à 0 et afficher des variations de +∞ ou en FCFA seulement.
7. **Ligne de total sur l'écran.** Ajouter une ligne « Total année à date » (CA, dépenses, résultat) sous le tableau ? Elle n'est pas dans le CDC ; elle est calculée par somme des mois affichés et vérifiée par le test (590 000 / 410 000 / 180 000).
