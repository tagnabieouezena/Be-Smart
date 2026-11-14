import { redirect } from "next/navigation";
import { exigerRole } from "@/lib/acces";
import { createClient } from "@/lib/supabase/server";
import { SelecteurPeriode } from "@/components/selecteur-periode";
import { BoutonCreerBudget } from "@/components/bouton-creer-budget";
import { GestionLignesCharge } from "@/components/gestion-lignes-charge";
import { GestionLignesRevenu } from "@/components/gestion-lignes-revenu";
import { ActionsBudget } from "@/components/actions-budget";
import { formaterMontant } from "@/lib/format";

export default async function BudgetsPage({
  searchParams,
}: {
  searchParams: Promise<{ mois?: string; annee?: string }>;
}) {
  await exigerRole(["ceo"], "/budgets");
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

  // Session valide sans profil : « / » recrée l'espace ou l'explique (jamais /connexion).
  if (!profil) {
    redirect("/?next=%2Fbudgets");
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
  let lignesRevenu: {
    id: string;
    source: string;
    montant_estime: number;
    statut: string;
    nb_creances?: number;
    montant_facture?: number;
    reste_a_facturer?: number;
  }[] = [];
  let totaux: {
    total_charges_fixes: number;
    total_charges_variables: number;
    total_ca_previsionnel: number;
    resultat_previsionnel: number;
  } | null = null;

  if (budget) {
    const [{ data: cats }, { data: charges }, { data: revenus }, { data: tot }, { data: facturation }] =
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
        // Facturé / reste à facturer (prérequis du 4.9, décision P8) : lus
        // dans la vue, jamais recalculés ici. Absente pour une ligne
        // annulée (exclue de la vue) : traitée comme "— / —" à l'écran.
        estCeo
          ? supabase
              .from("v_lignes_revenu_facturation")
              .select("ligne_revenu_prevu_id, nb_creances, montant_facture, reste_a_facturer")
              .eq("budget_mensuel_id", budget.id)
          : Promise.resolve({ data: [] }),
      ]);

    categories = cats ?? [];
    lignesCharge = charges ?? [];
    const facturationParId = new Map(
      (facturation ?? []).map((f) => [
        f.ligne_revenu_prevu_id as string,
        { nb_creances: f.nb_creances as number, montant_facture: f.montant_facture as number, reste_a_facturer: f.reste_a_facturer as number },
      ]),
    );
    lignesRevenu = (revenus ?? []).map((l) => ({ ...l, ...facturationParId.get(l.id) }));
    totaux = tot ?? null;
  }

  const categoriesFixes = categories.filter((c) => c.type === "fixe");
  const categoriesVariables = categories.filter((c) => c.type === "variable");

  return (
    <main className="page">
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
              <table>
                <tbody>
                  <tr>
                    <th scope="row">Charges fixes</th>
                    <td className="num">{formaterMontant(totaux.total_charges_fixes)}</td>
                  </tr>
                  <tr>
                    <th scope="row">Charges variables</th>
                    <td className="num">{formaterMontant(totaux.total_charges_variables)}</td>
                  </tr>
                  <tr>
                    <th scope="row">CA prévisionnel</th>
                    <td className="num">{formaterMontant(totaux.total_ca_previsionnel)}</td>
                  </tr>
                  <tr>
                    <th scope="row">Résultat prévisionnel</th>
                    <td className="num">{formaterMontant(totaux.resultat_previsionnel)}</td>
                  </tr>
                </tbody>
              </table>
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
                      {l.designation} — {formaterMontant(l.montant)} ({l.statut})
                    </li>
                  ))}
                </ul>
              </section>
              <section>
                <h3>Revenus prévus</h3>
                <ul>
                  {lignesRevenu.map((l) => (
                    <li key={l.id}>
                      {l.source} — {formaterMontant(l.montant_estime)} ({l.statut})
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
