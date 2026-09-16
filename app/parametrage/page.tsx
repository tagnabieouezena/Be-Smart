import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { GestionCategories } from "@/components/gestion-categories";
import { GestionObjectifs } from "@/components/gestion-objectifs";
import { FormulaireSoldeInitial } from "@/components/formulaire-solde-initial";

const MODES_PAIEMENT_FIXES = [
  { valeur: "cash", libelle: "Cash" },
  { valeur: "mobile_money", libelle: "Mobile Money" },
  { valeur: "virement", libelle: "Virement" },
  { valeur: "cheque", libelle: "Chèque" },
];

export default async function ParametragePage() {
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

  // Contrôle côté serveur — pas seulement une page cachée dans la nav,
  // même principe que /supervision (Module 4.1).
  if (!profil || profil.role !== "ceo") {
    notFound();
  }

  const [{ data: entreprise }, { data: categories }, { data: objectifs }] =
    await Promise.all([
      supabase
        .from("entreprises")
        .select("id, solde_initial")
        .eq("id", profil.entreprise_id)
        .single(),
      supabase
        .from("categories")
        .select("id, libelle, type")
        .order("libelle", { ascending: true }),
      supabase
        .from("objectifs_ca")
        .select("id, type_periode, annee, mois, trimestre, montant_cible")
        .order("annee", { ascending: false }),
    ]);

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Paramétrage</h1>

      {entreprise && (
        <FormulaireSoldeInitial
          entrepriseId={entreprise.id}
          soldeInitial={entreprise.solde_initial}
        />
      )}

      <GestionCategories
        categories={categories ?? []}
        entrepriseId={profil.entreprise_id}
      />

      <GestionObjectifs
        objectifs={objectifs ?? []}
        entrepriseId={profil.entreprise_id}
      />

      <section>
        <h2>Modes de paiement</h2>
        <p>Liste fixe pour la V1 (non personnalisable) :</p>
        <ul>
          {MODES_PAIEMENT_FIXES.map((m) => (
            <li key={m.valeur}>{m.libelle}</li>
          ))}
        </ul>
      </section>
    </main>
  );
}
