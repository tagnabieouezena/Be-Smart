-- Module 4.5 — Suivi des créances clients.
-- Voir docs/briefs/Module-4.5-Creances-Clients.md.
--
-- Le statut et le montant encaissé ne sont jamais stockés : ils sont
-- calculés à partir des transactions liées (transactions.creance_id).

-- =========================================================================
-- 1. Table creances
-- =========================================================================

create table public.creances (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references public.entreprises (id) on delete cascade,
  client text not null check (length(trim(client)) > 0),
  montant_du numeric not null check (montant_du > 0),
  date_facturation date not null,
  echeance date not null,
  notes text,
  saisi_par uuid not null references public.utilisateurs (id),
  created_at timestamptz not null default now(),
  check (echeance >= date_facturation)
);

comment on table public.creances is
  'Créance client (montant dû à une échéance). Ni statut ni montant encaissé stockés : calculés depuis les transactions liées (creances_situation).';
comment on column public.creances.saisi_par is
  'Forcé côté serveur par trigger (avant_insertion_creance) — jamais confié à la valeur envoyée par le client.';

create index creances_entreprise_echeance_idx on public.creances (entreprise_id, echeance);

grant select, insert, update, delete on public.creances to authenticated;
grant select, insert, update, delete on public.creances to service_role;

alter table public.creances enable row level security;

-- Lecture : toute l'entreprise (comptable ET CEO). La supervision Be Smart
-- n'a aucune policy : current_entreprise_id() est NULL pour elle, donc zéro ligne.
create policy "isolation_entreprise_lecture_creances"
  on public.creances
  for select
  using (entreprise_id = public.current_entreprise_id());

-- Écriture : comptable uniquement (le CEO consulte, CDC 4.5).
create policy "comptable_creation_creances"
  on public.creances
  for insert
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'comptable'
  );

create policy "comptable_modification_creances"
  on public.creances
  for update
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'comptable'
  )
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'comptable'
  );

create policy "comptable_suppression_creances"
  on public.creances
  for delete
  using (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'comptable'
  );

-- saisi_par : toujours l'appelant réel quand il y en a un (session
-- authentifiée). Hors contexte JWT (seed, service_role), auth.uid() est NULL :
-- la valeur fournie est conservée (même pattern que transactions, Module 4.4).
create or replace function public.avant_insertion_creance()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null then
    new.saisi_par := auth.uid();
  end if;

  return new;
end;
$$;

create trigger avant_insertion_creance
  before insert on public.creances
  for each row execute function public.avant_insertion_creance();

-- Immuabilité de entreprise_id et saisi_par ; montant_du ne peut pas
-- descendre sous l'encaissé. La ligne est déjà verrouillée par l'UPDATE en
-- cours, donc un paiement concurrent (qui verrouille la même ligne) est
-- sérialisé avec cette vérification.
create or replace function public.avant_modification_creance()
returns trigger
language plpgsql
as $$
declare
  v_encaisse numeric;
begin
  if new.entreprise_id <> old.entreprise_id then
    raise exception 'entreprise_id d''une créance est immuable.';
  end if;

  if new.saisi_par <> old.saisi_par then
    raise exception 'saisi_par d''une créance est immuable.';
  end if;

  select coalesce(sum(montant), 0) into v_encaisse
  from public.transactions where creance_id = new.id;

  if new.montant_du < v_encaisse then
    raise exception 'Le montant dû (%) ne peut pas être inférieur au montant déjà encaissé (%).', new.montant_du, v_encaisse;
  end if;

  return new;
end;
$$;

create trigger avant_modification_creance
  before update on public.creances
  for each row execute function public.avant_modification_creance();

-- =========================================================================
-- 2. Lien transactions.creance_id (encaissement = transaction d'entrée liée)
-- =========================================================================

alter table public.transactions
  add column creance_id uuid references public.creances (id) on delete restrict;

comment on column public.transactions.creance_id is
  'Créance encaissée (totalement ou partiellement) par cette transaction d''entrée. Plusieurs transactions peuvent viser la même créance.';

create index transactions_creance_id_idx on public.transactions (creance_id) where creance_id is not null;

-- Trigger BEFORE INSERT existant étendu (pas de second trigger) : reprend
-- à l'identique la version du correctif 4.4 et ajoute le bloc créance.
create or replace function public.avant_insertion_transaction()
returns trigger
language plpgsql
as $$
declare
  v_categorie_entreprise_id uuid;
  v_categorie_type text;
  v_ligne_entreprise_id uuid;
  v_ligne_statut text;
  v_creance_entreprise_id uuid;
  v_creance_montant_du numeric;
  v_deja_encaisse numeric;
  v_reste_du numeric;
begin
  -- saisi_par n'est jamais celui envoyé par le client : toujours l'appelant
  -- réel, quand il y en a un (session authentifiée). Hors contexte JWT
  -- (seed, script service_role direct), auth.uid() est NULL : on laisse
  -- alors la valeur fournie telle quelle, sinon aucun script serveur ne
  -- pourrait jamais seeder de transactions.
  if auth.uid() is not null then
    new.saisi_par := auth.uid();
  end if;

  select entreprise_id, type into v_categorie_entreprise_id, v_categorie_type
  from public.categories where id = new.categorie_id;

  if v_categorie_entreprise_id is null or v_categorie_entreprise_id <> new.entreprise_id then
    raise exception 'La catégorie référencée n''appartient pas à la même entreprise que la transaction.';
  end if;

  if new.type = 'entree' and v_categorie_type <> 'revenu' then
    raise exception 'Une transaction de type entree doit être rattachée à une catégorie de type revenu.';
  end if;

  if new.type = 'sortie' and v_categorie_type not in ('fixe', 'variable') then
    raise exception 'Une transaction de type sortie doit être rattachée à une catégorie fixe ou variable.';
  end if;

  if new.ligne_revenu_prevu_id is not null then
    select entreprise_id, statut into v_ligne_entreprise_id, v_ligne_statut
    from public.lignes_revenu_prevu where id = new.ligne_revenu_prevu_id;

    if v_ligne_entreprise_id is null or v_ligne_entreprise_id <> new.entreprise_id then
      raise exception 'La ligne de revenu prévu référencée n''appartient pas à la même entreprise que la transaction.';
    end if;

    if v_ligne_statut <> 'en_attente' then
      raise exception 'La ligne de revenu prévu référencée n''est pas en attente (statut=%).', v_ligne_statut;
    end if;
  end if;

  if new.creance_id is not null then
    if new.type <> 'entree' then
      raise exception 'Une transaction liée à une créance doit être de type entree.';
    end if;

    -- Verrou de la ligne de créance AVANT de calculer le reste dû : un
    -- paiement concurrent attend ici, puis recalcule (nouveau snapshot en
    -- READ COMMITTED) sur l'état committé par le premier.
    select entreprise_id, montant_du into v_creance_entreprise_id, v_creance_montant_du
    from public.creances where id = new.creance_id
    for update;

    if v_creance_entreprise_id is null or v_creance_entreprise_id <> new.entreprise_id then
      raise exception 'La créance référencée n''appartient pas à la même entreprise que la transaction.';
    end if;

    select coalesce(sum(montant), 0) into v_deja_encaisse
    from public.transactions where creance_id = new.creance_id;

    v_reste_du := v_creance_montant_du - v_deja_encaisse;

    if new.montant > v_reste_du then
      raise exception 'Le paiement dépasse le reste dû : % FCFA', v_reste_du;
    end if;
  end if;

  return new;
end;
$$;

-- =========================================================================
-- 3. Fonctions de lecture — statut, reste dû, balance âgée (calculés)
-- =========================================================================

-- security invoker : les policies RLS s'appliquent à l'appelant. Zéro ligne
-- (pas d'erreur) pour tout appelant qui n'est ni CEO ni comptable d'une
-- entreprise, supervision Be Smart comprise.
create or replace function public.creances_situation(p_date_reference date default current_date)
returns table (
  id uuid,
  client text,
  montant_du numeric,
  date_facturation date,
  echeance date,
  notes text,
  saisi_par uuid,
  created_at timestamptz,
  montant_encaisse numeric,
  reste_du numeric,
  statut text,
  jours_retard int,
  tranche text
)
language sql
stable
security invoker
set search_path = public
as $$
with ent as (
  select public.current_entreprise_id() as entreprise_id
  where public.current_role_utilisateur() in ('ceo', 'comptable')
),
calc as (
  select
    c.id, c.client, c.montant_du, c.date_facturation, c.echeance, c.notes,
    c.saisi_par, c.created_at,
    coalesce(p.total, 0) as montant_encaisse,
    c.montant_du - coalesce(p.total, 0) as reste_du
  from ent
  join public.creances c on c.entreprise_id = ent.entreprise_id
  left join lateral (
    select sum(t.montant) as total
    from public.transactions t
    where t.creance_id = c.id
  ) p on true
)
select
  calc.id, calc.client, calc.montant_du, calc.date_facturation, calc.echeance, calc.notes,
  calc.saisi_par, calc.created_at,
  calc.montant_encaisse,
  calc.reste_du,
  -- Priorité : payé > en retard > partiellement payé > en attente.
  case
    when calc.reste_du = 0 then 'paye'
    when calc.echeance < p_date_reference then 'en_retard'
    when calc.montant_encaisse > 0 then 'partiellement_paye'
    else 'en_attente'
  end,
  case when calc.reste_du > 0 then greatest(p_date_reference - calc.echeance, 0) else 0 end,
  case
    when calc.reste_du = 0 then null
    when p_date_reference - calc.echeance <= 0 then 'non_echue'
    when p_date_reference - calc.echeance <= 30 then '1_30'
    when p_date_reference - calc.echeance <= 60 then '31_60'
    else 'plus_60'
  end
from calc
order by calc.echeance, calc.created_at;
$$;

comment on function public.creances_situation(date) is
  'Situation de chaque créance à une date de référence : encaissé, reste dû, statut, jours de retard, tranche d''âge. Tout est calculé depuis les transactions liées (numeric, jamais float). Zéro ligne hors CEO/comptable.';

-- Une seule règle de statut/tranche dans le produit : cette fonction lit
-- creances_situation. Lignes : ('total','en_cours'), ('tranche', <4 tranches>),
-- ('mois', 'AAAA-MM' d'échéance) ; montant = reste dû, en numeric.
create or replace function public.creances_balance_agee(p_date_reference date default current_date)
returns table (
  rubrique text,
  cle text,
  montant numeric
)
language sql
stable
security invoker
set search_path = public
as $$
with ent as (
  select 1 as ok
  where public.current_entreprise_id() is not null
    and public.current_role_utilisateur() in ('ceo', 'comptable')
),
sit as (
  select s.echeance, s.reste_du, s.tranche
  from public.creances_situation(p_date_reference) s
  where s.reste_du > 0
),
tranches(cle, ordre) as (
  values ('non_echue', 1), ('1_30', 2), ('31_60', 3), ('plus_60', 4)
),
lignes as (
  select 1 as grp, 0 as ordre, 'total'::text as rubrique, 'en_cours'::text as cle,
         coalesce((select sum(sit.reste_du) from sit), 0) as montant
  from ent
  union all
  select 2, t.ordre, 'tranche', t.cle,
         coalesce((select sum(sit.reste_du) from sit where sit.tranche = t.cle), 0)
  from ent cross join tranches t
  union all
  select 3, 0, 'mois', to_char(sit.echeance, 'YYYY-MM'), sum(sit.reste_du)
  from ent cross join sit
  group by to_char(sit.echeance, 'YYYY-MM')
)
select lignes.rubrique, lignes.cle, lignes.montant
from lignes
order by lignes.grp, lignes.ordre, lignes.cle;
$$;

comment on function public.creances_balance_agee(date) is
  'Total en cours, total par tranche d''âge (non_echue, 1_30, 31_60, plus_60) et ventilation du reste dû par mois d''échéance. Zéro ligne hors CEO/comptable.';

revoke all on function public.creances_situation(date) from public;
revoke execute on function public.creances_situation(date) from anon;
grant execute on function public.creances_situation(date) to authenticated;

revoke all on function public.creances_balance_agee(date) from public;
revoke execute on function public.creances_balance_agee(date) from anon;
grant execute on function public.creances_balance_agee(date) to authenticated;
