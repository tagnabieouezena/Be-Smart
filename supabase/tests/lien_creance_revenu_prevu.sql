-- Tests du prérequis « Lien créance ↔ revenu prévu » (Module 4.9).
-- Voir docs/briefs/Lien-Creance-Revenu-Prevu.md.
--
-- Deux entreprises dédiées : Lien1 (d...) pour les 12 tests numérotés et la
-- plupart des adversariaux, Lien2 (e...) pour l'isolation (A1, A3, A6).
-- Chaque test numéroté part de l'état initial : savepoint puis rollback to
-- savepoint. Les attendus ont été recalculés par un modèle de référence
-- indépendant du SQL (script Python écrit à partir des seules règles du
-- brief) ; voir le corps de la PR pour la comparaison.

set client_min_messages to notice;

-- =========================================================================
-- Jeu de données commun
-- =========================================================================
-- État initial, Lien1 :
--   L1 avril Ventes          250000 en_attente  <- C1 100000, C2 60000
--   L2 avril Client Alpha    200000 en_attente  <- C3 200000
--   L3 avril Contrat Beta    300000 ok           <- C4 350000 (dépassement)
--   L4 avril Vente annulée    80000 annule       <- C5  50000 (lien inerte)
--   L5 avril Divers           40000 en_attente  <- (aucune)
--   L6 mai   Ventes          120000 en_attente  <- C6 120000 (sera soldée)
--   L7 mai   Prestations      75000 en_attente  <- C7  30000 (10000 payés)
--   C8 40000, sans lien.
-- Lien2 : M1 (budget mai) 100000 en_attente <- D1 50000.
create function pg_temp.setup_lien() returns void
language plpgsql as $$
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, email_change,
    email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated',
     'comptable-g@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-0000000000c2', 'authenticated', 'authenticated',
     'ceo-g@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', 'e1000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated',
     'comptable-h@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', 'e1000000-0000-0000-0000-0000000000c2', 'authenticated', 'authenticated',
     'ceo-h@test.besmart.local', crypt('mot-de-passe-test', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', '');

  insert into public.entreprises (id, nom, secteur, devise, solde_initial) values
    ('d0000000-0000-0000-0000-000000000001', 'Entreprise Lien1', 'Test', 'FCFA', 0),
    ('e0000000-0000-0000-0000-000000000001', 'Entreprise Lien2', 'Test', 'FCFA', 0);

  insert into public.utilisateurs (id, nom, email, role, entreprise_id) values
    ('d1000000-0000-0000-0000-0000000000c1', 'Comptable Lien1', 'comptable-g@test.besmart.local', 'comptable', 'd0000000-0000-0000-0000-000000000001'),
    ('d1000000-0000-0000-0000-0000000000c2', 'CEO Lien1', 'ceo-g@test.besmart.local', 'ceo', 'd0000000-0000-0000-0000-000000000001'),
    ('e1000000-0000-0000-0000-0000000000c1', 'Comptable Lien2', 'comptable-h@test.besmart.local', 'comptable', 'e0000000-0000-0000-0000-000000000001'),
    ('e1000000-0000-0000-0000-0000000000c2', 'CEO Lien2', 'ceo-h@test.besmart.local', 'ceo', 'e0000000-0000-0000-0000-000000000001');

  insert into public.categories (id, entreprise_id, libelle, type) values
    ('d2000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Ventes', 'revenu');

  insert into public.budgets_mensuels (id, entreprise_id, mois, annee, statut) values
    ('d4000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 4, 2026, 'brouillon'),
    ('d4000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', 5, 2026, 'brouillon'),
    ('e4000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 5, 2026, 'brouillon');

  insert into public.lignes_revenu_prevu (id, budget_mensuel_id, entreprise_id, source, montant_estime, statut) values
    ('d6000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Ventes', 250000, 'en_attente'),
    ('d6000000-0000-0000-0000-000000000002', 'd4000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Client Alpha', 200000, 'en_attente'),
    ('d6000000-0000-0000-0000-000000000003', 'd4000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Contrat Beta', 300000, 'ok'),
    ('d6000000-0000-0000-0000-000000000004', 'd4000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Vente annulée', 80000, 'en_attente'),
    ('d6000000-0000-0000-0000-000000000005', 'd4000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Divers', 40000, 'en_attente'),
    ('d6000000-0000-0000-0000-000000000006', 'd4000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', 'Ventes', 120000, 'en_attente'),
    ('d6000000-0000-0000-0000-000000000007', 'd4000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', 'Prestations', 75000, 'en_attente'),
    ('e6000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Ventes', 100000, 'en_attente');

  insert into public.creances (id, entreprise_id, client, montant_du, date_facturation, echeance, saisi_par, ligne_revenu_prevu_id) values
    ('d8000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Client C1', 100000, '2026-04-01', '2026-04-30', 'd1000000-0000-0000-0000-0000000000c1', 'd6000000-0000-0000-0000-000000000001'),
    ('d8000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', 'Client C2',  60000, '2026-04-01', '2026-04-30', 'd1000000-0000-0000-0000-0000000000c1', 'd6000000-0000-0000-0000-000000000001'),
    ('d8000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001', 'Client C3', 200000, '2026-04-01', '2026-04-30', 'd1000000-0000-0000-0000-0000000000c1', 'd6000000-0000-0000-0000-000000000002'),
    ('d8000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000001', 'Client C4', 350000, '2026-04-01', '2026-04-30', 'd1000000-0000-0000-0000-0000000000c1', 'd6000000-0000-0000-0000-000000000003'),
    ('d8000000-0000-0000-0000-000000000005', 'd0000000-0000-0000-0000-000000000001', 'Client C5',  50000, '2026-04-01', '2026-04-30', 'd1000000-0000-0000-0000-0000000000c1', 'd6000000-0000-0000-0000-000000000004'),
    ('d8000000-0000-0000-0000-000000000006', 'd0000000-0000-0000-0000-000000000001', 'Client C6', 120000, '2026-05-01', '2026-05-31', 'd1000000-0000-0000-0000-0000000000c1', 'd6000000-0000-0000-0000-000000000006'),
    ('d8000000-0000-0000-0000-000000000007', 'd0000000-0000-0000-0000-000000000001', 'Client C7',  30000, '2026-05-01', '2026-05-31', 'd1000000-0000-0000-0000-0000000000c1', 'd6000000-0000-0000-0000-000000000007'),
    ('d8000000-0000-0000-0000-000000000008', 'd0000000-0000-0000-0000-000000000001', 'Client C8',  40000, '2026-04-01', '2026-04-30', 'd1000000-0000-0000-0000-0000000000c1', null),
    ('e8000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Client D1',  50000, '2026-05-01', '2026-05-31', 'e1000000-0000-0000-0000-0000000000c1', 'e6000000-0000-0000-0000-000000000001');

  -- L4 n'est annulée qu'APRÈS le lien de C5 (le trigger ne refuse le lien
  -- qu'au moment où il est créé ou changé — cas « lien inerte », P4).
  update public.lignes_revenu_prevu set statut = 'annule' where id = 'd6000000-0000-0000-0000-000000000004';

  -- Solder C6 (120000) et payer partiellement C7 (10000 sur 30000).
  insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par, creance_id) values
    ('d0000000-0000-0000-0000-000000000001', '2026-05-10', 'Paiement C6', 'd2000000-0000-0000-0000-000000000001', 'entree', 120000, 'virement', 'd1000000-0000-0000-0000-0000000000c1', 'd8000000-0000-0000-0000-000000000006'),
    ('d0000000-0000-0000-0000-000000000001', '2026-05-10', 'Paiement partiel C7', 'd2000000-0000-0000-0000-000000000001', 'entree', 10000, 'cash', 'd1000000-0000-0000-0000-0000000000c1', 'd8000000-0000-0000-0000-000000000007');
end;
$$;

begin;

select pg_temp.setup_lien();

-- Contexte par défaut : comptable Lien1. Chaque test qui a besoin d'un
-- autre acteur change de rôle APRÈS son savepoint, ce qui annule le
-- changement au `rollback to savepoint` suivant (SET LOCAL est annulé par un
-- rollback à un savepoint antérieur).
set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

-- =========================================================================
-- Test 1 — état initial
-- =========================================================================
savepoint sp;
do $$
declare
  v_attendu record;
  v_obtenu record;
begin
  for v_attendu in
    select * from (values
      ('L1'::text, 'd6000000-0000-0000-0000-000000000001'::uuid, 2::int, 160000::numeric, 90000::numeric),
      ('L2', 'd6000000-0000-0000-0000-000000000002', 1, 200000::numeric, 0::numeric),
      ('L3', 'd6000000-0000-0000-0000-000000000003', 1, 350000, 0),
      ('L5', 'd6000000-0000-0000-0000-000000000005', 0, 0, 40000),
      ('L6', 'd6000000-0000-0000-0000-000000000006', 1, 120000, 0),
      ('L7', 'd6000000-0000-0000-0000-000000000007', 1, 30000, 45000)
    ) as t(label, id, nb, facture, reste)
  loop
    select nb_creances, montant_facture, reste_a_facturer into v_obtenu
    from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = v_attendu.id;

    raise notice 'TEST1 % : nb attendu % obtenu % ; facturé attendu % obtenu % ; reste attendu % obtenu %',
      v_attendu.label, v_attendu.nb, v_obtenu.nb_creances, v_attendu.facture, v_obtenu.montant_facture, v_attendu.reste, v_obtenu.reste_a_facturer;

    if v_obtenu.nb_creances is distinct from v_attendu.nb
       or v_obtenu.montant_facture is distinct from v_attendu.facture
       or v_obtenu.reste_a_facturer is distinct from v_attendu.reste then
      raise exception 'TEST1 % : écart (voir notice ci-dessus)', v_attendu.label;
    end if;
  end loop;

  if exists (select 1 from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000004') then
    raise exception 'TEST1 : L4 (annulée) ne devrait pas apparaître dans la vue';
  end if;

  if (select count(*) from public.v_lignes_revenu_facturation where entreprise_id = 'd0000000-0000-0000-0000-000000000001') <> 6 then
    raise exception 'TEST1 : la vue devrait avoir 6 lignes pour Lien1 (L4 exclue)';
  end if;

  if (select total_ca_previsionnel from public.v_budget_mensuel_totaux where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 790000 then
    raise exception 'TEST1 : CA prévisionnel avril attendu 790000';
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 130000 then
    raise exception 'TEST1 : reste à facturer avril attendu 130000';
  end if;
  if (select total_ca_previsionnel from public.v_budget_mensuel_totaux where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000002') <> 195000 then
    raise exception 'TEST1 : CA prévisionnel mai attendu 195000';
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000002') <> 45000 then
    raise exception 'TEST1 : reste à facturer mai attendu 45000';
  end if;

  raise notice 'OK — test 1 : état initial conforme (6 lignes, L4 absente, recoupements avril 790000/130000 et mai 195000/45000)';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 2 — C7 soldée (paiement de 20000, comptable) : vue inchangée
-- =========================================================================
savepoint sp;
insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, creance_id) values
  ('d0000000-0000-0000-0000-000000000001', '2026-05-20', 'Solde C7', 'd2000000-0000-0000-0000-000000000001', 'entree', 20000, 'cash', 'd8000000-0000-0000-0000-000000000007');
do $$
declare v_obtenu record; v_statut text; v_reste numeric;
begin
  select nb_creances, montant_facture, reste_a_facturer into v_obtenu
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000007';
  if v_obtenu.nb_creances <> 1 or v_obtenu.montant_facture <> 30000 or v_obtenu.reste_a_facturer <> 45000 then
    raise exception 'TEST2 : L7 devrait rester nb=1 facture=30000 reste=45000 (obtenu nb=%, facture=%, reste=%)',
      v_obtenu.nb_creances, v_obtenu.montant_facture, v_obtenu.reste_a_facturer;
  end if;

  select statut, reste_du into v_statut, v_reste from public.creances_situation() where id = 'd8000000-0000-0000-0000-000000000007';
  if v_statut <> 'paye' or v_reste <> 0 then
    raise exception 'TEST2 : C7 devrait être payée (reste 0), obtenu statut=%, reste=%', v_statut, v_reste;
  end if;

  raise notice 'OK — test 2 : C7 soldée ne change rien à la consommation (facture = montant dû, pas le reste dû)';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 3 — C1 : montant dû 100000 -> 120000 (comptable)
-- =========================================================================
savepoint sp;
update public.creances set montant_du = 120000 where id = 'd8000000-0000-0000-0000-000000000001';
do $$
declare v_obtenu record;
begin
  select nb_creances, montant_facture, reste_a_facturer into v_obtenu
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000001';
  if v_obtenu.nb_creances <> 2 or v_obtenu.montant_facture <> 180000 or v_obtenu.reste_a_facturer <> 70000 then
    raise exception 'TEST3 : L1 devrait être nb=2 facture=180000 reste=70000 (obtenu nb=%, facture=%, reste=%)',
      v_obtenu.nb_creances, v_obtenu.montant_facture, v_obtenu.reste_a_facturer;
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 110000 then
    raise exception 'TEST3 : reste à facturer avril attendu 110000';
  end if;
  raise notice 'OK — test 3 : C1 à 120000, L1 facturé 180000 reste 70000, avril 110000';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 4 — C2 déplacée de L1 vers L5 (comptable)
-- =========================================================================
savepoint sp;
update public.creances set ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000005' where id = 'd8000000-0000-0000-0000-000000000002';
do $$
declare v_l1 record; v_l5 record;
begin
  select nb_creances, montant_facture, reste_a_facturer into v_l1
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000001';
  select nb_creances, montant_facture, reste_a_facturer into v_l5
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000005';

  if v_l1.nb_creances <> 1 or v_l1.montant_facture <> 100000 or v_l1.reste_a_facturer <> 150000 then
    raise exception 'TEST4 : L1 devrait être nb=1 facture=100000 reste=150000 (obtenu nb=%, facture=%, reste=%)',
      v_l1.nb_creances, v_l1.montant_facture, v_l1.reste_a_facturer;
  end if;
  if v_l5.nb_creances <> 1 or v_l5.montant_facture <> 60000 or v_l5.reste_a_facturer <> 0 then
    raise exception 'TEST4 : L5 devrait être nb=1 facture=60000 reste=0 (obtenu nb=%, facture=%, reste=%)',
      v_l5.nb_creances, v_l5.montant_facture, v_l5.reste_a_facturer;
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 150000 then
    raise exception 'TEST4 : reste à facturer avril attendu 150000';
  end if;
  raise notice 'OK — test 4 : C2 déplacée vers L5, L1 reste 150000, L5 reste 0, avril 150000';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 5 — lien de C1 retiré (comptable) : C1 existe toujours
-- =========================================================================
savepoint sp;
update public.creances set ligne_revenu_prevu_id = null where id = 'd8000000-0000-0000-0000-000000000001';
do $$
declare v_l1 record; v_existe boolean;
begin
  select nb_creances, montant_facture, reste_a_facturer into v_l1
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000001';
  if v_l1.nb_creances <> 1 or v_l1.montant_facture <> 60000 or v_l1.reste_a_facturer <> 190000 then
    raise exception 'TEST5 : L1 devrait être nb=1 facture=60000 reste=190000 (obtenu nb=%, facture=%, reste=%)',
      v_l1.nb_creances, v_l1.montant_facture, v_l1.reste_a_facturer;
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 230000 then
    raise exception 'TEST5 : reste à facturer avril attendu 230000';
  end if;
  select exists(select 1 from public.creances where id = 'd8000000-0000-0000-0000-000000000001') into v_existe;
  if not v_existe then
    raise exception 'TEST5 : C1 doit toujours exister après le retrait de son lien';
  end if;
  raise notice 'OK — test 5 : lien de C1 retiré, L1 reste 190000, avril 230000, C1 existe toujours';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 6 — L1 : montant 250000 -> 150000 (CEO)
-- =========================================================================
savepoint sp;
set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';
update public.lignes_revenu_prevu set montant_estime = 150000 where id = 'd6000000-0000-0000-0000-000000000001';
do $$
declare v_l1 record;
begin
  select nb_creances, montant_facture, reste_a_facturer into v_l1
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000001';
  if v_l1.nb_creances <> 2 or v_l1.montant_facture <> 160000 or v_l1.reste_a_facturer <> 0 then
    raise exception 'TEST6 : L1 devrait être nb=2 facture=160000 reste=0 (jamais négatif) (obtenu nb=%, facture=%, reste=%)',
      v_l1.nb_creances, v_l1.montant_facture, v_l1.reste_a_facturer;
  end if;
  if (select total_ca_previsionnel from public.v_budget_mensuel_totaux where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 690000 then
    raise exception 'TEST6 : CA prévisionnel avril attendu 690000';
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 40000 then
    raise exception 'TEST6 : reste à facturer avril attendu 40000';
  end if;
  raise notice 'OK — test 6 : L1 à 150000, reste à facturer plafonné à 0 (jamais -10000), avril 690000/40000';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 7 — L1 annulée (CEO) ; notes de C1 modifiées (comptable, accepté) ;
--          lien de C8 vers L1 (comptable, refusé : ligne annulée)
-- =========================================================================
savepoint sp;
set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';
update public.lignes_revenu_prevu set statut = 'annule' where id = 'd6000000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';
update public.creances set notes = 'Note après annulation de L1' where id = 'd8000000-0000-0000-0000-000000000001';

do $$
declare v_notes text; v_lien uuid;
begin
  if exists (select 1 from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000001') then
    raise exception 'TEST7 : L1 annulée ne devrait plus apparaître dans la vue';
  end if;
  if (select total_ca_previsionnel from public.v_budget_mensuel_totaux where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 540000 then
    raise exception 'TEST7 : CA prévisionnel avril attendu 540000';
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 40000 then
    raise exception 'TEST7 : reste à facturer avril attendu 40000';
  end if;

  select notes, ligne_revenu_prevu_id into v_notes, v_lien from public.creances where id = 'd8000000-0000-0000-0000-000000000001';
  if v_notes <> 'Note après annulation de L1' or v_lien <> 'd6000000-0000-0000-0000-000000000001' then
    raise exception 'TEST7 : la modification des notes de C1 (lien inchangé) aurait dû être acceptée';
  end if;

  begin
    update public.creances set ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000001' where id = 'd8000000-0000-0000-0000-000000000008';
    raise exception 'GARDE-FOU ROMPU : C8 a pu être liée à L1 malgré son statut non actif';
  exception
    when others then
      if sqlerrm not like '%annulée%' then
        raise exception 'ECHEC INATTENDU (lien vers ligne annulée) : %', sqlerrm;
      end if;
      raise notice 'TEST7 lien de C8 vers L1 (annulée) : rejeté — "%"', sqlerrm;
  end;

  raise notice 'OK — test 7 : L1 annulée sort de la vue (avril 540000/40000) ; notes de C1 modifiables ; nouveau lien vers L1 refusé';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 8 — L4 remise en_attente (CEO) : le lien de C5 redevient actif
-- =========================================================================
savepoint sp;
set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';
update public.lignes_revenu_prevu set statut = 'en_attente' where id = 'd6000000-0000-0000-0000-000000000004';
do $$
declare v_l4 record;
begin
  select nb_creances, montant_facture, reste_a_facturer into v_l4
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000004';
  if v_l4.nb_creances <> 1 or v_l4.montant_facture <> 50000 or v_l4.reste_a_facturer <> 30000 then
    raise exception 'TEST8 : L4 réactivée devrait être nb=1 facture=50000 reste=30000 (obtenu nb=%, facture=%, reste=%)',
      v_l4.nb_creances, v_l4.montant_facture, v_l4.reste_a_facturer;
  end if;
  if (select total_ca_previsionnel from public.v_budget_mensuel_totaux where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 870000 then
    raise exception 'TEST8 : CA prévisionnel avril attendu 870000';
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 160000 then
    raise exception 'TEST8 : reste à facturer avril attendu 160000';
  end if;
  raise notice 'OK — test 8 : L4 réactivée, lien de C5 redevient actif (rien n''était stocké), avril 870000/160000';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 9 — L6 supprimée (CEO), alors que C6 est soldée
-- =========================================================================
savepoint sp;
set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';
do $$
declare v_rows int;
begin
  delete from public.lignes_revenu_prevu where id = 'd6000000-0000-0000-0000-000000000006';
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'TEST9 : la suppression de L6 par le CEO devrait affecter 1 ligne (obtenu %)', v_rows;
  end if;
end $$;
do $$
declare v_lien uuid; v_statut text; v_reste numeric;
begin
  select ligne_revenu_prevu_id into v_lien from public.creances where id = 'd8000000-0000-0000-0000-000000000006';
  if v_lien is not null then
    raise exception 'TEST9 : le lien de C6 devrait être NULL après suppression de L6 (obtenu %)', v_lien;
  end if;

  select statut, reste_du into v_statut, v_reste from public.creances_situation() where id = 'd8000000-0000-0000-0000-000000000006';
  if v_statut <> 'paye' or v_reste <> 0 then
    raise exception 'TEST9 : C6 devrait toujours exister, payée (reste 0) (obtenu statut=%, reste=%)', v_statut, v_reste;
  end if;

  if (select total_ca_previsionnel from public.v_budget_mensuel_totaux where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000002') <> 75000 then
    raise exception 'TEST9 : CA prévisionnel mai attendu 75000';
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000002') <> 45000 then
    raise exception 'TEST9 : reste à facturer mai attendu 45000';
  end if;

  raise notice 'OK — test 9 : L6 supprimée par le CEO (bien qu''il n''écrive jamais creances), lien de C6 vidé (on delete set null), C6 toujours payée, mai 75000/45000';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 10 — L1 supprimée (CEO)
-- =========================================================================
savepoint sp;
set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';
delete from public.lignes_revenu_prevu where id = 'd6000000-0000-0000-0000-000000000001';
do $$
declare v_lien1 uuid; v_lien2 uuid;
begin
  select ligne_revenu_prevu_id into v_lien1 from public.creances where id = 'd8000000-0000-0000-0000-000000000001';
  select ligne_revenu_prevu_id into v_lien2 from public.creances where id = 'd8000000-0000-0000-0000-000000000002';
  if v_lien1 is not null or v_lien2 is not null then
    raise exception 'TEST10 : les liens de C1 et C2 devraient être NULL après suppression de L1 (obtenu %, %)', v_lien1, v_lien2;
  end if;
  if not exists (select 1 from public.creances where id in ('d8000000-0000-0000-0000-000000000001', 'd8000000-0000-0000-0000-000000000002')) then
    raise exception 'TEST10 : C1 et C2 doivent toujours exister';
  end if;
  if (select total_ca_previsionnel from public.v_budget_mensuel_totaux where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 540000 then
    raise exception 'TEST10 : CA prévisionnel avril attendu 540000';
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 40000 then
    raise exception 'TEST10 : reste à facturer avril attendu 40000';
  end if;
  raise notice 'OK — test 10 : L1 supprimée, liens de C1 et C2 vidés (les deux créances existent toujours), avril 540000/40000';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 11 — C1 supprimée (comptable ; aucun paiement)
-- =========================================================================
savepoint sp;
delete from public.creances where id = 'd8000000-0000-0000-0000-000000000001';
do $$
declare v_l1 record;
begin
  select nb_creances, montant_facture, reste_a_facturer into v_l1
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000001';
  if v_l1.nb_creances <> 1 or v_l1.montant_facture <> 60000 or v_l1.reste_a_facturer <> 190000 then
    raise exception 'TEST11 : L1 devrait être nb=1 facture=60000 reste=190000 (obtenu nb=%, facture=%, reste=%)',
      v_l1.nb_creances, v_l1.montant_facture, v_l1.reste_a_facturer;
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 230000 then
    raise exception 'TEST11 : reste à facturer avril attendu 230000';
  end if;
  raise notice 'OK — test 11 : C1 supprimée (aucun paiement), L1 reste 190000, avril 230000';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- Test 12 — C9 (40000) créée liée à L5 (comptable, chemin INSERT)
-- =========================================================================
savepoint sp;
insert into public.creances (id, entreprise_id, client, montant_du, date_facturation, echeance, ligne_revenu_prevu_id) values
  ('d8000000-0000-0000-0000-000000000009', 'd0000000-0000-0000-0000-000000000001', 'Client C9', 40000, '2026-04-10', '2026-04-30', 'd6000000-0000-0000-0000-000000000005');
do $$
declare v_l5 record;
begin
  select nb_creances, montant_facture, reste_a_facturer into v_l5
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000005';
  if v_l5.nb_creances <> 1 or v_l5.montant_facture <> 40000 or v_l5.reste_a_facturer <> 0 then
    raise exception 'TEST12 : L5 devrait être nb=1 facture=40000 reste=0 exactement (obtenu nb=%, facture=%, reste=%)',
      v_l5.nb_creances, v_l5.montant_facture, v_l5.reste_a_facturer;
  end if;
  if (select sum(reste_a_facturer) from public.v_lignes_revenu_facturation where budget_mensuel_id = 'd4000000-0000-0000-0000-000000000001') <> 90000 then
    raise exception 'TEST12 : reste à facturer avril attendu 90000';
  end if;
  raise notice 'OK — test 12 : C9 créée liée à L5 (INSERT), reste 0 exactement, avril 90000';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- A1 — isolation en écriture : lier C8 à une ligne de Lien2 (refusé)
-- =========================================================================
savepoint sp;
do $$
begin
  begin
    update public.creances set ligne_revenu_prevu_id = 'e6000000-0000-0000-0000-000000000001' where id = 'd8000000-0000-0000-0000-000000000008';
    raise exception 'GARDE-FOU ROMPU : C8 (Lien1) a pu être liée à la ligne de Lien2';
  exception
    when others then
      if sqlerrm not like '%introuvable%' then
        raise exception 'ECHEC INATTENDU (A1) : %', sqlerrm;
      end if;
      raise notice 'A1 lien vers une ligne d''une autre entreprise : rejeté — "%"', sqlerrm;
  end;
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- A2 — identifiant inexistant : même message que A1
-- =========================================================================
savepoint sp;
do $$
begin
  begin
    update public.creances set ligne_revenu_prevu_id = '99999999-9999-9999-9999-999999999999' where id = 'd8000000-0000-0000-0000-000000000008';
    raise exception 'GARDE-FOU ROMPU : un identifiant inexistant a été accepté';
  exception
    when others then
      if sqlerrm not like '%introuvable%' then
        raise exception 'ECHEC INATTENDU (A2) : %', sqlerrm;
      end if;
      raise notice 'A2 identifiant inexistant : rejeté — "%"', sqlerrm;
  end;
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- A3 — le trigger, pas seulement la RLS (en postgres, sans RLS)
-- =========================================================================
savepoint sp;
reset role;
reset request.jwt.claims;
do $$
begin
  begin
    insert into public.creances (id, entreprise_id, client, montant_du, date_facturation, echeance, saisi_par, ligne_revenu_prevu_id) values
      ('d8000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-000000000001', 'Client A3', 10000, '2026-04-01', '2026-04-30', 'd1000000-0000-0000-0000-0000000000c1', 'e6000000-0000-0000-0000-000000000001');
    raise exception 'GARDE-FOU ROMPU : en postgres (sans RLS), une créance de Lien1 a pu être liée à une ligne de Lien2';
  exception
    when others then
      if sqlerrm not like '%introuvable%' then
        raise exception 'ECHEC INATTENDU (A3) : %', sqlerrm;
      end if;
      raise notice 'A3 lien cross-entreprise rejeté par le trigger, même sans RLS — "%"', sqlerrm;
  end;
end $$;
rollback to savepoint sp;
release savepoint sp;

set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

-- =========================================================================
-- A4 — le CEO ne lie ni ne délie (RLS : aucune écriture CEO sur creances)
-- =========================================================================
savepoint sp;
set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c2", "role": "authenticated"}';
update public.creances set ligne_revenu_prevu_id = null where id = 'd8000000-0000-0000-0000-000000000001';
do $$
declare v_lien uuid;
begin
  select ligne_revenu_prevu_id into v_lien from public.creances where id = 'd8000000-0000-0000-0000-000000000001';
  if v_lien is distinct from 'd6000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'A4 : le CEO a pu modifier le lien d''une créance (devrait être filtré par la RLS, 0 ligne)';
  end if;
  raise notice 'OK — A4 : le CEO ne peut modifier aucun lien (aucune écriture CEO sur creances)';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- A5 — le comptable n'écrit pas le budget (non-régression du 4.3)
-- =========================================================================
savepoint sp;
update public.lignes_revenu_prevu set montant_estime = 999999 where id = 'd6000000-0000-0000-0000-000000000001';
do $$
declare v_montant numeric;
begin
  select montant_estime into v_montant from public.lignes_revenu_prevu where id = 'd6000000-0000-0000-0000-000000000001';
  if v_montant <> 250000 then
    raise exception 'A5 : le comptable a pu modifier une ligne de CA prévisionnel (devrait être filtré par la RLS, 0 ligne)';
  end if;
  raise notice 'OK — A5 : le comptable ne peut pas écrire le budget (règle du 4.3 inchangée)';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- A6 — isolation en lecture de la vue
-- =========================================================================
savepoint sp;
do $$
declare v_nb int;
begin
  -- Lien1 (déjà le contexte par défaut) : 6 lignes.
  select count(*) into v_nb from public.v_lignes_revenu_facturation;
  if v_nb <> 6 then
    raise exception 'A6 : comptable Lien1 devrait voir 6 lignes (obtenu %)', v_nb;
  end if;
  raise notice 'OK — A6 (Lien1) : comptable Lien1 voit exactement ses 6 lignes';
end $$;
rollback to savepoint sp;
release savepoint sp;

savepoint sp;
set local role authenticated;
set local request.jwt.claims = '{"sub": "e1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';
do $$
declare v_obtenu record;
begin
  if (select count(*) from public.v_lignes_revenu_facturation) <> 1 then
    raise exception 'A6 : comptable Lien2 devrait voir exactement 1 ligne (la sienne)';
  end if;
  select nb_creances, montant_facture, reste_a_facturer into v_obtenu
  from public.v_lignes_revenu_facturation where ligne_revenu_prevu_id = 'e6000000-0000-0000-0000-000000000001';
  if v_obtenu.nb_creances <> 1 or v_obtenu.montant_facture <> 50000 or v_obtenu.reste_a_facturer <> 50000 then
    raise exception 'A6 : M1 (Lien2) devrait être nb=1 facture=50000 reste=50000 (obtenu nb=%, facture=%, reste=%)',
      v_obtenu.nb_creances, v_obtenu.montant_facture, v_obtenu.reste_a_facturer;
  end if;
  raise notice 'OK — A6 (Lien2) : comptable Lien2 ne voit que sa propre ligne, correctement calculée';
end $$;
rollback to savepoint sp;
release savepoint sp;

savepoint sp;
set local role authenticated;
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000001", "role": "authenticated", "app_metadata": {"super_admin": true}}';
do $$
begin
  if (select count(*) from public.v_lignes_revenu_facturation) <> 0 then
    raise exception 'A6 : la supervision Be Smart (super_admin) ne devrait voir aucune ligne';
  end if;
  raise notice 'OK — A6 (supervision) : super_admin ne voit aucune ligne';
end $$;
rollback to savepoint sp;
release savepoint sp;

savepoint sp;
set local role anon;
do $$
begin
  begin
    perform count(*) from public.v_lignes_revenu_facturation;
    raise exception 'GARDE-FOU ROMPU : anon a pu lire v_lignes_revenu_facturation';
  exception
    when insufficient_privilege then
      raise notice 'OK — A6 (anon) : permission refusée sur v_lignes_revenu_facturation';
  end;
end $$;
rollback to savepoint sp;
release savepoint sp;

set local role authenticated;
set local request.jwt.claims = '{"sub": "d1000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

-- =========================================================================
-- A7 — lien vers une ligne annulée, à la création comme en modification
-- =========================================================================
savepoint sp;
do $$
begin
  begin
    insert into public.creances (id, entreprise_id, client, montant_du, date_facturation, echeance, ligne_revenu_prevu_id) values
      ('d8000000-0000-0000-0000-00000000000b', 'd0000000-0000-0000-0000-000000000001', 'Client A7', 10000, '2026-04-01', '2026-04-30', 'd6000000-0000-0000-0000-000000000004');
    raise exception 'GARDE-FOU ROMPU : une créance a pu être créée liée à L4 malgré son statut non actif';
  exception
    when others then
      if sqlerrm not like '%annulée%' then
        raise exception 'ECHEC INATTENDU (A7, création) : %', sqlerrm;
      end if;
      raise notice 'A7 création liée à une ligne annulée : rejetée — "%"', sqlerrm;
  end;

  begin
    update public.creances set ligne_revenu_prevu_id = 'd6000000-0000-0000-0000-000000000004' where id = 'd8000000-0000-0000-0000-000000000008';
    raise exception 'GARDE-FOU ROMPU : C8 a pu être liée à L4 par UPDATE malgré son statut non actif';
  exception
    when others then
      if sqlerrm not like '%annulée%' then
        raise exception 'ECHEC INATTENDU (A7, modification) : %', sqlerrm;
      end if;
      raise notice 'A7 modification liée à une ligne annulée : rejetée — "%"', sqlerrm;
  end;

  raise notice 'OK — A7 : lien vers une ligne annulée toujours refusé (création et modification)';
end $$;
rollback to savepoint sp;
release savepoint sp;

-- =========================================================================
-- A8 — structure (indépendante des données ci-dessus)
-- =========================================================================
savepoint sp;
reset role;
reset request.jwt.claims;
do $$
declare
  v_options text[];
  v_confdeltype char;
  v_a_index boolean;
  v_tgtype int;
  v_nb_policies_creances int;
  v_nb_policies_lignes int;
begin
  -- Vue en security_invoker.
  select reloptions into v_options from pg_class where oid = 'public.v_lignes_revenu_facturation'::regclass;
  if not ('security_invoker=true' = any (coalesce(v_options, '{}'))) then
    raise exception 'A8 : v_lignes_revenu_facturation doit être security_invoker (options : %)', v_options;
  end if;

  -- Clé étrangère en ON DELETE SET NULL.
  select confdeltype into v_confdeltype
  from pg_constraint
  where conrelid = 'public.creances'::regclass and contype = 'f' and confrelid = 'public.lignes_revenu_prevu'::regclass;
  if v_confdeltype <> 'n' then
    raise exception 'A8 : la clé étrangère creances.ligne_revenu_prevu_id doit être ON DELETE SET NULL (obtenu %)', v_confdeltype;
  end if;

  -- Index partiel.
  select exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'creances' and indexname = 'creances_ligne_revenu_prevu_id_idx'
      and indexdef like '%WHERE%'
  ) into v_a_index;
  if not v_a_index then
    raise exception 'A8 : index partiel creances_ligne_revenu_prevu_id_idx introuvable';
  end if;

  -- Trigger BEFORE INSERT OR UPDATE, FOR EACH ROW.
  select tgtype into v_tgtype from pg_trigger
  where tgname = 'verifier_lien_creance_revenu_prevu' and tgrelid = 'public.creances'::regclass and not tgisinternal;
  if v_tgtype is null then
    raise exception 'A8 : trigger verifier_lien_creance_revenu_prevu introuvable';
  end if;
  if (v_tgtype & 2) = 0 or (v_tgtype & 4) = 0 or (v_tgtype & 16) = 0 or (v_tgtype & 1) = 0 then
    raise exception 'A8 : le trigger doit être BEFORE INSERT OR UPDATE FOR EACH ROW (tgtype=%)', v_tgtype;
  end if;

  -- La fonction du trigger n'est exécutable par aucun rôle applicatif.
  if has_function_privilege('anon', 'public.verifier_lien_creance_revenu_prevu()'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'public.verifier_lien_creance_revenu_prevu()'::regprocedure, 'execute')
     or has_function_privilege('service_role', 'public.verifier_lien_creance_revenu_prevu()'::regprocedure, 'execute') then
    raise exception 'A8 : verifier_lien_creance_revenu_prevu est exécutable par un rôle applicatif';
  end if;
  if exists (
    select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'public.verifier_lien_creance_revenu_prevu()'::regprocedure
      and a.grantee = 0 and a.privilege_type = 'EXECUTE'
  ) then
    raise exception 'A8 : verifier_lien_creance_revenu_prevu est exécutable par PUBLIC';
  end if;

  -- La vue : anon sans droit, authenticated avec SELECT.
  if has_table_privilege('anon', 'public.v_lignes_revenu_facturation', 'select') then
    raise exception 'A8 : anon peut lire v_lignes_revenu_facturation';
  end if;
  if not has_table_privilege('authenticated', 'public.v_lignes_revenu_facturation', 'select') then
    raise exception 'A8 : authenticated ne peut pas lire v_lignes_revenu_facturation';
  end if;

  -- Nombre de policies inchangé (aucune nouvelle policy, P1/P5 : aucune
  -- écriture CEO sur creances, aucune écriture comptable sur le budget).
  select count(*) into v_nb_policies_creances from pg_policies where schemaname = 'public' and tablename = 'creances';
  select count(*) into v_nb_policies_lignes from pg_policies where schemaname = 'public' and tablename = 'lignes_revenu_prevu';
  if v_nb_policies_creances <> 4 then
    raise exception 'A8 : creances devrait avoir exactement 4 policies (obtenu %)', v_nb_policies_creances;
  end if;
  if v_nb_policies_lignes <> 4 then
    raise exception 'A8 : lignes_revenu_prevu devrait avoir exactement 4 policies (obtenu %)', v_nb_policies_lignes;
  end if;

  raise notice 'OK — A8 : vue security_invoker, FK on delete set null, index partiel, trigger before insert/update, fonction sans EXECUTE pour aucun rôle ni PUBLIC, 4+4 policies inchangées';
end $$;
rollback to savepoint sp;
release savepoint sp;

rollback;
