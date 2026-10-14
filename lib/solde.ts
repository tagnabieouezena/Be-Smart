// Solde de caisse daté : constantes et affichage uniquement. Aucun calcul de
// solde n'est fait côté TypeScript : la règle unique vit dans la base
// (fonction solde_caisse_a, voir docs/briefs/Solde-Initial-Date.md).

// Date par défaut de entreprises.date_solde_initial (valeur de la migration) :
// « aucune date renseignée », toutes les transactions s'ajoutent au solde.
export const DATE_DEBUT_HISTORIQUE = "2000-01-01";

export function estDateParDefaut(date: string): boolean {
  return date === DATE_DEBUT_HISTORIQUE;
}

const dateLongue = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

// « 2026-10-13 » -> « 13 octobre 2026 ».
export function formaterDateLongue(date: string): string {
  return dateLongue.format(new Date(`${date}T00:00:00Z`));
}

// Date du jour (UTC, comme current_date côté base) au format AAAA-MM-JJ, pour
// borner le champ de saisie : la base refuse de toute façon une date future.
export function aujourdhuiISO(): string {
  return new Date().toISOString().slice(0, 10);
}
