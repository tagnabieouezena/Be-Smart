-- Prérequis du Module 4.9 : lien créance ↔ revenu prévu.
-- Voir docs/briefs/Lien-Creance-Revenu-Prevu.md (décisions P1 à P8, Ouezz,
-- 2026-11-13).
--
-- Le cashflow prévisionnel (4.9) additionnera le CA prévisionnel du budget
-- (4.3) et les créances clients (4.5). Sans lien entre les deux, une facture
-- budgétée puis créée en créance serait comptée deux fois. Ce prérequis
-- ajoute un lien explicite, facultatif, porté par la créance (P1) : une
-- créance vise au plus une ligne de CA prévisionnel, une ligne peut recevoir
-- plusieurs créances (une ligne de budget est globale, pas facture par
-- facture).
--
-- Règle de consommation unique (P2), portée par la vue plus bas : une ligne
-- non annulée est réduite du montant dû de ses créances liées, plafonnée à 0
-- PAR LIGNE (jamais par mois, jamais par le reste dû).
--
-- Ni le Budget (4.3), ni le Journal (4.4), ni les créances (4.5), ni les
-- écarts (4.6) ne sont modifiés : aucune policy nouvelle, aucune fonction
-- existante redéfinie.

-- =========================================================================
-- 1. Colonne creances.ligne_revenu_prevu_id
-- =========================================================================
-- Facultative, choisie par le comptable (qui écrit déjà creances et lit déjà
-- lignes_revenu_prevu / budgets_mensuels). on delete set null (P5) : le CEO
-- peut supprimer sa ligne de budget sans toucher aux créances, qui sont des
-- faits réels — y compris une créance déjà payée.

alter table public.creances
  add column ligne_revenu_prevu_id uuid
    references public.lignes_revenu_prevu (id) on delete set null;

comment on column public.creances.ligne_revenu_prevu_id is
  'Ligne de CA prévisionnel que cette facture réalise (facultatif, choisi par le comptable). Plusieurs créances peuvent viser la même ligne. Règle de consommation : v_lignes_revenu_facturation.';

create index creances_ligne_revenu_prevu_id_idx
  on public.creances (ligne_revenu_prevu_id)
  where ligne_revenu_prevu_id is not null;

-- =========================================================================
-- 2. Garde-fou : même entreprise, ligne non annulée au moment du lien
-- =========================================================================
-- Comme verifier_coherence_ligne_revenu_prevu (4.3) et
-- verifier_date_solde_initial (prérequis 4.8) : un garde-fou, pas une policy,
-- car la RLS empêcherait seulement de VOIR une incohérence après coup, pas
-- de la CRÉER (leçon du 4.8, cf. test A3 contre N1).
--
-- Lien vide : rien à vérifier. UPDATE qui ne change pas le lien (comparaison
-- IS NOT DISTINCT FROM, insensible au null) : rien à vérifier non plus —
-- indispensable, car une créance déjà liée à une ligne annulée après coup
-- doit rester modifiable (notes, échéance, montant...).
--
-- Un seul message pour « ligne introuvable » et « ligne d'une autre
-- entreprise » : il ne révèle donc pas qu'un identifiant existe ailleurs
-- (même principe que les gardes-fous du 4.3/4.4). Testé sans RLS (test A3) :
-- le garde-fou tient même pour un appelant qui la contourne.

create or replace function public.verifier_lien_creance_revenu_prevu()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_entreprise_id uuid;
  v_statut text;
begin
  if new.ligne_revenu_prevu_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.ligne_revenu_prevu_id is not distinct from old.ligne_revenu_prevu_id then
    return new;
  end if;

  select entreprise_id, statut into v_entreprise_id, v_statut
  from public.lignes_revenu_prevu
  where id = new.ligne_revenu_prevu_id;

  if v_entreprise_id is null or v_entreprise_id <> new.entreprise_id then
    raise exception 'La ligne de revenu prévu référencée est introuvable.';
  end if;

  if v_statut = 'annule' then
    raise exception 'La ligne de revenu prévu référencée est annulée.';
  end if;

  return new;
end;
$$;

-- Fonction de trigger : aucun EXECUTE nécessaire (le droit n'est vérifié
-- qu'à la création du trigger). On retire aussi les droits accordés par
-- défaut aux rôles applicatifs (même motif que verifier_date_solde_initial).
revoke all on function public.verifier_lien_creance_revenu_prevu() from public, anon, authenticated, service_role;

create trigger verifier_lien_creance_revenu_prevu
  before insert or update on public.creances
  for each row execute function public.verifier_lien_creance_revenu_prevu();

-- =========================================================================
-- 3. Vue v_lignes_revenu_facturation — règle de consommation unique
-- =========================================================================
-- security_invoker = true (comme v_budget_mensuel_totaux) : la vue s'exécute
-- avec les droits de l'appelant, donc les policies RLS de lignes_revenu_prevu
-- et de creances s'appliquent normalement (CEO et comptable voient leur
-- propre entreprise, personne d'autre).
--
-- Une ligne par ligne de CA prévisionnel NON ANNULÉE (P3 : une ligne annulée
-- ne fait plus partie du budget, elle sort donc aussi de cette vue — le lien
-- d'une créance vers elle devient inerte sans qu'aucune donnée ne change).
-- montant_facture = somme des montant_du des créances liées (jamais le reste
-- dû : un paiement ne doit pas changer le reste à facturer, la part payée
-- est déjà dans le réel). reste_a_facturer plafonné à 0 PAR LIGNE.
--
-- v_budget_mensuel_totaux n'est pas modifiée : le CA prévisionnel du Budget
-- et du 4.6 reste le même ; le 4.9 retranchera les restes à facturer de
-- cette vue-ci, séparément.

create view public.v_lignes_revenu_facturation
with (security_invoker = true)
as
select
  l.id as ligne_revenu_prevu_id,
  l.entreprise_id,
  l.budget_mensuel_id,
  b.annee,
  b.mois,
  l.source,
  l.statut,
  l.montant_estime,
  coalesce(f.nb_creances, 0) as nb_creances,
  coalesce(f.montant_facture, 0) as montant_facture,
  greatest(l.montant_estime - coalesce(f.montant_facture, 0), 0) as reste_a_facturer
from public.lignes_revenu_prevu l
join public.budgets_mensuels b on b.id = l.budget_mensuel_id
left join (
  select c.ligne_revenu_prevu_id, count(*) as nb_creances, sum(c.montant_du) as montant_facture
  from public.creances c
  where c.ligne_revenu_prevu_id is not null
  group by c.ligne_revenu_prevu_id
) f on f.ligne_revenu_prevu_id = l.id
where l.statut <> 'annule';

comment on view public.v_lignes_revenu_facturation is
  'Montant facturé et reste à facturer par ligne de CA prévisionnel non annulée (creances.ligne_revenu_prevu_id). Consommation par le montant DÛ, plafonnée à 0 PAR LIGNE — jamais par mois, jamais par le reste dû. Numeric partout. Lue par le Module 4.9 et par le Budget (CEO).';

-- Les lignes nées sans droit pour anon/public (durcissement du 2026-09-28) :
-- droit explicite accordé seulement à authenticated.
revoke all on public.v_lignes_revenu_facturation from public;
revoke all on public.v_lignes_revenu_facturation from anon;
grant select on public.v_lignes_revenu_facturation to authenticated;
