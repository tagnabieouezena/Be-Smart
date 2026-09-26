-- Module 4.4 — Journal des transactions réelles.
-- Voir docs/briefs/module-4.4-journal-transactions.md.

-- =========================================================================
-- 1. Table transactions
-- =========================================================================

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references public.entreprises (id) on delete cascade,
  date date not null,
  description text not null,
  categorie_id uuid not null references public.categories (id),
  type text not null check (type in ('entree', 'sortie')),
  montant numeric not null check (montant > 0),
  mode_paiement text not null check (mode_paiement in ('cash', 'mobile_money', 'virement', 'cheque')),
  saisi_par uuid not null references public.utilisateurs (id),
  notes text,
  ligne_revenu_prevu_id uuid references public.lignes_revenu_prevu (id),
  justificatif_path text,
  created_at timestamptz not null default now()
);

comment on table public.transactions is
  'Journal des transactions réelles (entrées/sorties). Aucune update/delete en V1 — une correction est une nouvelle transaction, pas une retouche (intégrité comptable).';
comment on column public.transactions.saisi_par is
  'Forcé côté serveur par trigger (voir avant_insertion_transaction) — jamais confié à la valeur envoyée par le client.';

create index transactions_entreprise_id_idx on public.transactions (entreprise_id);
create index transactions_date_idx on public.transactions (entreprise_id, date);
create index transactions_saisi_par_idx on public.transactions (saisi_par);

-- Pas d'update/delete dans les GRANT : personne ne peut modifier/supprimer
-- une transaction, à aucun rôle (cf. brief — sobriété fonctionnelle et
-- intégrité comptable). Posés par cohérence/anticipation même si ce module
-- n'a pas encore de route service_role identifiée (leçon Module 4.1).
grant select, insert on public.transactions to authenticated;
grant select, insert, update, delete on public.transactions to service_role;

alter table public.transactions enable row level security;

-- Décision Ouezz : lecture élargie à toute l'entreprise (comptable ET CEO),
-- pas restreinte à l'auteur de la saisie — historique cohérent si plusieurs
-- comptables se succèdent, malgré la formulation CDC 3.2 ("ses propres saisies").
create policy "isolation_entreprise_lecture_transactions"
  on public.transactions
  for select
  using (entreprise_id = public.current_entreprise_id());

-- Seul le comptable écrit (le CEO consulte, ne saisit pas — CDC 3.1/3.2).
-- saisi_par n'a pas besoin d'être vérifié ici : le trigger BEFORE INSERT
-- ci-dessous l'a déjà forcé à auth.uid() avant que ce `with check` s'évalue.
create policy "comptable_creation_transactions"
  on public.transactions
  for insert
  with check (
    entreprise_id = public.current_entreprise_id()
    and public.current_role_utilisateur() = 'comptable'
  );

-- =========================================================================
-- 2. Garde-fous trigger (BEFORE INSERT) — cohérence + saisi_par forcé
-- =========================================================================

create or replace function public.avant_insertion_transaction()
returns trigger
language plpgsql
as $$
declare
  v_categorie_entreprise_id uuid;
  v_categorie_type text;
  v_ligne_entreprise_id uuid;
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
    select entreprise_id into v_ligne_entreprise_id
    from public.lignes_revenu_prevu where id = new.ligne_revenu_prevu_id;

    if v_ligne_entreprise_id is null or v_ligne_entreprise_id <> new.entreprise_id then
      raise exception 'La ligne de revenu prévu référencée n''appartient pas à la même entreprise que la transaction.';
    end if;
  end if;

  return new;
end;
$$;

create trigger avant_insertion_transaction
  before insert on public.transactions
  for each row execute function public.avant_insertion_transaction();

-- =========================================================================
-- 3. Rapprochement automatique (CDC 4.4)
-- =========================================================================

-- security definer : le comptable qui déclenche ce trigger n'a pas de
-- policy update sur lignes_revenu_prevu (CEO uniquement) — le rapprochement
-- automatique est une opération système, pas un acte de saisie du
-- comptable, elle doit donc s'exécuter avec des droits élevés, comme
-- current_entreprise_id()/current_role_utilisateur().
create or replace function public.rapprocher_ligne_revenu_prevu()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.ligne_revenu_prevu_id is not null then
    update public.lignes_revenu_prevu
    set statut = 'ok'
    where id = new.ligne_revenu_prevu_id
      and entreprise_id = new.entreprise_id; -- défensif, déjà garanti par le trigger ci-dessus
  end if;

  return new;
end;
$$;

create trigger rapprocher_ligne_revenu_prevu
  after insert on public.transactions
  for each row execute function public.rapprocher_ligne_revenu_prevu();

-- =========================================================================
-- 4. Storage — bucket justificatifs (privé)
-- =========================================================================

insert into storage.buckets (id, name, public)
values ('justificatifs', 'justificatifs', false)
on conflict (id) do nothing;

-- Convention de chemin : {entreprise_id}/{transaction_id}/{nom_fichier} —
-- storage.foldername(name) renvoie les segments du chemin, le premier est
-- l'entreprise_id, ce qui permet une policy simple basée dessus.
create policy "comptable_upload_justificatifs"
  on storage.objects
  for insert
  with check (
    bucket_id = 'justificatifs'
    and (storage.foldername(name))[1] = public.current_entreprise_id()::text
    and public.current_role_utilisateur() = 'comptable'
  );

create policy "entreprise_lecture_justificatifs"
  on storage.objects
  for select
  using (
    bucket_id = 'justificatifs'
    and (storage.foldername(name))[1] = public.current_entreprise_id()::text
  );
