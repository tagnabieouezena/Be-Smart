import { notFound, redirect } from "next/navigation";
import { exigerRole } from "@/lib/acces";
import { createClient } from "@/lib/supabase/server";
import { formaterMontant } from "@/lib/format";
import { GestionCreances, type LigneCreance, type LigneDisponible, type LigneLabel } from "@/components/gestion-creances";

type LigneBalance = { rubrique: "total" | "tranche" | "mois"; cle: string; montant: number };

const STATUTS = ["en_attente", "partiellement_paye", "paye", "en_retard"] as const;

const LIBELLES_STATUT: Record<(typeof STATUTS)[number], string> = {
  en_attente: "En attente",
  partiellement_paye: "Partiellement payé",
  paye: "Payé",
  en_retard: "⚠ En retard",
};

const LIBELLES_TRANCHE: Record<string, string> = {
  non_echue: "Non échue",
  "1_30": "1 à 30 jours de retard",
  "31_60": "31 à 60 jours de retard",
  plus_60: "Plus de 60 jours de retard",
};

const NOMS_MOIS = [
  "Janvier",
  "Février",
  "Mars",
  "Avril",
  "Mai",
  "Juin",
  "Juillet",
  "Août",
  "Septembre",
  "Octobre",
  "Novembre",
  "Décembre",
];

const montant = formaterMontant;

function libelleMois(cle: string) {
  const [annee, mois] = cle.split("-");
  return `${NOMS_MOIS[Number(mois) - 1]} ${annee}`;
}


export default async function CreancesPage({
  searchParams,
}: {
  searchParams: Promise<{ statut?: string }>;
}) {
  await exigerRole(["ceo", "comptable"], "/creances");
  const params = await searchParams;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/connexion");
  }

  const { data: profil } = await supabase
    .from("utilisateurs")
    .select("role, entreprise_id")
    .eq("id", user.id)
    .single();

  // Contrôle côté serveur : CEO (lecture) et comptable (lecture + saisie) ;
  // les fonctions SQL renvoient de toute façon zéro ligne à tout autre rôle.
  if (!profil || (profil.role !== "ceo" && profil.role !== "comptable")) {
    notFound();
  }

  const estComptable = profil.role === "comptable";
  const statutFiltre = STATUTS.find((s) => s === params.statut);

  // Filtre appliqué dans la requête (pas en JS sur un tableau déjà chargé).
  let requeteSituation = supabase.rpc("creances_situation");
  if (statutFiltre) {
    requeteSituation = requeteSituation.eq("statut", statutFiltre);
  }

  // creances_situation() ne porte pas ligne_revenu_prevu_id (4.5 non
  // redéfinie, cf. brief du prérequis) : le lien est lu séparément sur
  // creances, puis fusionné par id.
  const [
    { data: situation, error: erreurSituation },
    { data: balance },
    { data: categories },
    { data: liens },
    { data: lignesTout },
    { data: disponibles },
  ] = await Promise.all([
    requeteSituation,
    supabase.rpc("creances_balance_agee"),
    estComptable
      ? supabase.from("categories").select("id, libelle, type")
      : Promise.resolve({ data: [] }),
    supabase.from("creances").select("id, ligne_revenu_prevu_id"),
    supabase.from("lignes_revenu_prevu").select("id, source, statut, budgets_mensuels(mois, annee)"),
    estComptable
      ? supabase
          .from("v_lignes_revenu_facturation")
          .select("ligne_revenu_prevu_id, annee, mois, source, reste_a_facturer")
      : Promise.resolve({ data: [] }),
  ]);

  const liensParId = new Map((liens ?? []).map((l) => [l.id as string, l.ligne_revenu_prevu_id as string | null]));
  const lignes = ((situation ?? []) as Omit<LigneCreance, "ligne_revenu_prevu_id">[]).map((l) => ({
    ...l,
    ligne_revenu_prevu_id: liensParId.get(l.id) ?? null,
  })) as LigneCreance[];
  const lignesBalance = (balance ?? []) as LigneBalance[];

  const lignesLabels: Record<string, LigneLabel> = {};
  for (const l of (lignesTout ?? []) as unknown as {
    id: string;
    source: string;
    statut: string;
    budgets_mensuels: { mois: number; annee: number } | null;
  }[]) {
    if (l.budgets_mensuels) {
      lignesLabels[l.id] = {
        source: l.source,
        statut: l.statut,
        mois: l.budgets_mensuels.mois,
        annee: l.budgets_mensuels.annee,
      };
    }
  }

  const lignesDisponibles = (disponibles ?? []) as LigneDisponible[];
  const totalEnCours = lignesBalance.find((l) => l.rubrique === "total")?.montant ?? 0;
  const tranches = lignesBalance.filter((l) => l.rubrique === "tranche");
  const parMois = lignesBalance.filter((l) => l.rubrique === "mois");

  return (
    <main className="page">
      <h1>Créances clients</h1>

      <section aria-label="Synthèse" style={{ margin: "var(--espace-4) 0" }}>
        <p>
          <strong>Total des créances en cours : {montant(totalEnCours)}</strong>
        </p>

        <div style={{ display: "flex", gap: "var(--espace-8)", flexWrap: "wrap" }}>
          <table>
            <caption style={{ textAlign: "left", fontWeight: 600, paddingBottom: "var(--espace-2)" }}>Balance âgée (reste dû)</caption>
            <tbody>
              {tranches.map((t) => (
                <tr key={t.cle}>
                  <th scope="row">{LIBELLES_TRANCHE[t.cle] ?? t.cle}</th>
                  <td className="num">{montant(t.montant)}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <table>
            <caption style={{ textAlign: "left", fontWeight: 600, paddingBottom: "var(--espace-2)" }}>Reste dû par mois d&apos;échéance</caption>
            <tbody>
              {parMois.length === 0 && (
                <tr>
                  <td>Aucun reste dû</td>
                </tr>
              )}
              {parMois.map((m) => (
                <tr key={m.cle}>
                  <th scope="row">{libelleMois(m.cle)}</th>
                  <td className="num">{montant(m.montant)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <form method="get" className="barre-filtres">
        <label>
          Statut{" "}
          <select name="statut" defaultValue={statutFiltre ?? ""}>
            <option value="">Tous</option>
            {STATUTS.map((s) => (
              <option key={s} value={s}>
                {LIBELLES_STATUT[s].replace("⚠ ", "")}
              </option>
            ))}
          </select>
        </label>
        <button type="submit">Filtrer</button>
      </form>

      {erreurSituation && (
        <p className="message-erreur">Impossible de charger les créances : {erreurSituation.message}</p>
      )}

      <GestionCreances
        creances={lignes}
        estComptable={estComptable}
        entrepriseId={profil.entreprise_id}
        categories={(categories ?? []) as { id: string; libelle: string; type: "fixe" | "variable" | "revenu" }[]}
        lignesDisponibles={lignesDisponibles}
        lignesLabels={lignesLabels}
      />
    </main>
  );
}
