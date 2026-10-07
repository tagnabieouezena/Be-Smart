import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SelecteurPeriode } from "@/components/selecteur-periode";
import { BoutonCreerBudget } from "@/components/bouton-creer-budget";
import { GestionLignesCharge } from "@/components/gestion-lignes-charge";
import { GestionLignesRevenu } from "@/components/gestion-lignes-revenu";
import { ActionsBudget } from "@/components/actions-budget";

export default async function BudgetsPage({
  searchParams,
}: {
  searchParams: Promise<{ mois?: string; annee?: string }>;
}) {
  const params = await searchParams;
  const maintenant = new Date();
  const mois = Number(params.mois) || maintenant.getMonth() + 1;
  const annee = Number(params.annee) || maintenant.getFullYear();

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

  const estCeo = profil.role === "ceo";

  const { data: budget } = await supabase
    .from("budgets_mensuels")
    .select("id, statut")
    .eq("mois", mois)
    .eq("annee", annee)
    .maybeSingle();

  let categories: { id: string; libelle: string; type: string }[] = [];
  let lignesCharge: {
    id: string;
    designation: string;
    montant: number;
    categorie_id: string;
    statut: string;
  }[] = [];
  let lignesRevenu: { id: string; source: string; montant_estime: number; statut: string }[] = [];
  let totaux: {
    total_charges_fixes: number;
    total_charges_variables: number;
    total_ca_previsionnel: number;
    resultat_previsionnel: number;
  } | null = null;

  if (budget) {
    const [{ data: cats }, { data: charges }, { data: revenus }, { data: tot }] =
      await Promise.all([
        supabase.from("categories").select("id, libelle, type"),
        supabase
          .from("lignes_charge_prevue")
          .select("id, designation, montant, categorie_id, statut")
          .eq("budget_mensuel_id", budget.id),
        supabase
          .from("lignes_revenu_prevu")
          .select("id, source, montant_estime, statut")
          .eq("budget_mensuel_id", budget.id),
        supabase
          .from("v_budget_mensuel_totaux")
          .select("total_charges_fixes, total_charges_variables, total_ca_previsionnel, resultat_previsionnel")
          .eq("budget_mensuel_id", budget.id)
          .maybeSingle(),
      ]);

    categories = cats ?? [];
    lignesCharge = charges ?? [];
    lignesRevenu = revenus ?? [];
    totaux = tot ?? null;
  }

  const categoriesFixes = categories.filter((c) => c.type === "fixe");
  const categoriesVariables = categories.filter((c) => c.type === "variable");

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Budget prévisionnel</h1>
      <SelecteurPeriode mois={mois} annee={annee} />

      {!budget && estCeo && (
        <BoutonCreerBudget entrepriseId={profil.entreprise_id} mois={mois} annee={annee} />
      )}
      {!budget && !estCeo && <p>Aucun budget pour {mois}/{annee}.</p>}

      {budget && (
        <>
          {estCeo && <ActionsBudget budgetMensuelId={budget.id} statut={budget.statut} />}
          {!estCeo && <p>Statut : {budget.statut}</p>}

          {totaux && (
            <section>
              <h2>Totaux</h2>
              <ul>
                <li>Charges fixes : {totaux.total_charges_fixes} FCFA</li>
                <li>Charges variables : {totaux.total_charges_variables} FCFA</li>
                <li>CA prévisionnel : {totaux.total_ca_previsionnel} FCFA</li>
                <li>Résultat prévisionnel : {totaux.resultat_previsionnel} FCFA</li>
              </ul>
            </section>
          )}

          {estCeo ? (
            <>
              <GestionLignesCharge
                titre="Charges fixes prévues"
                type="fixe"
                lignes={lignesCharge.filter((l) =>
                  categoriesFixes.some((c) => c.id === l.categorie_id),
                )}
                categories={categoriesFixes}
                budgetMensuelId={budget.id}
                entrepriseId={profil.entreprise_id}
              />
              <GestionLignesCharge
                titre="Charges variables prévues"
                type="variable"
                lignes={lignesCharge.filter((l) =>
                  categoriesVariables.some((c) => c.id === l.categorie_id),
                )}
                categories={categoriesVariables}
                budgetMensuelId={budget.id}
                entrepriseId={profil.entreprise_id}
              />
              <GestionLignesRevenu
                lignes={lignesRevenu}
                budgetMensuelId={budget.id}
                entrepriseId={profil.entreprise_id}
              />
            </>
          ) : (
            <>
              <section>
                <h3>Charges prévues</h3>
                <ul>
                  {lignesCharge.map((l) => (
                    <li key={l.id}>
                      {l.designation} — {l.montant} FCFA ({l.statut})
                    </li>
                  ))}
                </ul>
              </section>
              <section>
                <h3>Revenus prévus</h3>
                <ul>
                  {lignesRevenu.map((l) => (
                    <li key={l.id}>
                      {l.source} — {l.montant_estime} FCFA ({l.statut})
                    </li>
                  ))}
                </ul>
              </section>
            </>
          )}
        </>
      )}
    </main>
  );
}
