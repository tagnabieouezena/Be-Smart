-- Module 4.7 — Comparaison mensuelle CA encaissé / Dépenses / Résultat net.
-- Voir docs/briefs/Module-4.7-Comparaison-Mensuelle.md.
--
-- Lecture seule : aucune table, aucune écriture. Trois fonctions :
--   * variation_mensuelle    : fonction PURE qui porte les règles de variation
--                              (une seule fois dans tout le produit) ;
--   * comparaison_mensuelle  : tableau annuel (/comparaison) ;
--   * comparaison_accueil    : bandeau de l'accueil du CEO (/ecarts).
--
-- Le réel (CA, dépenses, résultat) vient EXCLUSIVEMENT de ecarts_mensuels (4.6) :
-- aucune règle de calcul du réel n'est réécrite ici, et la table creances n'est
-- jamais lue (un paiement de créance est une transaction d'entrée : il compte une
-- fois, au mois de son paiement). Index transactions (entreprise_id, date) :
-- transactions_date_idx existe depuis le Module 4.4, rien à ajouter.
--
-- Toutes les fonctions naissent SANS droit d'exécution (revoke all from public),
-- puis grant explicite à authenticated uniquement.

-- =========================================================================
-- 1. variation_mensuelle — règles 2 à 4 du brief, fonction pure
-- =========================================================================
-- variation     = courant − précédent ;
-- variation_pct = variation / précédent × 100 (2 décimales), seulement si
--                 précédent > 0 ;
-- les DEUX sont null si l'un des deux mois est sans aucune transaction
-- (règle 2 symétrique) ou si le mois précédent n'existe pas (a_precedent null,
-- cas de janvier du tableau annuel).
-- Aucun accès aux tables : aucun risque d'isolation.
create or replace function public.variation_mensuelle(
  p_courant numeric,
  p_precedent numeric,
  p_a_courant boolean,
  p_a_precedent boolean
)
returns table (variation numeric, variation_pct numeric)
language sql
immutable
set search_path = public
as $$
  select
    case when p_a_courant and p_a_precedent then p_courant - p_precedent end,
    case
      when p_a_courant and p_a_precedent and p_precedent > 0
        then round((p_courant - p_precedent) / p_precedent * 100, 2)
    end;
$$;

comment on function public.variation_mensuelle(numeric, numeric, boolean, boolean) is
  'Variation d''un mois sur le précédent (FCFA et %). Null si l''un des deux mois est sans transaction ; % null si le précédent vaut 0. Fonction pure, partagée par le tableau annuel et le bandeau.';

revoke all on function public.variation_mensuelle(numeric, numeric, boolean, boolean) from public;
revoke execute on function public.variation_mensuelle(numeric, numeric, boolean, boolean) from anon;
grant execute on function public.variation_mensuelle(numeric, numeric, boolean, boolean) to authenticated;

-- =========================================================================
-- 2. comparaison_mensuelle — tableau annuel
-- =========================================================================
-- Une ligne par mois : de janvier au mois de la date de référence inclus pour
-- l'année de référence, les 12 mois pour une année passée, zéro ligne pour une
-- année future. security invoker, restriction au CEO dans la requête elle-même
-- (CTE ent) : on ne part jamais d'une série de mois seule, sinon un comptable
-- obtiendrait 12 lignes de zéros. Zéro ligne, pas d'erreur, pour tout appelant
-- qui n'est pas le CEO de son entreprise.
create or replace function public.comparaison_mensuelle(
  p_annee int,
  p_date_reference date default current_date
)
returns table (
  mois int,
  statut_mois text,
  a_activite boolean,
  ca numeric,
  depenses numeric,
  resultat numeric,
  ca_variation numeric,
  ca_variation_pct numeric,
  depenses_variation numeric,
  depenses_variation_pct numeric,
  resultat_variation numeric,
  ca_cumul numeric,
  depenses_cumul numeric,
  resultat_cumul numeric
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
-- Mois affichés : jamais de mois futur.
bornes as (
  select case
    when p_annee < extract(year from p_date_reference)::int then 12
    when p_annee = extract(year from p_date_reference)::int then extract(month from p_date_reference)::int
    else 0
  end as dernier_mois
),
-- Le réel vient du Module 4.6, sans autre calcul.
reel as (
  select em.mois, em.revenus_reel, em.depenses_reel, em.resultat_reel
  from ent
  cross join public.ecarts_mensuels(p_annee, p_date_reference) em
),
-- Mois qui ont au moins une transaction (une seule passe sur transactions).
activite as (
  select distinct extract(month from t.date)::int as mois
  from ent
  join public.transactions t
    on t.entreprise_id = ent.id
   and t.date >= make_date(p_annee, 1, 1)
   and t.date < make_date(p_annee + 1, 1, 1)
),
base as (
  select
    m.mois,
    case
      when make_date(p_annee, m.mois, 1) < date_trunc('month', p_date_reference)::date then 'clos'
      else 'en_cours'
    end as statut_mois,
    (a.mois is not null) as a_activite,
    coalesce(r.revenus_reel, 0) as ca,
    coalesce(r.depenses_reel, 0) as depenses,
    coalesce(r.resultat_reel, 0) as resultat
  from ent
  cross join bornes b
  cross join generate_series(1, 12) as m(mois)
  left join reel r on r.mois = m.mois
  left join activite a on a.mois = m.mois
  where m.mois <= b.dernier_mois
),
avec_precedent as (
  select
    base.*,
    lag(base.ca) over w as ca_prec,
    lag(base.depenses) over w as depenses_prec,
    lag(base.resultat) over w as resultat_prec,
    lag(base.a_activite) over w as a_activite_prec
  from base
  window w as (order by base.mois)
)
select
  b.mois,
  b.statut_mois,
  b.a_activite,
  b.ca,
  b.depenses,
  b.resultat,
  vca.variation,
  vca.variation_pct,
  vdep.variation,
  vdep.variation_pct,
  vres.variation,
  sum(b.ca) over (order by b.mois),
  sum(b.depenses) over (order by b.mois),
  sum(b.resultat) over (order by b.mois)
from avec_precedent b
cross join lateral public.variation_mensuelle(b.ca, b.ca_prec, b.a_activite, b.a_activite_prec) vca
cross join lateral public.variation_mensuelle(b.depenses, b.depenses_prec, b.a_activite, b.a_activite_prec) vdep
cross join lateral public.variation_mensuelle(b.resultat, b.resultat_prec, b.a_activite, b.a_activite_prec) vres
order by b.mois;
$$;

comment on function public.comparaison_mensuelle(int, date) is
  'Comparaison mensuelle CA encaissé / dépenses / résultat net avec variations et cumuls (CEO uniquement : zéro ligne pour tout autre appelant). Le réel vient de ecarts_mensuels (4.6). Janvier : aucune variation. p_date_reference rend les tests déterministes.';

revoke all on function public.comparaison_mensuelle(int, date) from public;
revoke execute on function public.comparaison_mensuelle(int, date) from anon;
grant execute on function public.comparaison_mensuelle(int, date) to authenticated;

-- =========================================================================
-- 3. comparaison_accueil — bandeau de l'accueil du CEO
-- =========================================================================
-- Dernier mois clos comparé au mois calendaire qui le précède, même dans
-- l'année précédente (en janvier : décembre contre novembre ; en février :
-- janvier contre décembre de l'année précédente). Une ligne pour le CEO, zéro
-- ligne pour tout autre appelant. Les règles de variation sont celles de
-- variation_mensuelle (une seule règle dans le produit).
create or replace function public.comparaison_accueil(
  p_date_reference date default current_date
)
returns table (
  annee_clos int,
  mois_clos int,
  annee_precedent int,
  mois_precedent int,
  ca numeric,
  depenses numeric,
  resultat numeric,
  ca_precedent numeric,
  depenses_precedent numeric,
  resultat_precedent numeric,
  a_activite boolean,
  a_activite_precedent boolean,
  ca_variation numeric,
  ca_variation_pct numeric,
  depenses_variation numeric,
  depenses_variation_pct numeric,
  resultat_variation numeric
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
periodes as (
  select
    extract(year from d)::int as annee,
    extract(month from d)::int as mois,
    rang
  from (values
    ('clos', (date_trunc('month', p_date_reference) - interval '1 month')::date),
    ('precedent', (date_trunc('month', p_date_reference) - interval '2 months')::date)
  ) as v(rang, d)
),
-- Le réel vient du Module 4.6 : un appel par année concernée (une seule, sauf en février).
reel as (
  select p.rang, em.revenus_reel, em.depenses_reel, em.resultat_reel
  from ent
  cross join (select distinct annee from periodes) a
  cross join lateral public.ecarts_mensuels(a.annee, p_date_reference) em
  join periodes p on p.annee = a.annee and p.mois = em.mois
),
mois_lus as (
  select
    p.rang,
    p.annee,
    p.mois,
    coalesce(r.revenus_reel, 0) as ca,
    coalesce(r.depenses_reel, 0) as depenses,
    coalesce(r.resultat_reel, 0) as resultat,
    exists (
      select 1
      from public.transactions t
      where t.entreprise_id = ent.id
        and t.date >= make_date(p.annee, p.mois, 1)
        and t.date < (make_date(p.annee, p.mois, 1) + interval '1 month')::date
    ) as a_activite
  from ent
  cross join periodes p
  left join reel r on r.rang = p.rang
)
select
  c.annee,
  c.mois,
  pr.annee,
  pr.mois,
  c.ca,
  c.depenses,
  c.resultat,
  pr.ca,
  pr.depenses,
  pr.resultat,
  c.a_activite,
  pr.a_activite,
  vca.variation,
  vca.variation_pct,
  vdep.variation,
  vdep.variation_pct,
  vres.variation
from mois_lus c
join mois_lus pr on pr.rang = 'precedent'
cross join lateral public.variation_mensuelle(c.ca, pr.ca, c.a_activite, pr.a_activite) vca
cross join lateral public.variation_mensuelle(c.depenses, pr.depenses, c.a_activite, pr.a_activite) vdep
cross join lateral public.variation_mensuelle(c.resultat, pr.resultat, c.a_activite, pr.a_activite) vres
where c.rang = 'clos';
$$;

comment on function public.comparaison_accueil(date) is
  'Bandeau de l''accueil du CEO : dernier mois clos comparé au mois calendaire précédent (année précédente comprise). CEO uniquement : zéro ligne pour tout autre appelant. Le réel vient de ecarts_mensuels (4.6).';

revoke all on function public.comparaison_accueil(date) from public;
revoke execute on function public.comparaison_accueil(date) from anon;
grant execute on function public.comparaison_accueil(date) to authenticated;
