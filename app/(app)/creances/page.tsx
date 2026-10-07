import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { GestionCreances, type LigneCreance } from "@/components/gestion-creances";

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

const formatMontant = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
const montant = (v: number) => `${formatMontant.format(v)} FCFA`;

function libelleMois(cle: string) {
  const [annee, mois] = cle.split("-");
  return `${NOMS_MOIS[Number(mois) - 1]} ${annee}`;
}

const cellule = { padding: "0.4rem 0.6rem", borderBottom: "1px solid #ddd", textAlign: "left" as const };

export default async function CreancesPage({
  searchParams,
}: {
  searchParams: Promise<{ statut?: string }>;
}) {
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

  const [{ data: situation, error: erreurSituation }, { data: balance }, { data: categories }] =
    await Promise.all([
      requeteSituation,
      supabase.rpc("creances_balance_agee"),
      estComptable
        ? supabase.from("categories").select("id, libelle, type")
        : Promise.resolve({ data: [] }),
    ]);

  const lignes = (situation ?? []) as LigneCreance[];
  const lignesBalance = (balance ?? []) as LigneBalance[];
  const totalEnCours = lignesBalance.find((l) => l.rubrique === "total")?.montant ?? 0;
  const tranches = lignesBalance.filter((l) => l.rubrique === "tranche");
  const parMois = lignesBalance.filter((l) => l.rubrique === "mois");

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Créances clients</h1>

      <section aria-label="Synthèse" style={{ margin: "1rem 0" }}>
        <p>
          <strong>Total des créances en cours : {montant(totalEnCours)}</strong>
        </p>

        <div style={{ display: "flex", gap: "2rem", flexWrap: "wrap" }}>
          <table style={{ borderCollapse: "collapse" }}>
            <caption style={{ textAlign: "left", fontWeight: 600 }}>Balance âgée (reste dû)</caption>
            <tbody>
              {tranches.map((t) => (
                <tr key={t.cle}>
                  <th style={cellule}>{LIBELLES_TRANCHE[t.cle] ?? t.cle}</th>
                  <td style={cellule}>{montant(t.montant)}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <table style={{ borderCollapse: "collapse" }}>
            <caption style={{ textAlign: "left", fontWeight: 600 }}>Reste dû par mois d&apos;échéance</caption>
            <tbody>
              {parMois.length === 0 && (
                <tr>
                  <td style={cellule}>Aucun reste dû</td>
                </tr>
              )}
              {parMois.map((m) => (
                <tr key={m.cle}>
                  <th style={cellule}>{libelleMois(m.cle)}</th>
                  <td style={cellule}>{montant(m.montant)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <form method="get" style={{ display: "flex", gap: "0.5rem", alignItems: "center", margin: "1rem 0" }}>
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
        <p style={{ color: "crimson" }}>Impossible de charger les créances : {erreurSituation.message}</p>
      )}

      <GestionCreances
        creances={lignes}
        estComptable={estComptable}
        entrepriseId={profil.entreprise_id}
        categories={(categories ?? []) as { id: string; libelle: string; type: "fixe" | "variable" | "revenu" }[]}
      />
    </main>
  );
}
