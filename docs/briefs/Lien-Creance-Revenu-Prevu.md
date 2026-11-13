# Brief Claude Code — Prérequis du Module 4.9 : lien créance ↔ revenu prévu

*Depuis `main` (Modules 4.1 à 4.8 mergés). Branche : `feat/lien-creance-revenu-prevu`. Une migration (une colonne, un index, un trigger, une vue), un champ de formulaire et deux affichages en lecture seule. Le Module 4.9 (`docs/briefs/Module-4.9-Cashflow-Previsionnel.md`, décision D4) attend ce prérequis : il ne s'implémente qu'une fois ce brief validé par Ouezz et sa PR mergée.*

## Pourquoi

Le cashflow prévisionnel (4.9) additionne deux sources d'encaissements futurs : le CA prévisionnel du budget (4.3) et les créances clients non payées (4.5). Quand le CEO budgète une vente qui devient ensuite une facture, la même somme figure dans les deux sources. Elle est alors **comptée deux fois**. Ouezz a retenu le 2026-11-12 un lien explicite entre les deux (D4) : c'est la seule règle exacte, et elle garde le simulateur honnête.

Ce brief décrit ce lien. Il ne change aucun calcul existant : ni le Budget (4.3), ni le Journal (4.4), ni les créances (4.5), ni les écarts (4.6) ne bougent.

## Ce qui change

### Sens et cardinalité du lien (tranché)

**Le lien est porté par la créance** : `creances.ligne_revenu_prevu_id`, facultatif. **Une créance vise au plus une ligne ; une ligne peut être visée par plusieurs créances.**

Pourquoi la colonne est sur la créance :
- **C'est le comptable qui crée le lien**, au moment où il saisit la facture. Il écrit déjà dans `creances` et lit déjà les budgets. Une colonne sur `lignes_revenu_prevu` (table que seul le CEO écrit) obligerait à ouvrir au comptable une écriture sur le budget, donc une nouvelle policy. Ce brief n'en ajoute aucune.
- Le Journal fait déjà ainsi : `transactions.ligne_revenu_prevu_id` (4.4). Même nom de colonne, même sens (« ce fait réel se rattache à cette ligne prévue »), même garde-fou.

Pourquoi une ligne accepte plusieurs créances :
- **Un budget se saisit par ligne globale** (« Ventes — avril : 250 000 », comme dans l'onglet Excel d'origine), pas facture par facture. Avec un lien unique, la deuxième facture d'avril ne pourrait plus être rattachée à « Ventes ». Elle resterait non liée, et serait donc comptée deux fois : exactement ce que D4 veut éviter.
- Le cas « une ligne = un client » (« Client Alpha : 200 000 ») est un cas particulier de la même règle, avec une seule créance.
- Une créance rattachée à plusieurs lignes demanderait de répartir son montant entre elles. Ce n'est pas demandé, et ce serait source d'erreurs. Une créance vise donc une seule ligne.

### Règle de consommation (règle unique, utilisée par le 4.9)

Pour chaque ligne de CA prévisionnel **non annulée** :

- **montant facturé** = somme des `montant_du` des créances liées à la ligne ;
- **reste à facturer** = `max(montant_estime − montant facturé, 0)`, calculé **ligne par ligne**.

Le 4.9 projette le **reste à facturer** des lignes, au mois de leur budget. Il projette aussi le **reste dû** de chaque créance attendue, qu'elle soit liée ou non, à sa date d'encaissement attendue. Ainsi, une facture **déplace** sa part du budget vers la créance, avec la vraie échéance et les paiements déjà reçus. L'argent attendu n'est jamais compté deux fois. Il n'est jamais perdu non plus.

- Le montant facturé utilise le **montant dû** (ce qui a été facturé), jamais le reste dû. Un paiement ne change donc pas le reste à facturer : la part payée est dans le réel, la part restante dans la créance, et le total est conservé.
- Le plafond à 0 s'applique **par ligne**, pas par mois. Une facture plus élevée que sa ligne (dépassement) n'efface pas les autres lignes du même mois.
- Quand la facture couvre exactement la ligne, la règle revient à « la ligne liée est remplacée par la créance » (la formulation initiale de D4). Les attendus actuels du 4.9 n'en sont pas changés (voir la décision produit P2).

### Migration

```sql
alter table public.creances
  add column ligne_revenu_prevu_id uuid
    references public.lignes_revenu_prevu (id) on delete set null;

comment on column public.creances.ligne_revenu_prevu_id is
  'Ligne de CA prévisionnel que cette facture réalise (facultatif). Plusieurs créances peuvent viser la même ligne. Règle de consommation : v_lignes_revenu_facturation.';

create index creances_ligne_revenu_prevu_id_idx
  on public.creances (ligne_revenu_prevu_id)
  where ligne_revenu_prevu_id is not null;
```

Le **trigger** `verifier_lien_creance_revenu_prevu`, `BEFORE INSERT OR UPDATE` sur `creances` (fonction dédiée, à côté des deux triggers du 4.5) :

- lien vide : rien à vérifier ;
- `UPDATE` qui ne **change** pas le lien (`is not distinct from old`) : rien à vérifier. C'est indispensable : une créance liée à une ligne annulée **après coup** doit rester modifiable (notes, échéance…) ;
- sinon, la ligne est lue dans `lignes_revenu_prevu`. Elle est refusée si elle est introuvable **ou** d'une autre entreprise (`v_entreprise is null or v_entreprise <> new.entreprise_id`), avec **un seul message** dans les deux cas. Le message ne révèle donc pas qu'un identifiant existe ailleurs. Le test est le même que celui des gardes-fous du 4.3 et du 4.4, et il ne s'appuie pas sur la RLS : il tient aussi pour un appelant qui la contourne (`postgres`, `service_role`) ;
- la ligne est refusée si elle est `annule` (message explicite) ;
- la fonction naît **sans droit d'exécution** : `revoke all … from public, anon, authenticated, service_role`. C'est une fonction de trigger, comme `verifier_date_solde_initial` (PR #20).

La **vue** `v_lignes_revenu_facturation` porte la règle de consommation (`security_invoker = true`, comme `v_budget_mensuel_totaux`). Elle donne une ligne par ligne de CA prévisionnel non annulée :

| Colonne | Contenu |
|---|---|
| `ligne_revenu_prevu_id`, `entreprise_id`, `budget_mensuel_id`, `annee`, `mois`, `source`, `statut` | identité de la ligne et mois de son budget |
| `montant_estime` | `numeric` |
| `nb_creances` | nombre de créances liées |
| `montant_facture` | somme des `montant_du` liés (`numeric`, 0 sans créance) |
| `reste_a_facturer` | `greatest(montant_estime − montant_facture, 0)` (`numeric`) |

Droits : `revoke all … from anon`, `grant select … to authenticated`. Les lignes visibles sont celles de la RLS de l'appelant : CEO et comptable voient leur entreprise ; la supervision et `anon` ne voient rien. `v_budget_mensuel_totaux` **n'est pas modifiée** : le CA prévisionnel du Budget et du 4.6 reste le même.

### Ce qui ne change pas (vérifié)

- **Aucune policy nouvelle.**
  - Le comptable modifie déjà toute la ligne de créance. La policy `comptable_modification_creances` couvre la nouvelle colonne, et aucun droit n'est accordé colonne par colonne sur `creances`.
  - Le comptable lit déjà `lignes_revenu_prevu` et `budgets_mensuels` (policies `isolation_entreprise_lecture_*`). Le formulaire de transaction s'en sert déjà pour le rapprochement.
  - Le CEO n'a toujours **aucune** écriture sur `creances`. Il ne peut donc ni créer ni retirer un lien. Il peut en revanche supprimer ou annuler ses propres lignes (voir « Cas à couvrir »).
- **`on delete set null`** marche quand c'est le CEO qui supprime la ligne, alors qu'il ne peut pas modifier les créances. Les actions de clé étrangère de PostgreSQL s'exécutent en effet sous le propriétaire de la table et ignorent la RLS. La modification passe aussi les triggers existants : `avant_modification_creance` vérifie l'entreprise, `saisi_par` et que le montant dû reste au moins égal à l'encaissé, et rien de cela ne change. Un prototype local, dans une transaction annulée, l'a confirmé le 2026-11-12, y compris sur une créance déjà soldée. Le test SQL doit le prouver de nouveau (test 9).
- `creances_situation` et `creances_balance_agee` (4.5) **ne sont pas redéfinies**. Pour l'affichage, les écrans lisent le lien directement dans `creances`, par une jointure PostgREST, sans aucun calcul.

## Écrans

### Formulaire de créance du comptable (`components/gestion-creances.tsx`)

- Nouveau champ facultatif, **« Ligne du budget (facultatif) »**. C'est une liste déroulante, avec « Aucune » par défaut.
  - Options : les lignes de CA prévisionnel **non annulées** de l'entreprise (statut `en_attente` ou `ok`), lues dans `v_lignes_revenu_facturation`.
  - Libellé de chaque option : « Avril 2026 — Ventes — reste à facturer 90 000 FCFA ».
  - Tri : par mois puis par source. Seuls les mois à partir de celui de la date de facturation moins un mois sont proposés. Ce filtre est une aide à la saisie, pas une règle de sécurité.
  - En modification, la ligne déjà liée est toujours proposée, même si elle est hors de ce filtre ou annulée. Dans ce cas, elle est marquée « (annulée) ».
- **Avertissement non bloquant** quand le montant dû dépasse le reste à facturer de la ligne choisie : « Cette facture dépasse de X FCFA le reste à facturer de la ligne : le surplus n'est pas retiré d'une autre ligne. » La différence est un simple affichage : le reste à facturer vient de la vue.
- Le formulaire envoie `ligne_revenu_prevu_id` (ou `null`), et rien d'autre. Toutes les règles sont en base : l'écran n'en applique aucune.

### Liste des créances (CEO et comptable)

- Colonne en lecture seule **« Ligne du budget »** : « Ventes — avril 2026 », « — » sans lien, et « Ventes — avril 2026 (annulée) » quand le lien est inerte.

### Budget (CEO, `components/gestion-lignes-revenu.tsx`)

- Sur chaque ligne de CA, deux colonnes en lecture seule lues dans la vue : **« Facturé »** (montant facturé, avec le nombre de créances) et **« Reste à facturer »**. Le CEO voit ainsi pourquoi le cashflow ne projette plus toute la ligne. Aucune action de lien n'est ajoutée côté CEO.

## Cas à couvrir

- **Créance sans lien** : comportement inchangé. Elle ne consomme aucune ligne. Le 4.9 l'ajoute au budget, et l'écran du 4.9 signale « N créances ne sont rattachées à aucune ligne du budget ».
- **Lien vers une ligne annulée** :
  - *Au moment du lien* (création ou changement) : refusé par le trigger.
  - *La ligne est annulée après coup* par le CEO : c'est autorisé. Le lien est conservé mais **inerte** : la ligne sort de la vue (comme du budget), et la créance compte seule. Elle reste modifiable. La liste affiche « (annulée) ». Si le CEO remet la ligne en `en_attente`, le lien redevient actif, car rien n'est stocké (test 8).
- **Ligne liée modifiée** par le CEO (montant, source, statut `ok` ↔ `en_attente`) : le reste à facturer se recalcule à la lecture, et rien n'est stocké. Le plafond à 0 évite tout reste négatif (test 6). La ligne ne peut pas changer d'entreprise : son trigger du 4.3 l'en empêche. Elle peut changer de budget dans la même entreprise ; le lien la suit alors.
- **Ligne liée supprimée** par le CEO : la suppression est autorisée. Le lien de chaque créance devient vide (`on delete set null`), y compris pour une créance payée. Les créances restent intactes, et elles comptent ensuite comme non liées (tests 9 et 10).
- **Créance payée** (partiellement ou soldée) : le lien est conservé et la consommation reste la même, car elle repose sur le montant dû (tests 1 et 2).
  - Le comptable peut encore **changer ou retirer** le lien d'une créance payée. C'est un classement : aucun argent ne bouge.
  - La règle « montant dû ≥ encaissé » du 4.5 continue de s'appliquer à toute modification du montant.
- **Créance supprimée** (possible seulement sans paiement, règle du 4.5) : sa consommation disparaît avec elle (test 11).
- **Créance liée à une ligne d'un autre mois que son échéance** : c'est autorisé. La ligne est consommée dans le mois de son budget, et la créance encaissée à sa date attendue. Le 4.9 conserve ainsi le total et place l'argent au bon mois (scénario 7 du 4.9, créance K2).
- **Rapprochement du Journal** (`transactions.ligne_revenu_prevu_id`, qui passe la ligne à `ok`) : il est indépendant de ce lien et n'est pas modifié. Une ligne `ok` peut encore recevoir des créances.

## Jeu de test chiffré (obligatoire, recalculé par script)

Test SQL `supabase/tests/lien_creance_revenu_prevu.sql`, avec son étape CI dédiée. Il utilise une **entreprise dédiée** `Lien1` et une seconde entreprise `Lien2` pour l'isolation, des utilisateurs authentifiés réels et des attendus jsonb écrits en dur.
- **Chaque test numéroté part de l'état initial** : `savepoint` puis `rollback to savepoint`.
- **Les attendus ci-dessous ont été recalculés par un modèle de référence indépendant du SQL** : un script Python écrit à partir des seules règles de ce brief.
- Toute divergence est à analyser avant de toucher aux attendus.

### État initial (`Lien1`)

Budgets d'avril et de mai 2026. Créances saisies par le comptable de `Lien1`. C5 est liée à L4 pendant que L4 est `en_attente`, puis le CEO annule L4. C6 est soldée par une transaction de 120 000, et C7 a reçu 10 000.

| Ligne | Mois | Source | Montant | Statut | Créances liées (montant dû) |
|---|---|---|---|---|---|
| L1 | avril | Ventes | 250 000 | en_attente | C1 100 000 ; C2 60 000 |
| L2 | avril | Client Alpha | 200 000 | en_attente | C3 200 000 |
| L3 | avril | Contrat Beta | 300 000 | **ok** | C4 350 000 (dépassement) |
| L4 | avril | Vente annulée | 80 000 | **annule** | C5 50 000 (lien inerte) |
| L5 | avril | Divers | 40 000 | en_attente | — |
| L6 | mai | Ventes | 120 000 | en_attente | C6 120 000 (**soldée**) |
| L7 | mai | Prestations | 75 000 | en_attente | C7 30 000 (10 000 payés) |
| — | | | | | C8 40 000, **sans lien** |

### Test 1 — état initial (lignes de `v_lignes_revenu_facturation`)

| Ligne | Nb créances | Facturé | Reste à facturer |
|---|---|---|---|
| L1 | 2 | 160 000 | 90 000 |
| L2 | 1 | 200 000 | 0 |
| L3 | 1 | 350 000 | **0** (jamais −50 000) |
| L5 | 0 | 0 | 40 000 |
| L6 | 1 | 120 000 | 0 |
| L7 | 1 | 30 000 | 45 000 |

L4 est **absente**, car elle est annulée. La vue a 6 lignes.

Recoupements :
- Avril : CA prévisionnel de `v_budget_mensuel_totaux` = **790 000** (inchangé par ce prérequis). Somme des restes à facturer = **130 000**. Un plafond par mois aurait donné 790 000 − 710 000 = 80 000 : c'est faux, car le dépassement de L3 effacerait 50 000 de L1 et L5.
- Mai : CA prévisionnel **195 000**, reste à facturer **45 000**.

### Tests 2 à 12 (chacun depuis l'état initial)

| # | Action (par qui) | Attendu |
|---|---|---|
| 2 | C7 soldée : paiement de 20 000 (comptable) | Vue **identique** au test 1 (L7 : facturé 30 000, reste 45 000). Le paiement ne consomme rien. |
| 3 | C1 : montant dû 100 000 → 120 000 (comptable) | L1 : facturé 180 000, reste 70 000. Avril : 110 000. |
| 4 | C2 déplacée de L1 vers L5 (comptable) | L1 : 1 créance, 100 000, reste 150 000. L5 : 1 créance, 60 000, reste **0**. Avril : 150 000. |
| 5 | Lien de C1 retiré, mis à `null` (comptable) | L1 : 1 créance, 60 000, reste 190 000. Avril : 230 000. C1 existe toujours. |
| 6 | L1 : montant 250 000 → 150 000 (CEO) | L1 : facturé 160 000, reste **0** (jamais −10 000). Avril : CA prévu 690 000, reste à facturer 40 000. |
| 7 | L1 annulée (CEO) | L1 sort de la vue. C1 et C2 gardent leur lien. Avril : CA prévu 540 000, reste à facturer 40 000. Le comptable modifie ensuite les notes de C1 : **accepté**. Il lie ensuite C8 à L1 : **refusé** (ligne annulée). |
| 8 | L4 remise en `en_attente` (CEO) | L4 réapparaît : 1 créance, facturé 50 000, reste 30 000. Avril : CA prévu 870 000, reste à facturer 160 000. |
| 9 | L6 supprimée (CEO), alors que C6 est soldée | Suppression **acceptée**, bien que le CEO n'ait aucun droit d'écriture sur `creances`. Le lien de C6 devient `null`. C6 existe toujours, payée (`creances_situation` : reste dû 0, statut `paye`). Mai : CA prévu 75 000, reste à facturer 45 000. |
| 10 | L1 supprimée (CEO) | Les liens de C1 et C2 deviennent `null`, et les deux créances existent toujours. Avril : CA prévu 540 000, reste à facturer 40 000. |
| 11 | C1 supprimée (comptable ; aucun paiement) | L1 : 1 créance, 60 000, reste 190 000. Avril : 230 000. |
| 12 | C9 de 40 000 **créée** liée à L5 (comptable, chemin `INSERT`) | L5 : 1 créance, facturé 40 000, reste **0** exactement. Avril : 90 000. |

## Tests adversariaux (obligatoires, en utilisateur authentifié réel, jamais en `service_role` sauf A3)

1. **A1 — isolation en écriture.** Le comptable de `Lien1` lie C8 à une ligne de `Lien2`. C'est **refusé**, et le message est **identique** à celui de A2.
2. **A2 — identifiant inexistant.** Le comptable de `Lien1` lie C8 à un uuid qui n'existe pas. C'est refusé, avec le même message que A1.
3. **A3 — le trigger, pas seulement la RLS.** En `postgres`, donc sans RLS, une créance de `Lien1` est insérée avec une ligne de `Lien2`. C'est refusé par le trigger. Sans ce test, A1 passerait même sans trigger : la ligne de B y est seulement invisible (leçon du 4.8).
4. **A4 — le CEO ne lie pas.** Le CEO de `Lien1` modifie `ligne_revenu_prevu_id` d'une créance. Aucune ligne n'est modifiée (0 ligne, RLS), et la créance reste inchangée.
5. **A5 — le comptable n'écrit pas le budget.** Le comptable de `Lien1` modifie une ligne de CA. Aucune ligne n'est modifiée (règle du 4.3, non-régression).
6. **A6 — isolation en lecture de la vue.**
   - Le CEO et le comptable de `Lien2` ne voient que les lignes de `Lien2`.
   - Ceux de `Lien1` ne voient que les leurs.
   - La supervision Be Smart (claim `super_admin`) ne voit aucune ligne.
   - `anon` reçoit une permission refusée.
7. **A7 — ligne annulée.** Le comptable lie une créance à une ligne `annule`, à la création comme en modification. C'est refusé.
8. **A8 — structure.** Le test vérifie que :
   - la vue a `security_invoker = true` (`reloptions`) ;
   - la clé étrangère est en `on delete set null` (`confdeltype = 'n'`) ;
   - l'index partiel existe ;
   - le trigger est `BEFORE INSERT OR UPDATE` ;
   - la fonction de trigger n'a aucun EXECUTE pour `public`, `anon`, `authenticated` ni `service_role` ;
   - le **nombre de policies** de `creances` (4) et de `lignes_revenu_prevu` (4) est inchangé ;
   - l'audit d'isolation reste vert.

## Contrôles négatifs (à faire en local, puis consigner dans la PR)

Chaque contrôle se déroule ainsi : on modifie temporairement la migration, on constate que le test échoue, puis on la restaure.

| # | Mutation | Test qui doit échouer |
|---|---|---|
| N1 | Retirer la vérification d'entreprise du trigger | A3. A1 seul ne suffirait pas, car la RLS rend la ligne de B invisible. |
| N2 | Vérifier le lien à **chaque** `UPDATE`, même s'il ne change pas | Test 7 (modification des notes de C1 refusée) |
| N3 | Retirer le plafond `greatest(…, 0)` | Test 1 (L3 à −50 000) et test 6 (L1 à −10 000) |
| N4 | Plafonner par mois au lieu de par ligne | Test 1 (avril à 80 000 au lieu de 130 000) |
| N5 | Consommer le **reste dû** au lieu du montant dû | Test 1 (L6 : reste 120 000 au lieu de 0 ; L7 : 55 000 au lieu de 45 000) et test 2 |
| N6 | `on delete restrict` au lieu de `set null` | Test 9 (suppression de L6 refusée) |
| N7 | Ne plus exclure les lignes `annule` de la vue | Test 1 (L4 apparaît) |
| N8 | `security_invoker = false` | A6 (la vue, exécutée sous son propriétaire, montre les deux entreprises) et A8 |
| N9 | Ne plus refuser une ligne `annule` dans le trigger | A7 |

## Hors de ce module

- Le calcul du cashflow lui-même : Module 4.9, qui lit `v_lignes_revenu_facturation`.
- Répartir une créance entre plusieurs lignes.
- Lier automatiquement une créance à une ligne (par client, montant ou mois).
- Créer, retirer ou proposer un lien depuis l'écran du Budget (CEO).
- Le lien entre une charge prévue et une dette fournisseur : les dettes fournisseurs sont hors V1 (CDC 4.14).
- Modifier `v_budget_mensuel_totaux`, le Suivi des écarts (4.6) ou le rapprochement du Journal (4.4).

## Livrable attendu pour revue

Une PR depuis `feat/lien-creance-revenu-prevu` vers `main`, avec :
- le SQL complet de la migration en clair, ainsi que les ACL réelles de la vue et de la fonction de trigger ;
- les résultats réels des tests 1 à 12 comparés aux attendus ci-dessus ;
- la preuve des tests A1 à A8 et des contrôles N1 à N9, chaque essai noté ;
- la description des trois écrans, avec des captures bureau et mobile ;
- l'étape CI du test SQL ;
- une CI verte.

La migration attend l'approbation explicite d'Ouezz avant merge.

---

## Décisions produit (décidées, Ouezz, 2026-11-13)

*Toutes retenues selon ma recommandation ; les alternatives restent notées pour mémoire.*

**P1 — Sens et cardinalité.** *Décidé : lien porté par la créance ; une créance vise au plus une ligne, une ligne peut recevoir plusieurs factures.* Pourquoi : c'est le comptable qui facture, et il ne faut ouvrir aucune écriture du budget au comptable. Une ligne globale (« Ventes ») reçoit en outre plusieurs factures dans le mois. Alternative écartée : une ligne ↔ une seule créance. La deuxième facture d'une ligne globale resterait non liée, et serait donc comptée deux fois.

**P2 — Règle de consommation (précise D4).** *Décidé : la ligne est consommée par le montant facturé de ses créances, plafonnée à 0 par ligne.* Pourquoi : une facture partielle (150 000 facturés sur une ligne de 400 000) laisse 250 000 encore attendus. La règle « la ligne liée est remplacée par la créance » les ferait disparaître, ce qui rendrait le solde projeté faussement pessimiste (scénario 7 du 4.9 : 70 000 de moins dès septembre). Quand la facture couvre la ligne, les deux règles donnent le même résultat. C'est pourquoi les scénarios 1 à 6 du 4.9 ne changent pas. Alternative : le remplacement total, plus simple à expliquer mais faux dès la première facture partielle.

**P3 — Statuts acceptés au moment du lien.** *Décidé : `en_attente` et `ok`, mais jamais `annule`.* Pourquoi : `ok` signifie seulement qu'un encaissement a été rapproché au Journal. Une ligne globale passe à `ok` dès la première vente comptant, et doit encore pouvoir recevoir des factures. Une ligne annulée ne fait plus partie du budget. Alternative : `en_attente` seulement, comme le rapprochement du Journal. Mais une ligne globale serait alors bloquée trop tôt.

**P4 — Ligne annulée après coup.** *Décidé : autorisée ; le lien est conservé mais inerte, et signalé « (annulée) » dans la liste des créances.* Pourquoi : interdire l'annulation bloquerait le CEO sur des données du comptable, qu'il ne peut pas modifier. Garder le lien permet de le réactiver si l'annulation était une erreur. Alternative : vider le lien à l'annulation. La réactivation de la ligne serait alors perdue, et un trigger de plus serait nécessaire sur `lignes_revenu_prevu`.

**P5 — Ligne liée supprimée.** *Décidé : la suppression est autorisée et les liens sont vidés automatiquement (`on delete set null`).* Pourquoi : c'est la même raison que P4, et la créance est un fait réel qui ne doit pas dépendre d'une ligne de prévision. Alternative écartée : `on delete restrict`. Le CEO ne pourrait plus supprimer sa ligne sans demander au comptable de retirer chaque lien.

**P6 — Facture supérieure à sa ligne.** *Décidé : acceptée, avec un avertissement non bloquant dans le formulaire ; le surplus ne consomme aucune autre ligne.* Pourquoi : une vente plus importante que prévu est normale, et un refus pousserait à ne pas lier la facture, donc au double comptage.

**P7 — Modifier ou retirer le lien d'une créance payée.** *Décidé : autorisé.* Pourquoi : c'est un classement, et aucun argent ne bouge. La règle « montant dû ≥ encaissé » du 4.5 reste la seule contrainte sur une créance payée.

**P8 — Visibilité.** *Décidé : le lien est en lecture pour le CEO et le comptable (liste des créances) ; « Facturé » et « Reste à facturer » s'affichent dans le Budget du CEO.* Pourquoi : le CEO doit comprendre pourquoi le cashflow ne projette plus une ligne entière. Ce sont des données qu'il lit déjà, sans nouveau droit. Alternative : aucun affichage avant le 4.9, ce qui allège ce prérequis mais rend le 4.9 opaque.

## Choix techniques proposés

- **T1 — Une colonne et un trigger dédiés**, plutôt qu'une table de liaison. La cardinalité « une créance → au plus une ligne » est portée par la colonne elle-même, sans contrainte d'unicité à écrire. Une table de liaison aurait demandé sa propre RLS et son propre test A/B.
- **T2 — Une fonction de trigger dédiée** (`BEFORE INSERT OR UPDATE`), plutôt que d'étendre `avant_insertion_creance` et `avant_modification_creance`. La règle vit à un seul endroit pour les deux opérations, et le contrôle négatif N1 ne touche qu'elle.
- **T3 — La règle de consommation vit dans une vue `security_invoker`** (`v_lignes_revenu_facturation`), et non dans le 4.9. C'est le même principe que `v_budget_mensuel_totaux` : une seule règle, testée ici avec des chiffres, que le 4.9 et l'écran du Budget lisent sans la recalculer. La vue n'ajoute aucun droit : elle ne montre que ce que l'appelant lit déjà.
- **T4 — `on delete set null`**, et un index partiel sur la colonne, qui sert la suppression d'une ligne et la somme par ligne de la vue.
- **T5 — Les fonctions du 4.5 ne sont pas redéfinies.** L'affichage du lien passe par une jointure PostgREST sur `creances`. Changer la signature de `creances_situation` obligerait à la recréer et à refaire ses droits, sans aucun gain de calcul.
- **T6 — Tests** dans le même style que le 4.7 et le 4.8 : jsonb attendus écrits en dur, `BEGIN … ROLLBACK`, utilisateurs authentifiés réels, assertions de structure. Les contrôles négatifs sont consignés dans la PR, et le test a son étape CI dédiée. La matrice `acces_pages.mjs` est inchangée, car aucune page n'est ajoutée.
