"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Categorie = {
  id: string;
  libelle: string;
  type: "fixe" | "variable" | "revenu";
};

const TYPES: Categorie["type"][] = ["fixe", "variable", "revenu"];

export function GestionCategories({
  categories,
  entrepriseId,
}: {
  categories: Categorie[];
  entrepriseId: string;
}) {
  const router = useRouter();
  const [libelle, setLibelle] = useState("");
  const [type, setType] = useState<Categorie["type"]>("fixe");
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);
  const [enEdition, setEnEdition] = useState<string | null>(null);
  const [libelleEdition, setLibelleEdition] = useState("");

  async function ajouter(e: React.FormEvent) {
    e.preventDefault();
    setErreur(null);
    setEnCours(true);

    const supabase = createClient();
    const { error } = await supabase
      .from("categories")
      .insert({ entreprise_id: entrepriseId, libelle, type });

    setEnCours(false);

    if (error) {
      setErreur(error.message);
      return;
    }

    setLibelle("");
    router.refresh();
  }

  async function enregistrerEdition(id: string) {
    const supabase = createClient();
    const { error } = await supabase
      .from("categories")
      .update({ libelle: libelleEdition })
      .eq("id", id);

    if (error) {
      setErreur(error.message);
      return;
    }

    setEnEdition(null);
    router.refresh();
  }

  async function supprimer(id: string) {
    const supabase = createClient();
    const { error } = await supabase.from("categories").delete().eq("id", id);

    if (error) {
      setErreur(error.message);
      return;
    }

    router.refresh();
  }

  return (
    <section>
      <h2>Catégories</h2>
      {TYPES.map((t) => (
        <div key={t}>
          <h3>{t}</h3>
          <ul>
            {categories
              .filter((c) => c.type === t)
              .map((c) => (
                <li key={c.id}>
                  {enEdition === c.id ? (
                    <>
                      <input
                        value={libelleEdition}
                        onChange={(e) => setLibelleEdition(e.target.value)}
                      />
                      <button onClick={() => enregistrerEdition(c.id)}>
                        Enregistrer
                      </button>
                      <button onClick={() => setEnEdition(null)}>Annuler</button>
                    </>
                  ) : (
                    <>
                      {c.libelle}{" "}
                      <button
                        onClick={() => {
                          setEnEdition(c.id);
                          setLibelleEdition(c.libelle);
                        }}
                      >
                        Modifier
                      </button>
                      <button onClick={() => supprimer(c.id)}>Supprimer</button>
                    </>
                  )}
                </li>
              ))}
          </ul>
        </div>
      ))}

      <form onSubmit={ajouter} style={{ display: "grid", gap: "0.5rem", maxWidth: 320 }}>
        <label>
          Libellé
          <input required value={libelle} onChange={(e) => setLibelle(e.target.value)} />
        </label>
        <label>
          Type
          <select value={type} onChange={(e) => setType(e.target.value as Categorie["type"])}>
            {TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </label>
        {erreur && <p style={{ color: "crimson" }}>{erreur}</p>}
        <button type="submit" disabled={enCours}>
          {enCours ? "Ajout..." : "Ajouter une catégorie"}
        </button>
      </form>
    </section>
  );
}
