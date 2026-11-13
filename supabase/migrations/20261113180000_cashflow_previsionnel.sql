-- Module 4.9 — Cashflow prévisionnel (projection + simulateur).
-- Voir docs/briefs/Module-4.9-Cashflow-Previsionnel.md (décisions D1 à D9 et
-- choix T1 à T9 décidés par Ouezz le 2026-11-12) et le prérequis
-- docs/briefs/Lien-Creance-Revenu-Prevu.md (PR #26).
--
-- Lecture seule : aucune table, aucune policy, aucune écriture. Une seule
-- fonction, cashflow_previsionnel, pour la base et la simulation, par mois et
-- par trimestre (T1).
--
-- Rien n'est recalculé (T2) :
--   * solde de départ : solde_caisse_a(p_date_reference), règle unique du
--     solde daté (D1) ; les soldes suivants sont des sommes cumulées des
--     résultats mensuels (T5) ;
--   * charges prévues : v_budget_mensuel_totaux (lignes annulées exclues) ;
--   * CA prévu restant à facturer : v_lignes_revenu_facturation (prérequis :
--     consommation par le montant facturé, plafonnée à 0 par ligne) ;
--   * créances : creances_situation(p_date_reference) — reste dû et tranche,
--     jamais recalculés ;
--   * seule lecture nouvelle du réel : entrées, entrées payant une créance et
--     sorties du mois en cours jusqu'à la date de référence incluse.
--
-- Le simulateur ne peut rien écrire : fonction STABLE (PostgreSQL y interdit
-- toute écriture) et corps sans insert, update ni delete ; paramètres passés en
-- jsonb, rien n'est stocké (D6, T3, T4, T7).
--
-- Index : transactions_date_idx (entreprise_id, date) sert le réel du mois en
-- cours, creances_entreprise_echeance_idx les créances, l'index de
-- budgets_mensuels (entreprise_id, mois, annee) les budgets ; rien à ajouter.
--
-- Naît SANS droit d'exécution, puis grant explicite à authenticated.

create or replace function public.cashflow_previsionnel(
  p_date_reference date default current_date,
  p_depenses_reportees jsonb default '[]'::jsonb,
  p_creances_retardees jsonb default '[]'::jsonb
)
returns table (
  granularite text,
  annee int,
  periode int,
  statut text,
  projete boolean,
  nb_mois_projetes int,
  encaissements_budget numeric,
  encaissements_creances numeric,
  encaissements numeric,
  depenses numeric,
  resultat numeric,
  solde_debut numeric,
  solde_fin numeric,
  solde_negatif boolean,
  encaissements_simule numeric,
  depenses_simule numeric,
  resultat_simule numeric,
  solde_debut_simule numeric,
  solde_fin_simule numeric,
  solde_negatif_simule boolean,
  ecart_solde_fin numeric
)
language plpgsql
stable
security invoker
set search_path = public
as $$
#variable_conflict use_column
declare
  v_entreprise_id uuid;
  v_mois_courant date;
  v_dernier_projete date;
  v_elem jsonb;
  v_ligne record;
  v_creance record;
  v_montant numeric;
  v_cible date;
  v_jours int;
  v_uuid uuid;
  v_deja_reporte jsonb := '{}'::jsonb;
  v_retards_vus uuid[] := '{}';
  v_regex_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  -- 1. Restriction au CEO, AVANT toute validation : tout autre appelant
  --    (comptable, supervision, inconnu) obtient zéro ligne, jamais d'erreur,
  --    même avec des paramètres de simulation invalides.
  select e.id into v_entreprise_id
  from public.entreprises e
  where e.id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'ceo';

  if v_entreprise_id is null or p_date_reference is null then
    return;
  end if;

  v_mois_courant := date_trunc('month', p_date_reference)::date;

  -- Dernier mois projeté : la projection s'arrête au premier mois sans budget
  -- de l'horizon de 12 mois (D2, D3). null = rien n'est projeté.
  select max(h.debut) into v_dernier_projete
  from (
    select (v_mois_courant + make_interval(months => k))::date as debut, k
    from generate_series(0, 11) k
  ) h
  where not exists (
    select 1
    from generate_series(0, h.k) j
    where not exists (
      select 1 from public.budgets_mensuels b
      where b.entreprise_id = v_entreprise_id
        and b.annee = extract(year from v_mois_courant + make_interval(months => j))::int
        and b.mois = extract(month from v_mois_courant + make_interval(months => j))::int
    )
  );

  -- 2. Validation de la simulation (exceptions explicites, CEO seulement).
  --    Un identifiant d'une autre entreprise produit exactement le même message
  --    qu'un identifiant inexistant.
  if p_depenses_reportees is null then p_depenses_reportees := '[]'::jsonb; end if;
  if p_creances_retardees is null then p_creances_retardees := '[]'::jsonb; end if;

  if jsonb_typeof(p_depenses_reportees) <> 'array' then
    raise exception 'Simulation invalide : les dépenses reportées doivent être une liste.';
  end if;
  if jsonb_typeof(p_creances_retardees) <> 'array' then
    raise exception 'Simulation invalide : les paiements retardés doivent être une liste.';
  end if;

  for v_elem in select value from jsonb_array_elements(p_depenses_reportees) loop
    -- Types d'abord (SQL ne garantit pas l'ordre d'évaluation d'un OR : aucun
    -- cast n'est tenté tant que les types ne sont pas vérifiés).
    if jsonb_typeof(v_elem) <> 'object'
       or jsonb_typeof(v_elem -> 'ligne_charge_id') is distinct from 'string'
       or jsonb_typeof(v_elem -> 'montant') is distinct from 'number'
       or jsonb_typeof(v_elem -> 'vers_annee') is distinct from 'number'
       or jsonb_typeof(v_elem -> 'vers_mois') is distinct from 'number' then
      raise exception 'Simulation invalide : report attendu {ligne_charge_id, montant, vers_annee, vers_mois}.';
    end if;
    if (v_elem ->> 'ligne_charge_id') !~ v_regex_uuid
       or (v_elem ->> 'vers_annee')::numeric <> trunc((v_elem ->> 'vers_annee')::numeric)
       or (v_elem ->> 'vers_mois')::numeric <> trunc((v_elem ->> 'vers_mois')::numeric)
       or (v_elem ->> 'vers_mois')::numeric not between 1 and 12
       or (v_elem ->> 'vers_annee')::numeric not between 2000 and 9999 then
      raise exception 'Simulation invalide : report attendu {ligne_charge_id, montant, vers_annee, vers_mois}.';
    end if;

    v_montant := (v_elem ->> 'montant')::numeric;
    if v_montant <= 0 then
      raise exception 'Simulation invalide : le montant reporté doit être positif.';
    end if;

    v_uuid := (v_elem ->> 'ligne_charge_id')::uuid;
    select l.id, l.montant, l.statut, make_date(b.annee, b.mois, 1) as mois_ligne
      into v_ligne
    from public.lignes_charge_prevue l
    join public.budgets_mensuels b on b.id = l.budget_mensuel_id
    where l.id = v_uuid
      and l.entreprise_id = v_entreprise_id;

    if v_ligne.id is null then
      raise exception 'Simulation invalide : ligne de charge introuvable.';
    end if;
    if v_ligne.statut in ('annule', 'realise') then
      raise exception 'Simulation invalide : une ligne de charge annulée ou réalisée ne peut pas être reportée.';
    end if;
    if v_ligne.mois_ligne < v_mois_courant then
      raise exception 'Simulation invalide : une ligne d''un mois passé ne peut pas être reportée.';
    end if;

    v_cible := make_date((v_elem ->> 'vers_annee')::numeric::int, (v_elem ->> 'vers_mois')::numeric::int, 1);
    if v_cible = v_ligne.mois_ligne then
      raise exception 'Simulation invalide : le mois cible est le mois d''origine de la ligne.';
    end if;
    -- « Avancer une dépense » est hors périmètre du simulateur (brief) : un
    -- report va toujours vers un mois postérieur.
    if v_cible < v_ligne.mois_ligne then
      raise exception 'Simulation invalide : une dépense ne peut être reportée que vers un mois postérieur.';
    end if;
    if v_dernier_projete is null or v_cible > v_dernier_projete then
      raise exception 'Simulation invalide : le mois cible n''est pas un mois projeté.';
    end if;

    -- Plusieurs reports d'une même ligne : leur somme ne dépasse pas la ligne.
    v_deja_reporte := jsonb_set(
      v_deja_reporte, array[v_uuid::text],
      to_jsonb(coalesce((v_deja_reporte ->> v_uuid::text)::numeric, 0) + v_montant)
    );
    if (v_deja_reporte ->> v_uuid::text)::numeric > v_ligne.montant then
      raise exception 'Simulation invalide : le montant reporté dépasse le montant de la ligne (% FCFA).', v_ligne.montant;
    end if;
  end loop;

  for v_elem in select value from jsonb_array_elements(p_creances_retardees) loop
    if jsonb_typeof(v_elem) <> 'object'
       or jsonb_typeof(v_elem -> 'creance_id') is distinct from 'string'
       or jsonb_typeof(v_elem -> 'jours') is distinct from 'number' then
      raise exception 'Simulation invalide : retard attendu {creance_id, jours}.';
    end if;
    if (v_elem ->> 'creance_id') !~ v_regex_uuid
       or (v_elem ->> 'jours')::numeric <> trunc((v_elem ->> 'jours')::numeric)
       or (v_elem ->> 'jours')::numeric > 3650 then
      raise exception 'Simulation invalide : retard attendu {creance_id, jours}.';
    end if;

    v_jours := (v_elem ->> 'jours')::numeric::int;
    if v_jours <= 0 then
      raise exception 'Simulation invalide : le retard doit être d''au moins un jour.';
    end if;

    v_uuid := (v_elem ->> 'creance_id')::uuid;
    if v_uuid = any (v_retards_vus) then
      raise exception 'Simulation invalide : une même créance ne peut être retardée qu''une fois.';
    end if;
    v_retards_vus := v_retards_vus || v_uuid;

    select s.id, s.reste_du, s.tranche into v_creance
    from public.creances_situation(p_date_reference) s
    where s.id = v_uuid;

    if v_creance.id is null then
      raise exception 'Simulation invalide : créance introuvable.';
    end if;
    if v_creance.reste_du <= 0 or v_creance.tranche = 'plus_60' then
      raise exception 'Simulation invalide : cette créance n''est pas attendue (soldée ou en retard de plus de 60 jours).';
    end if;
  end loop;

  -- 3. Projection : une seule requête, qui repart elle aussi de l'entreprise
  --    du CEO (défense en profondeur).
  return query
  with ent as (
    select e.id
    from public.entreprises e
    where e.id = public.current_entreprise_id()
      and public.current_role_utilisateur() = 'ceo'
  ),
  horizon as (
    select k, (v_mois_courant + make_interval(months => k))::date as debut
    from generate_series(0, 11) k
  ),
  mois as (
    select
      h.k,
      h.debut,
      extract(year from h.debut)::int as an,
      extract(month from h.debut)::int as mo,
      (v_dernier_projete is not null and h.debut <= v_dernier_projete) as est_projete,
      v.budget_mensuel_id,
      v.total_charges_fixes + v.total_charges_variables as charges_prevues
    from horizon h
    cross join ent
    left join public.v_budget_mensuel_totaux v
      on v.entreprise_id = ent.id
     and v.annee = extract(year from h.debut)::int
     and v.mois = extract(month from h.debut)::int
  ),
  -- CA prévu restant à facturer, par mois (règle du prérequis, non recalculée).
  facturation as (
    select f.budget_mensuel_id, sum(f.reste_a_facturer) as reste
    from public.v_lignes_revenu_facturation f
    join ent on f.entreprise_id = ent.id
    group by f.budget_mensuel_id
  ),
  -- Réel du mois en cours jusqu'à la fin de la journée de référence : les
  -- transactions postérieures sont ignorées (D8).
  reel as (
    select
      coalesce(sum(t.montant) filter (where t.type = 'entree'), 0) as entrees,
      coalesce(sum(t.montant) filter (where t.type = 'entree' and t.creance_id is not null), 0) as paiements_creances,
      coalesce(sum(t.montant) filter (where t.type = 'sortie'), 0) as sorties
    from ent
    left join public.transactions t
      on t.entreprise_id = ent.id
     and t.date >= v_mois_courant
     and t.date <= p_date_reference
  ),
  -- Reports simulés : le montant quitte le mois de la ligne, rejoint le mois cible.
  reports as (
    select (r ->> 'ligne_charge_id')::uuid as ligne_id,
           (r ->> 'montant')::numeric as montant,
           make_date((r ->> 'vers_annee')::numeric::int, (r ->> 'vers_mois')::numeric::int, 1) as cible
    from jsonb_array_elements(p_depenses_reportees) r
  ),
  deltas as (
    select make_date(b.annee, b.mois, 1) as debut, -r.montant as delta
    from reports r
    join public.lignes_charge_prevue l on l.id = r.ligne_id
    join public.budgets_mensuels b on b.id = l.budget_mensuel_id
    union all
    select r.cible, r.montant from reports r
  ),
  delta_mois as (
    select d.debut, sum(d.delta) as delta from deltas d group by d.debut
  ),
  -- Créances attendues : reste dû > 0 et hors tranche plus_60 (D5). Date
  -- attendue = max(échéance, référence), décalée du retard simulé.
  retards as (
    select (r ->> 'creance_id')::uuid as creance_id, (r ->> 'jours')::numeric::int as jours
    from jsonb_array_elements(p_creances_retardees) r
  ),
  attendues as (
    select
      s.reste_du,
      date_trunc('month', greatest(s.echeance, p_date_reference))::date as mois_base,
      date_trunc('month', greatest(s.echeance, p_date_reference) + coalesce(rt.jours, 0))::date as mois_simule
    from ent
    cross join public.creances_situation(p_date_reference) s
    left join retards rt on rt.creance_id = s.id
    where s.reste_du > 0
      and s.tranche is distinct from 'plus_60'
  ),
  flux as (
    select
      m.k, m.debut, m.an, m.mo, m.est_projete,
      case
        when not m.est_projete then null
        when m.k = 0 then greatest(coalesce(fa.reste, 0) - (reel.entrees - reel.paiements_creances), 0)
        else coalesce(fa.reste, 0)
      end as enc_budget,
      case when m.est_projete then
        coalesce((select sum(a.reste_du) from attendues a where a.mois_base = m.debut), 0)
      end as enc_creances,
      case when m.est_projete then
        coalesce((select sum(a.reste_du) from attendues a where a.mois_simule = m.debut), 0)
      end as enc_creances_sim,
      case
        when not m.est_projete then null
        when m.k = 0 then greatest(m.charges_prevues - reel.sorties, 0)
        else m.charges_prevues
      end as dep,
      case
        when not m.est_projete then null
        when m.k = 0 then greatest(m.charges_prevues + coalesce(dm.delta, 0) - reel.sorties, 0)
        else m.charges_prevues + coalesce(dm.delta, 0)
      end as dep_sim
    from mois m
    cross join reel
    left join facturation fa on fa.budget_mensuel_id = m.budget_mensuel_id
    left join delta_mois dm on dm.debut = m.debut
  ),
  -- Soldes : un seul appel à solde_caisse_a, puis cumul des résultats (T5).
  depart as (
    select public.solde_caisse_a(p_date_reference) as solde from ent
  ),
  mois_calcules as (
    select
      f.*,
      f.enc_budget + f.enc_creances as enc,
      f.enc_budget + f.enc_creances_sim as enc_sim,
      f.enc_budget + f.enc_creances - f.dep as res,
      f.enc_budget + f.enc_creances_sim - f.dep_sim as res_sim
    from flux f
  ),
  mois_soldes as (
    select
      mc.*,
      case when mc.est_projete then
        d.solde + coalesce(sum(mc.res) over (order by mc.k rows between unbounded preceding and 1 preceding), 0)
      end as sd,
      case when mc.est_projete then
        d.solde + coalesce(sum(mc.res_sim) over (order by mc.k rows between unbounded preceding and 1 preceding), 0)
      end as sd_sim
    from mois_calcules mc
    cross join depart d
  ),
  lignes_mois as (
    select
      'mois'::text as g,
      ms.an, ms.mo as per,
      case when ms.k = 0 then 'en_cours' else 'futur' end as st,
      ms.est_projete as pr,
      case when ms.est_projete then 1 else 0 end as nb,
      ms.enc_budget, ms.enc_creances, ms.enc, ms.dep, ms.res,
      ms.sd, ms.sd + ms.res as sf,
      ms.enc_sim, ms.dep_sim, ms.res_sim,
      ms.sd_sim, ms.sd_sim + ms.res_sim as sf_sim,
      ms.k as ordre
    from mois_soldes ms
  ),
  -- Trimestres civils : sommes de leurs mois projetés ; soldes du premier et du
  -- dernier mois projetés ; tout est null sans mois projeté.
  lignes_trimestre as (
    select
      'trimestre'::text as g,
      ms.an, (ms.mo - 1) / 3 + 1 as per,
      case when bool_or(ms.k = 0) then 'en_cours' else 'futur' end as st,
      bool_or(ms.est_projete) as pr,
      (count(*) filter (where ms.est_projete))::int as nb,
      sum(ms.enc_budget), sum(ms.enc_creances), sum(ms.enc), sum(ms.dep), sum(ms.res),
      (array_agg(ms.sd order by ms.k) filter (where ms.est_projete))[1],
      (array_agg(ms.sd + ms.res order by ms.k desc) filter (where ms.est_projete))[1],
      sum(ms.enc_sim), sum(ms.dep_sim), sum(ms.res_sim),
      (array_agg(ms.sd_sim order by ms.k) filter (where ms.est_projete))[1],
      (array_agg(ms.sd_sim + ms.res_sim order by ms.k desc) filter (where ms.est_projete))[1],
      min(ms.k) as ordre
    from mois_soldes ms
    group by ms.an, (ms.mo - 1) / 3 + 1
  ),
  toutes as (
    select * from lignes_mois
    union all
    select * from lignes_trimestre
  )
  select
    t.g, t.an, t.per, t.st, t.pr, t.nb,
    t.enc_budget, t.enc_creances, t.enc, t.dep, t.res,
    t.sd, t.sf,
    case when t.pr then t.sf < 0 end,
    t.enc_sim, t.dep_sim, t.res_sim,
    t.sd_sim, t.sf_sim,
    case when t.pr then t.sf_sim < 0 end,
    t.sf_sim - t.sf
  from toutes t
  order by case t.g when 'mois' then 1 else 2 end, t.ordre;
end;
$$;

comment on function public.cashflow_previsionnel(date, jsonb, jsonb) is
  'Cashflow prévisionnel sur 12 mois (et trimestres civils) à partir de solde_caisse_a, des budgets (v_budget_mensuel_totaux, v_lignes_revenu_facturation) et des créances attendues (creances_situation), avec la simulation (reports de dépenses, retards de paiement) côte à côte. Projection arrêtée au premier mois sans budget. CEO uniquement : zéro ligne pour tout autre appelant. Fonction stable : n''écrit jamais.';

revoke all on function public.cashflow_previsionnel(date, jsonb, jsonb) from public;
revoke execute on function public.cashflow_previsionnel(date, jsonb, jsonb) from anon;
grant execute on function public.cashflow_previsionnel(date, jsonb, jsonb) to authenticated;
