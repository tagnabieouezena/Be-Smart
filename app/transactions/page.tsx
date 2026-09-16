import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { FiltresTransactions } from "@/components/filtres-transactions";
import { FormulaireSaisieTransaction } from "@/components/formulaire-saisie-transaction";

export default async function TransactionsPage({
  searchParams,
}: {
  searchParams: Promise<{
    date_debut?: string;
    date_fin?: string;
    categorie_id?: string;
    saisi_par?: string;
    mode_paiement?: string;
  }>;
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

  if (!profil) {
    redirect("/connexion");
  }

  const estComptable = profil.role === "comptable";

  // Filtrage côté requête (pas côté client) — reste utilisable avec un
  // historique important, CDC 5.3.
  let requete = supabase
    .from("transactions")
    .select(
      "id, date, description, type, montant, mode_paiement, notes, categories(libelle), utilisateurs(nom)",
    )
    .order("date", { ascending: false });

  if (params.date_debut) requete = requete.gte("date", params.date_debut);
  if (params.date_fin) requete = requete.lte("date", params.date_fin);
  if (params.categorie_id) requete = requete.eq("categorie_id", params.categorie_id);
  if (params.saisi_par) requete = requete.eq("saisi_par", params.saisi_par);
  if (params.mode_paiement) requete = requete.eq("mode_paiement", params.mode_paiement);

  const maintenant = new Date();

  const [{ data: transactions }, { data: categories }, { data: utilisateurs }, { data: lignesRevenuPrevu }] =
    await Promise.all([
      requete,
      supabase.from("categories").select("id, libelle, type"),
      supabase.from("utilisateurs").select("id, nom"),
      estComptable
        ? supabase
            .from("lignes_revenu_prevu")
            .select("id, source, montant_estime, budgets_mensuels!inner(mois, annee)")
            .eq("statut", "en_attente")
        : Promise.resolve({ data: [] }),
    ]);

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Journal des transactions</h1>

      <FiltresTransactions categories={categories ?? []} utilisateurs={utilisateurs ?? []} />

      <table>
        <thead>
          <tr>
            <th>Date</th>
            <th>Description</th>
            <th>Catégorie</th>
            <th>Type</th>
            <th>Montant</th>
            <th>Mode</th>
            <th>Saisi par</th>
          </tr>
        </thead>
        <tbody>
          {(transactions ?? []).map((t) => (
            <tr key={t.id}>
              <td>{t.date}</td>
              <td>{t.description}</td>
              <td>{(t.categories as unknown as { libelle: string } | null)?.libelle}</td>
              <td>{t.type}</td>
              <td>{t.montant} FCFA</td>
              <td>{t.mode_paiement}</td>
              <td>{(t.utilisateurs as unknown as { nom: string } | null)?.nom}</td>
            </tr>
          ))}
        </tbody>
      </table>

      {estComptable && (
        <FormulaireSaisieTransaction
          entrepriseId={profil.entreprise_id}
          categories={categories ?? []}
          lignesRevenuPrevuEnAttente={((lignesRevenuPrevu ?? []) as unknown as {
            id: string;
            source: string;
            montant_estime: number;
            budgets_mensuels: { mois: number; annee: number };
          }[]).filter(
            (l) =>
              l.budgets_mensuels.mois === maintenant.getMonth() + 1 &&
              l.budgets_mensuels.annee === maintenant.getFullYear(),
          )}
        />
      )}
    </main>
  );
}
