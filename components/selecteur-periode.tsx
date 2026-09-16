"use client";

import { useRouter } from "next/navigation";

export function SelecteurPeriode({ mois, annee }: { mois: number; annee: number }) {
  const router = useRouter();

  function naviguer(nouveauMois: number, nouvelleAnnee: number) {
    router.push(`/budgets?mois=${nouveauMois}&annee=${nouvelleAnnee}`);
  }

  return (
    <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
      <label>
        Mois
        <select
          value={mois}
          onChange={(e) => naviguer(Number(e.target.value), annee)}
        >
          {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => (
            <option key={m} value={m}>
              {m}
            </option>
          ))}
        </select>
      </label>
      <label>
        Année
        <input
          type="number"
          value={annee}
          onChange={(e) => naviguer(mois, Number(e.target.value))}
        />
      </label>
    </div>
  );
}
