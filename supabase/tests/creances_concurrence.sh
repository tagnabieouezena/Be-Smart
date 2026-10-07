#!/usr/bin/env bash
# Test adversarial 2 (Module 4.5) — paiements concurrents sur la même créance.
# Deux sessions psql distinctes, utilisateur authentifié réel (comptable),
# jamais service_role :
#   - session 1 : insère un paiement de 150 000 sur la créance (reste dû
#     200 000), puis garde sa transaction ouverte quelques secondes ;
#   - session 2 : tente le même paiement de 150 000 pendant ce temps.
# Attendu : la session 2 ATTEND le verrou de la créance, puis est rejetée
# (« dépasse le reste dû : 50000 FCFA ») une fois la session 1 commitée.
#
# Usage :
#   CI    : DB_URL=postgresql://... bash supabase/tests/creances_concurrence.sh
#   local : PSQL_CMD="docker exec -i supabase_db_Be_smart psql -U postgres -d postgres" \
#           bash supabase/tests/creances_concurrence.sh

set -u

if [ -n "${PSQL_CMD:-}" ]; then
  psqlc() { $PSQL_CMD -X -q "$@"; }
else
  : "${DB_URL:?DB_URL ou PSQL_CMD requis}"
  psqlc() { psql "$DB_URL" -X -q "$@"; }
fi

ENT='f0000000-0000-0000-0000-0000000000c0'
COMPTABLE='f1000000-0000-0000-0000-0000000000c9'
CATEGORIE='f2000000-0000-0000-0000-0000000000c9'
CREANCE='f8000000-0000-0000-0000-0000000000c9'
CLAIMS="{\"sub\": \"$COMPTABLE\", \"role\": \"authenticated\"}"
TMP="$(mktemp -d)"

nettoyer() {
  psqlc -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1
delete from public.transactions where entreprise_id = '$ENT';
delete from public.creances where entreprise_id = '$ENT';
delete from public.categories where entreprise_id = '$ENT';
delete from public.utilisateurs where entreprise_id = '$ENT';
delete from public.entreprises where id = '$ENT';
delete from auth.users where id = '$COMPTABLE';
SQL
  rm -rf "$TMP"
}
trap nettoyer EXIT
nettoyer >/dev/null 2>&1 || true
TMP="$(mktemp -d)"

echo "== Préparation (hors contexte JWT) : entreprise dédiée, comptable, créance de 300 000 déjà payée à hauteur de 100 000 (reste dû 200 000)"
psqlc -v ON_ERROR_STOP=1 <<SQL || { echo "ECHEC préparation"; exit 1; }
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
values ('00000000-0000-0000-0000-000000000000', '$COMPTABLE', 'authenticated', 'authenticated', 'comptable-concurrence@test.besmart.local',
        crypt('mot-de-passe-test', gen_salt('bf')), now(), '{}', '{}', now(), now(), '', '', '', '');
insert into public.entreprises (id, nom, secteur, devise, solde_initial) values ('$ENT', 'Entreprise Concurrence', 'Test', 'FCFA', 0);
insert into public.utilisateurs (id, nom, email, role, entreprise_id)
values ('$COMPTABLE', 'Comptable Concurrence', 'comptable-concurrence@test.besmart.local', 'comptable', '$ENT');
insert into public.categories (id, entreprise_id, libelle, type) values ('$CATEGORIE', '$ENT', 'Ventes', 'revenu');
insert into public.creances (id, entreprise_id, client, montant_du, date_facturation, echeance, saisi_par)
values ('$CREANCE', '$ENT', 'Client Concurrence', 300000, '2026-08-01', '2026-08-31', '$COMPTABLE');
insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, saisi_par, creance_id)
values ('$ENT', '2026-09-10', 'Acompte', '$CATEGORIE', 'entree', 100000, 'virement', '$COMPTABLE', '$CREANCE');
SQL

echo "== Session 1 : BEGIN, paiement de 150000, SANS COMMIT pendant 6 s, puis COMMIT"
(
  psqlc -v ON_ERROR_STOP=1 <<SQL
begin;
set local role authenticated;
set local request.jwt.claims = '$CLAIMS';
insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, creance_id)
values ('$ENT', '2026-10-15', 'Paiement session 1', '$CATEGORIE', 'entree', 150000, 'cash', '$CREANCE');
select 'session 1 : paiement de 150000 inséré, transaction ouverte (verrou de la créance tenu) à ' || clock_timestamp()::time as etat;
select pg_sleep(6);
commit;
select 'session 1 : COMMIT effectué à ' || clock_timestamp()::time as etat;
SQL
) >"$TMP/session1.txt" 2>&1 &
PID1=$!

# Laisse à la session 1 le temps de poser son verrou avant de lancer la 2.
sleep 2

echo "== Session 2 : tentative du même paiement de 150000 pendant que la session 1 tient le verrou"
DEBUT=$(date +%s)
(
  psqlc -v ON_ERROR_STOP=1 <<SQL
begin;
set local role authenticated;
set local request.jwt.claims = '$CLAIMS';
select 'session 2 : tentative lancée à ' || clock_timestamp()::time as etat;
insert into public.transactions (entreprise_id, date, description, categorie_id, type, montant, mode_paiement, creance_id)
values ('$ENT', '2026-10-15', 'Paiement session 2', '$CATEGORIE', 'entree', 150000, 'cash', '$CREANCE');
select 'session 2 : paiement ACCEPTE à ' || clock_timestamp()::time as etat;
commit;
SQL
) >"$TMP/session2.txt" 2>&1
CODE2=$?
FIN=$(date +%s)
DUREE=$((FIN - DEBUT))

wait "$PID1"
CODE1=$?

echo
echo "----- Sortie session 1 (code de sortie $CODE1) -----"
cat "$TMP/session1.txt"
echo "----- Sortie session 2 (code de sortie $CODE2, durée d'attente ${DUREE}s) -----"
cat "$TMP/session2.txt"
echo "-----------------------------------------------------"

ECHEC=0

if [ "$CODE1" -ne 0 ]; then echo "ECHEC : la session 1 aurait dû réussir"; ECHEC=1; fi
if [ "$CODE2" -eq 0 ]; then echo "ECHEC : la session 2 aurait dû être rejetée"; ECHEC=1; fi
if ! grep -q "dépasse le reste dû : 50000 FCFA" "$TMP/session2.txt"; then
  echo "ECHEC : la session 2 devait être rejetée avec « dépasse le reste dû : 50000 FCFA »"; ECHEC=1
fi
if [ "$DUREE" -lt 3 ]; then
  echo "ECHEC : la session 2 n'a attendu que ${DUREE}s — elle n'a pas été bloquée par le verrou de la session 1"; ECHEC=1
fi

TOTAL=$(psqlc -t -A -c "select sum(montant) from public.transactions where creance_id = '$CREANCE'")
NB=$(psqlc -t -A -c "select count(*) from public.transactions where creance_id = '$CREANCE'")
echo "Etat final en base : $NB paiement(s) liés, total encaissé = $TOTAL (attendu : 2 paiements, 250000 — l'acompte + la session 1 seulement)"
if [ "$TOTAL" != "250000" ] || [ "$NB" != "2" ]; then echo "ECHEC : état final incohérent"; ECHEC=1; fi

if [ "$ECHEC" -eq 0 ]; then
  echo "OK — paiements concurrents : la session 2 a attendu ${DUREE}s le verrou, puis a été rejetée (reste insuffisant) ; aucun surpaiement"
  exit 0
fi
exit 1
