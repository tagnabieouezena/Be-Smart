-- Solde de caisse initial DATÉ (prérequis du Module 4.8).
-- Voir docs/briefs/Solde-Initial-Date.md.
--
-- Avant : entreprises.solde_initial sans date ; ecarts_mensuels (4.6) ajoutait
-- le résultat de TOUTES les transactions antérieures à la période, ce qui
-- double-compte l'historique saisi après un solde « d'aujourd'hui ».
--
-- Maintenant : solde_initial est le solde de caisse À LA FIN de la journée
-- date_solde_initial (D). Règle unique, solde à la fin de la journée t :
--   t >= D : solde_initial + somme des transactions telles que D < date <= t
--   t <  D : solde_initial - somme des transactions telles que t < date <= D
--   F(D) = solde_initial (les transactions datées D sont DÉJÀ dans le solde).
-- Intervalles semi-ouverts à gauche (borne basse exclue, borne haute incluse).
-- Aucun solde n'est stocké : l'ordre de saisie n'a aucune influence.

-- =========================================================================
-- 1. Colonne
-- =========================================================================
-- Défaut 2000-01-01 : aucune transaction ne peut lui être antérieure, donc le
-- comportement antérieur (tout s'ajoute au solde initial) est reproduit
-- exactement pour les entreprises existantes, du seed, des tests et créées par
-- creer_entreprise_et_ceo.
alter table public.entreprises
  add column date_solde_initial date not null default date '2000-01-01';

comment on column public.entreprises.date_solde_initial is
  'Date D à la FIN de laquelle solde_initial est le solde de caisse (opérations du jour D comprises). 2000-01-01 = aucune date renseignée.';

-- =========================================================================
-- 2. Garde-fou : pas de date future
-- =========================================================================
-- La fin d'une journée à venir ne s'observe pas. Trigger (et non check, car
-- current_date n'est pas immutable), déclenché seulement quand la date change.
create or replace function public.verifier_date_solde_initial()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.date_solde_initial > current_date then
    raise exception 'La date du solde de caisse ne peut pas être dans le futur.';
  end if;
  return new;
end;
$$;

-- Fonction de trigger : aucun EXECUTE nécessaire (il n'est vérifié qu'à la création du
-- trigger). On retire aussi les droits accordés par défaut aux rôles applicatifs.
revoke all on function public.verifier_date_solde_initial() from public, anon, authenticated, service_role;

create trigger entreprises_date_solde_initial
  before insert or update of date_solde_initial on public.entreprises
  for each row execute function public.verifier_date_solde_initial();

-- =========================================================================
-- 3. solde_caisse_a — la règle unique du solde de caisse
-- =========================================================================
-- Solde de caisse de l'entreprise de l'appelant à la FIN de la journée p_date.
-- security invoker ; null pour tout appelant qui n'est pas le CEO (comptable,
-- supervision) et pour p_date null. Une seule formule, deux lectures : les deux
-- filtres ne peuvent pas être non vides en même temps (le premier exige
-- p_date >= D, le second p_date < D). La jointure borne la lecture des
-- transactions à l'intervalle utile (index transactions_date_idx).
create or replace function public.solde_caisse_a(p_date date)
returns numeric
language sql
stable
security invoker
set search_path = public
as $$
  select
    e.solde_initial
    + coalesce(sum(case when t.type = 'entree' then t.montant else -t.montant end)
        filter (where t.date > e.date_solde_initial and t.date <= p_date), 0)
    - coalesce(sum(case when t.type = 'entree' then t.montant else -t.montant end)
        filter (where t.date > p_date and t.date <= e.date_solde_initial), 0)
  from public.entreprises e
  left join public.transactions t
    on t.entreprise_id = e.id
   and t.date >= least(e.date_solde_initial, p_date)
   and t.date <= greatest(e.date_solde_initial, p_date)
  where e.id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
    and p_date is not null
  group by e.id, e.solde_initial, e.date_solde_initial;
$$;

comment on function public.solde_caisse_a(date) is
  'Solde de caisse à la fin de la journée p_date, à partir du solde initial daté (règle unique du produit). CEO uniquement : null pour tout autre appelant.';

revoke all on function public.solde_caisse_a(date) from public;
revoke execute on function public.solde_caisse_a(date) from anon;
grant execute on function public.solde_caisse_a(date) to authenticated;

-- =========================================================================
-- 4. ecarts_mensuels (4.6) — modifiée a minima
-- =========================================================================
-- Seule fonction qui lisait solde_initial. Une seule modification : le solde
-- d'ouverture de l'année est solde_caisse_a(31 décembre précédent) ; le reste
-- (signature, colonnes, alertes, restriction au CEO, ACL) est inchangé.
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
  select e.id
  from public.entreprises e
  where e.id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
),
-- Solde d'ouverture de l'année : solde de caisse à la fin du 31 décembre de l'année
-- précédente, par la règle unique du solde (solde_caisse_a : solde initial daté,
-- valable avant comme après la date du solde). Aucune règle du solde n'est recopiée ici.
ouverture as (
  select public.solde_caisse_a(make_date(p_annee, 1, 1) - 1) as solde
  from ent
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
-- précédents, pas par une sous-requête par ligne. Le cumul à l'intérieur de
-- l'année reste exact quelle que soit la date du solde initial (identité de
-- continuité de solde_caisse_a).
cumul as (
  select
    base.*,
    ouverture.solde
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
  cross join ouverture
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
