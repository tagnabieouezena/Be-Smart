# Be Smart Pilotage — Décision : Supabase plutôt que Firebase

*Fiche de décision (ADR). Tranchée par Ouezz. Sert de référence si la question est reposée en cours de projet.*

## Décision

**Supabase (PostgreSQL) est retenu**, Firebase (Firestore) est écarté.

## Contexte

Be Smart Pilotage n'est pas un produit de contenu (pas de médias à héberger — un justificatif photo occasionnel suffit). C'est un produit de **reporting financier multi-tenant** : rapprochement prévu/réel, synthèses trimestrielles, cashflow prévisionnel, balance âgée des créances, KPI cumulés, comparaisons mensuelles. La priorité absolue est la **sécurité de l'isolation entre entreprises clientes** et l'**exactitude des calculs financiers** — pas la vitesse de mise en marché sur du CRUD simple.

## Raisons de la décision

1. **La logique métier est relationnelle, pas documentaire.** Le CDC (section 6) est déjà pensé en entités liées par clés étrangères, avec des agrégations partout (SUM par catégorie/mois/trimestre, jointures budget↔transaction↔créance). Postgres fait ça nativement (GROUP BY, vues, jointures). Firestore (NoSQL) n'a pas d'agrégation native : il aurait fallu dénormaliser et maintenir des compteurs à la main via Cloud Functions, ce qui multiplie les points de défaillance sur la partie la plus sensible du produit.

2. **Sécurité imposée au niveau du moteur, pas de l'application.** Le Row-Level Security de Postgres s'applique dans la base elle-même : une politique RLS ne peut pas être contournée par une route API mal écrite. C'est le socle de l'isolation `entreprise_id` + rôle définie dans `01-stack-et-architecture.md`. Les Firestore Security Rules sont un langage à part, plus difficile à raisonner pour des combinaisons rôle+tenant complexes, et une Cloud Function tournant en mode admin peut tout contourner si la discipline manque.

3. **Intégrité transactionnelle sur l'argent.** La règle « une créance payée devient automatiquement une transaction réelle » (CDC 4.5) doit être atomique sur plusieurs tables. Postgres le fait nativement (transactions ACID, contraintes, triggers). C'est exactement ce type de garantie qui a permis de corriger, sur Air Ajjar, des bugs comme la dérive silencieuse de solde de caisse ou la double soumission — des risques bien réels sur un logiciel financier.

4. **Exactitude numérique.** Les montants FCFA sont stockés en `numeric` Postgres (précision exacte), pas en float64 comme Firestore — moins de risque de dérive d'arrondi sur des cumuls (KPI, synthèses annuelles).

5. **Forfaits gratuits.** Supabase : projet Postgres complet, RLS illimité, auth jusqu'à 50 000 utilisateurs actifs/mois, aucune carte bancaire requise pour démarrer, et un CLI local (Docker) fait pour développer à coût zéro — exactement le workflow retenu (`01-stack-et-architecture.md`, section 3). Firebase : le plan gratuit Firestore est généreux, mais toute logique métier (rapprochement, KPI, alertes) demande des Cloud Functions, qui exigent le plan payant Blaze (carte bancaire requise) même à faible usage ; et la facturation Firestore au nombre de lectures rend les coûts moins prévisibles à mesure que le nombre d'entreprises clientes grandit.

## Contrepartie assumée

Le point fort réel de Firestore est la synchronisation offline-first, pertinente vu l'exigence CDC 5.1 (connexion instable). Ce n'est pas natif sur Supabase — d'où la couche PWA dédiée déjà prévue (Serwist + Dexie + Background Sync). C'est un coût d'ingénierie ponctuel, jugé largement compensé par les garanties de sécurité et d'exactitude ci-dessus.

## Conséquence directe sur les principes du projet

Cette décision confirme deux principes non négociables, désormais explicites dans `02-ways-of-working.md` et `CLAUDE.md` :

- **La sécurité de l'isolation multi-tenant n'est jamais négociable** — aucune fonctionnalité ne justifie une politique RLS incomplète ou une vérification faite seulement côté UI.
- **L'exactitude des calculs financiers n'est jamais négociable** — tout calcul monétaire passe par `numeric` (jamais de float), toute opération qui touche plusieurs tables liées à l'argent est transactionnelle, et tout nouveau calcul doit être vérifié par un cas de test concret avant/après (pas seulement "les tests passent").
