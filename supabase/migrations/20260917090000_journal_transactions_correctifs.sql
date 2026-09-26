-- Module 4.4 — Correctifs revue Ouezz (avant merge PR #5).
-- Voir docs/briefs/module-4.4-journal-transactions.md.
-- Ne modifie pas la migration 20260916141223_journal_transactions.sql :
-- ajoute une contrainte et remplace les fonctions trigger existantes.

-- =========================================================================
-- 1. justificatif_path doit pointer vers le dossier de SA PROPRE
--    transaction (entreprise_id/id/...), jamais celui d'une autre —
--    incohérence de traçabilité sur une donnée qui sert de preuve, même
--    si ce n'est pas une fuite cross-tenant (la lecture Storage reste
--    scopée par entreprise).
-- =========================================================================

alter table public.transactions
  add constraint transactions_justificatif_path_coherent
  check (
    justificatif_path is null
    or justificatif_path like entreprise_id::text || '/' || id::text || '/%'
  );

-- =========================================================================
-- 2. Une ligne_revenu_prevu 'annulee' ne doit pas pouvoir être rapprochée
--    (le rapprochement automatique, en security definer, la repasserait
--    à 'ok'). Le formulaire ne propose que les lignes 'en_attente', mais
--    le SQL doit l'imposer, pas seulement l'UI.
-- =========================================================================

create or replace function public.avant_insertion_transaction()
returns trigger
language plpgsql
as $$
declare
  v_categorie_entreprise_id uuid;
  v_categorie_type text;
  v_ligne_entreprise_id uuid;
  v_ligne_statut text;
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

  return new;
end;
$$;
