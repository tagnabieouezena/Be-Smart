-- Module 4.8 — Synthèses mensuelle, trimestrielle et annuelle.
-- Voir docs/briefs/Module-4.8-Syntheses.md.
--
-- Lecture seule : aucune table, aucune écriture, aucune policy nouvelle. Une
-- seule fonction, syntheses_periodes, pour les trois granularités.
--
-- Rien n'est recalculé :
--   * le réel de chaque mois (CA encaissé, dépenses, résultat, statut, mois avec
--     ou sans transaction) vient de comparaison_mensuelle (4.7), qui le lit dans
--     ecarts_mensuels (4.6) ; trimestres et année sont des SOMMES de ces mois ;
--   * le solde de caisse vient de solde_caisse_a (règle unique du solde daté) :
--     solde d'ouverture de l'année + cumul des résultats des mois ;
--   * les objectifs viennent de objectifs_ca, lue sous RLS (CEO uniquement).
-- Index : transactions_date_idx (entreprise_id, date) sert les lectures du réel,
-- l'index unique de objectifs_ca couvre celle des objectifs ; rien à ajouter.
--
-- Naît SANS droit d'exécution, puis grant explicite à authenticated.

create or replace function public.syntheses_periodes(
  p_annee int,
  p_date_reference date default current_date
)
returns table (
  granularite text,
  periode int,
  statut text,
  a_activite boolean,
  ca numeric,
  depenses numeric,
  resultat numeric,
  objectif_ca numeric,
  statut_objectif text,
  taux_realisation numeric,
  verdict_objectif text,
  solde_debut numeric,
  solde_fin numeric
)
language sql
stable
security invoker
set search_path = public
as $$
-- Restriction au CEO dans la requête elle-même : on ne part jamais d'une série
-- de mois seule, sinon un comptable obtiendrait des lignes de zéros. Zéro ligne,
-- pas d'erreur, pour tout autre appelant.
with ent as (
  select e.id
  from public.entreprises e
  where e.id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo'
),
-- Le réel : exclusivement comparaison_mensuelle (4.7). Mois affichés : jamais de
-- mois futur ; année future : aucune ligne.
reel as (
  select m.mois, m.statut_mois, m.a_activite, m.ca, m.depenses, m.resultat
  from ent
  cross join public.comparaison_mensuelle(p_annee, p_date_reference) m
),
-- Solde d'ouverture de l'année : règle unique du solde (fin du 31 décembre de
-- l'année précédente), valable pour toute année, avec ou sans activité.
ouverture as (
  select public.solde_caisse_a(make_date(p_annee, 1, 1) - 1) as solde
  from ent
),
-- Solde de début d'un mois = ouverture + somme des résultats des mois précédents
-- (identité de continuité de solde_caisse_a) ; un mois vide a un résultat nul.
mois_soldes as (
  select
    r.*,
    ouverture.solde
      + coalesce(sum(r.resultat) over (order by r.mois rows between unbounded preceding and 1 preceding), 0) as solde_debut
  from reel r
  cross join ouverture
),
niveaux as (
  select
    'mois'::text as granularite,
    s.mois as periode,
    s.statut_mois as statut,
    s.a_activite,
    s.ca,
    s.depenses,
    s.resultat,
    s.solde_debut,
    s.solde_debut + s.resultat as solde_fin
  from mois_soldes s

  union all

  -- Trimestre : somme de ses mois affichés ; clos seulement si ses 3 mois le sont.
  select
    'trimestre',
    (s.mois - 1) / 3 + 1,
    case when count(*) = 3 and bool_and(s.statut_mois = 'clos') then 'clos' else 'en_cours' end,
    bool_or(s.a_activite),
    sum(s.ca),
    sum(s.depenses),
    sum(s.resultat),
    (array_agg(s.solde_debut order by s.mois))[1],
    (array_agg(s.solde_debut + s.resultat order by s.mois desc))[1]
  from mois_soldes s
  group by (s.mois - 1) / 3 + 1

  union all

  -- Année : somme des mois affichés ; début de janvier, fin du dernier mois affiché.
  select
    'annee',
    p_annee,
    case when count(*) = 12 and bool_and(s.statut_mois = 'clos') then 'clos' else 'en_cours' end,
    bool_or(s.a_activite),
    sum(s.ca),
    sum(s.depenses),
    sum(s.resultat),
    (array_agg(s.solde_debut order by s.mois))[1],
    (array_agg(s.solde_debut + s.resultat order by s.mois desc))[1]
  from mois_soldes s
  having count(*) > 0
),
-- Chaque période n'affiche que l'objectif saisi à SA granularité : aucun prorata
-- d'un objectif annuel sur les mois ou les trimestres.
avec_objectif as (
  select n.*, o.montant_cible as objectif
  from niveaux n
  left join public.objectifs_ca o
    on o.entreprise_id = (select id from ent)
   and o.annee = p_annee
   and (
     (n.granularite = 'mois' and o.type_periode = 'mensuel' and o.mois = n.periode)
     or (n.granularite = 'trimestre' and o.type_periode = 'trimestriel' and o.trimestre = n.periode)
     or (n.granularite = 'annee' and o.type_periode = 'annuel')
   )
)
select
  a.granularite,
  a.periode,
  a.statut,
  a.a_activite,
  a.ca,
  a.depenses,
  a.resultat,
  a.objectif,
  case when a.objectif is null then 'absent' when a.objectif = 0 then 'nul' else 'defini' end,
  -- Taux tronqué à 1 décimale (jamais arrondi : « 100,0 % » seulement si l'objectif
  -- est atteint). Pas de taux sans objectif, avec objectif à 0, ni pour une période
  -- sans aucune transaction.
  case when a.objectif > 0 and a.a_activite then trunc(a.ca / a.objectif * 100, 1) end,
  -- Verdict : comparaison exacte en numeric ; période en cours = « à date », sans verdict.
  case
    when a.objectif > 0 and a.a_activite then
      case
        when a.statut = 'en_cours' then 'a_date'
        when a.ca >= a.objectif then 'atteint'
        else 'manque'
      end
  end,
  a.solde_debut,
  a.solde_fin
from avec_objectif a
order by case a.granularite when 'mois' then 1 when 'trimestre' then 2 else 3 end, a.periode;
$$;

comment on function public.syntheses_periodes(int, date) is
  'Synthèses par mois, trimestre et année : CA encaissé, dépenses, résultat net, objectif de CA et taux de réalisation (tronqué à 1 décimale), soldes de caisse début/fin. CEO uniquement : zéro ligne pour tout autre appelant. Le réel vient de comparaison_mensuelle (4.7), le solde de solde_caisse_a. p_date_reference rend les tests déterministes.';

revoke all on function public.syntheses_periodes(int, date) from public;
revoke execute on function public.syntheses_periodes(int, date) from anon;
grant execute on function public.syntheses_periodes(int, date) to authenticated;
