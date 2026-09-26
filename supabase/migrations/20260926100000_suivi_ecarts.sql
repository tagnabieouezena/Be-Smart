-- Module 4.6 — Suivi des écarts (Prévu vs Réel).
-- Voir docs/briefs/Module-4.6-Suivi-Ecarts.md.
-- Lecture seule : aucune nouvelle table, aucune écriture.

-- =========================================================================
-- 1. Correctif v_budget_mensuel_totaux (Module 4.3) : exclure les lignes
--    'annule'. Une seule règle dans tout le produit : une ligne annulée ne
--    compte ni dans le prévu affiché au Module 4.3, ni dans les écarts 4.6.
--    Mêmes colonnes qu'avant, security_invoker conservé (RLS de l'appelant).
-- =========================================================================

create or replace view public.v_budget_mensuel_totaux
with (security_invoker = true)
as
select
  b.id as budget_mensuel_id,
  b.entreprise_id,
  b.mois,
  b.annee,
  coalesce(cf.total, 0) as total_charges_fixes,
  coalesce(cv.total, 0) as total_charges_variables,
  coalesce(r.total, 0) as total_ca_previsionnel,
  coalesce(r.total, 0) - coalesce(cf.total, 0) - coalesce(cv.total, 0) as resultat_previsionnel
from public.budgets_mensuels b
left join (
  select l.budget_mensuel_id, sum(l.montant) as total
  from public.lignes_charge_prevue l
  join public.categories c on c.id = l.categorie_id
  where c.type = 'fixe' and l.statut <> 'annule'
  group by l.budget_mensuel_id
) cf on cf.budget_mensuel_id = b.id
left join (
  select l.budget_mensuel_id, sum(l.montant) as total
  from public.lignes_charge_prevue l
  join public.categories c on c.id = l.categorie_id
  where c.type = 'variable' and l.statut <> 'annule'
  group by l.budget_mensuel_id
) cv on cv.budget_mensuel_id = b.id
left join (
  select budget_mensuel_id, sum(montant_estime) as total
  from public.lignes_revenu_prevu
  where statut <> 'annule'
  group by budget_mensuel_id
) r on r.budget_mensuel_id = b.id;

comment on view public.v_budget_mensuel_totaux is
  'Totaux calculés (charges fixes, charges variables, CA prévisionnel, résultat prévisionnel) par budget mensuel, hors lignes annulées — numeric partout, jamais de float.';

-- =========================================================================
-- 2. Seuil d'écart significatif — défini ici et nulle part ailleurs.
--    Le rendre réglable plus tard ne demandera que de modifier cette fonction.
-- =========================================================================

create or replace function public.seuil_ecart_significatif()
returns numeric
language sql
immutable
security invoker
set search_path = public
as $$
  select 0.10::numeric;
$$;

comment on function public.seuil_ecart_significatif() is
  'Seuil d''écart défavorable jugé significatif (10 %, fixe en V1, décision Ouezz).';

revoke all on function public.seuil_ecart_significatif() from public;
revoke execute on function public.seuil_ecart_significatif() from anon;
grant execute on function public.seuil_ecart_significatif() to authenticated;

-- =========================================================================
-- 3. ecarts_mensuels — comparaison Prévu / Réel, mois par mois
-- =========================================================================

-- security invoker (jamais definer) : les policies RLS des tables lues
-- s'appliquent à l'appelant. La restriction au CEO vit dans la fonction
-- elle-même (CTE `ent`) : le comptable lit pourtant transactions et
-- budgets, une simple vue lui aurait donné le résultat net par la bande.
-- Comportement identique à objectifs_ca (Module 4.2) : zéro ligne, pas
-- d'erreur, pour tout appelant qui n'est pas le CEO de son entreprise.
create or replace function public.ecarts_mensuels(
  p_annee int,
  p_date_reference date default current_date
)
returns table (
  mois int,
  statut_mois text,
  a_budget boolean,
  revenus_prevu numeric,
  revenus_reel numeric,
  revenus_ecart numeric,
  revenus_ecart_pct numeric,
  depenses_prevu numeric,
  depenses_reel numeric,
  depenses_ecart numeric,
  depenses_ecart_pct numeric,
  depenses_fixes_prevu numeric,
  depenses_fixes_reel numeric,
  depenses_fixes_ecart numeric,
  depenses_variables_prevu numeric,
  depenses_variables_reel numeric,
  depenses_variables_ecart numeric,
  resultat_prevu numeric,
  resultat_reel numeric,
  resultat_ecart numeric,
  resultat_ecart_pct numeric,
  solde_debut numeric,
  solde_fin_prevu numeric,
  solde_fin_reel numeric,
  solde_fin_ecart numeric,
  alerte_revenus boolean,
  alerte_depenses boolean,
  depense_non_prevue boolean,
  alerte_solde_negatif boolean
)
language sql
stable
security invoker
set search_path = public
as $$
with ent as (
  select e.id, e.solde_initial
  from public.entreprises e
  where e.id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
),
-- Solde cumulé de toutes les transactions antérieures à l'année demandée.
avant as (
  select coalesce(sum(case when t.type = 'entree' then t.montant else -t.montant end), 0) as net
  from ent
  join public.transactions t
    on t.entreprise_id = ent.id
   and t.date < make_date(p_annee, 1, 1)
),
tx as (
  select
    extract(month from t.date)::int as mois,
    sum(case when t.type = 'entree' then t.montant else 0 end) as revenus,
    sum(case when t.type = 'sortie' then t.montant else 0 end) as depenses,
    sum(case when t.type = 'sortie' and c.type = 'fixe' then t.montant else 0 end) as fixes,
    sum(case when t.type = 'sortie' and c.type = 'variable' then t.montant else 0 end) as variables
  from ent
  join public.transactions t
    on t.entreprise_id = ent.id
   and t.date >= make_date(p_annee, 1, 1)
   and t.date < make_date(p_annee + 1, 1, 1)
  join public.categories c on c.id = t.categorie_id
  group by 1
),
-- Prévu : réutilise la vue du Module 4.3 (lignes 'annule' exclues), pour
-- qu'il n'existe qu'une seule règle de calcul du prévu dans le produit.
budget as (
  select
    v.mois,
    v.total_ca_previsionnel as revenus,
    v.total_charges_fixes as fixes,
    v.total_charges_variables as variables
  from ent
  join public.v_budget_mensuel_totaux v
    on v.entreprise_id = ent.id
   and v.annee = p_annee
),
base as (
  select
    m.mois,
    (tx.mois is not null or bu.mois is not null) as actif,
    (bu.mois is not null) as a_budget,
    bu.revenus as rev_prevu,
    coalesce(tx.revenus, 0) as rev_reel,
    bu.fixes + bu.variables as dep_prevu,
    coalesce(tx.depenses, 0) as dep_reel,
    bu.fixes as fix_prevu,
    coalesce(tx.fixes, 0) as fix_reel,
    bu.variables as var_prevu,
    coalesce(tx.variables, 0) as var_reel,
    coalesce(tx.revenus, 0) - coalesce(tx.depenses, 0) as res_reel,
    bu.revenus - (bu.fixes + bu.variables) as res_prevu
  from generate_series(1, 12) as m(mois)
  left join tx on tx.mois = m.mois
  left join budget bu on bu.mois = m.mois
),
-- Le prévu repart du réel constaté (décision Ouezz) : solde de début
-- commun, obtenu par somme cumulative des résultats réels des mois
-- précédents, pas par une sous-requête par ligne.
cumul as (
  select
    base.*,
    ent.solde_initial + avant.net
      + coalesce(
          sum(base.res_reel) over (order by base.mois rows between unbounded preceding and 1 preceding),
          0
        ) as solde_debut,
    case
      when make_date(p_annee, base.mois, 1) < date_trunc('month', p_date_reference)::date then 'clos'
      when make_date(p_annee, base.mois, 1) = date_trunc('month', p_date_reference)::date then 'en_cours'
      else 'futur'
    end as statut_mois
  from base
  cross join ent
  cross join avant
)
select
  c.mois,
  c.statut_mois,
  c.a_budget,
  c.rev_prevu,
  c.rev_reel,
  c.rev_reel - c.rev_prevu,
  case when c.rev_prevu > 0 then round((c.rev_reel - c.rev_prevu) / c.rev_prevu * 100, 2) end,
  c.dep_prevu,
  c.dep_reel,
  c.dep_reel - c.dep_prevu,
  case when c.dep_prevu > 0 then round((c.dep_reel - c.dep_prevu) / c.dep_prevu * 100, 2) end,
  c.fix_prevu,
  c.fix_reel,
  c.fix_reel - c.fix_prevu,
  c.var_prevu,
  c.var_reel,
  c.var_reel - c.var_prevu,
  c.res_prevu,
  c.res_reel,
  c.res_reel - c.res_prevu,
  case when c.res_prevu > 0 then round((c.res_reel - c.res_prevu) / c.res_prevu * 100, 2) end,
  c.solde_debut,
  c.solde_debut + c.res_prevu,
  c.solde_debut + c.res_reel,
  (c.solde_debut + c.res_reel) - (c.solde_debut + c.res_prevu),
  -- Alertes d'écart : défavorable uniquement, mois clos uniquement.
  coalesce(
    c.statut_mois = 'clos'
    and c.rev_prevu > 0
    and (c.rev_prevu - c.rev_reel) / c.rev_prevu >= public.seuil_ecart_significatif(),
    false
  ),
  coalesce(
    c.statut_mois = 'clos'
    and c.dep_prevu > 0
    and (c.dep_reel - c.dep_prevu) / c.dep_prevu >= public.seuil_ecart_significatif(),
    false
  ),
  coalesce(c.dep_prevu = 0 and c.dep_reel > 0, false),
  coalesce(c.statut_mois in ('en_cours', 'futur') and (c.solde_debut + c.res_prevu) < 0, false)
from cumul c
where c.actif
order by c.mois;
$$;

comment on function public.ecarts_mensuels(int, date) is
  'Écarts Prévu/Réel par mois (CEO uniquement : zéro ligne pour tout autre appelant). Réel calculé sur les montants des transactions, jamais sur le statut des lignes prévisionnelles. p_date_reference rend les tests déterministes.';

revoke all on function public.ecarts_mensuels(int, date) from public;
revoke execute on function public.ecarts_mensuels(int, date) from anon;
grant execute on function public.ecarts_mensuels(int, date) to authenticated;

-- =========================================================================
-- 4. Index — déjà présent (transactions_date_idx sur (entreprise_id, date),
--    Module 4.4) : rien à ajouter pour CDC 5.3.
-- =========================================================================
