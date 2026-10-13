import { NOMS_MOIS, NOMS_MOIS_COURTS, formaterMontant } from "@/lib/format";

export type PointGraphique = { mois: number; ca: number; depenses: number; resultat: number };

// Graphique d'évolution mensuelle écrit à la main (SVG rendu côté serveur, aucune
// dépendance ni JavaScript envoyé au navigateur). Les courbes se distinguent par
// le tracé (plein, tirets, pointillés) et la forme du repère, pas seulement par la
// couleur. Le tableau de la page donne toutes les valeurs exactes.
//
// Seule arithmétique de ce composant : la mise à l'échelle géométrique des points.
// Aucun montant affiché n'en résulte : les repères de l'axe vertical sont des
// valeurs de la série (0, maximum, minimum), jamais des valeurs calculées.
const LARGEUR = 720;
const HAUTEUR = 360;
const MARGE = { gauche: 110, droite: 20, haut: 50, bas: 40 };

const SERIES = [
  { cle: "ca", libelle: "CA encaissé", couleur: "var(--graph-ca)", tirets: undefined, repere: "cercle" },
  { cle: "depenses", libelle: "Dépenses", couleur: "var(--graph-depenses)", tirets: "8 5", repere: "carre" },
  { cle: "resultat", libelle: "Résultat net", couleur: "var(--graph-resultat)", tirets: "2 4", repere: "triangle" },
] as const;

function Repere({ forme, x, y, couleur }: { forme: string; x: number; y: number; couleur: string }) {
  if (forme === "carre") {
    return <rect x={x - 4} y={y - 4} width={8} height={8} fill={couleur} />;
  }
  if (forme === "triangle") {
    return <polygon points={`${x},${y - 5} ${x + 5},${y + 4} ${x - 5},${y + 4}`} fill={couleur} />;
  }
  return <circle cx={x} cy={y} r={4} fill={couleur} />;
}

export function GraphiqueComparaison({ points, annee }: { points: PointGraphique[]; annee: number }) {
  if (points.length === 0) return null;

  const valeurs = points.flatMap((p) => [p.ca, p.depenses, p.resultat]);
  const maximum = Math.max(0, ...valeurs);
  const minimum = Math.min(0, ...valeurs);
  const etendue = maximum - minimum || 1;

  const largeurTrace = LARGEUR - MARGE.gauche - MARGE.droite;
  const hauteurTrace = HAUTEUR - MARGE.haut - MARGE.bas;
  const x = (mois: number) => MARGE.gauche + ((mois - 0.5) / 12) * largeurTrace;
  const y = (valeur: number) => MARGE.haut + ((maximum - valeur) / etendue) * hauteurTrace;

  const premier = points[0];
  const dernier = points[points.length - 1];
  const resume =
    `Évolution mensuelle de ${NOMS_MOIS[premier.mois - 1]} à ${NOMS_MOIS[dernier.mois - 1]} ${annee}. ` +
    SERIES.map(
      (s) =>
        `${s.libelle} : ${formaterMontant(premier[s.cle])} en ${NOMS_MOIS[premier.mois - 1]}` +
        (points.length > 1 ? `, ${formaterMontant(dernier[s.cle])} en ${NOMS_MOIS[dernier.mois - 1]}` : ""),
    ).join(". ") +
    ". Le tableau ci-dessous donne toutes les valeurs.";

  return (
    <figure>
      <svg
        className="graphique-comparaison"
        viewBox={`0 0 ${LARGEUR} ${HAUTEUR}`}
        role="img"
        aria-labelledby="graphique-titre graphique-resume"
      >
        <title id="graphique-titre">{`CA encaissé, dépenses et résultat net par mois, ${annee}`}</title>
        <desc id="graphique-resume">{resume}</desc>

        {/* Ligne du zéro et repères de l'axe vertical (valeurs de la série, non calculées). */}
        <line x1={MARGE.gauche} x2={LARGEUR - MARGE.droite} y1={y(0)} y2={y(0)} stroke="var(--graph-grille)" strokeWidth={1} />
        <text x={MARGE.gauche - 8} y={y(0) + 4} textAnchor="end" fontSize={12} fill="currentColor">
          0
        </text>
        {maximum > 0 && (
          <>
            <line x1={MARGE.gauche} x2={LARGEUR - MARGE.droite} y1={y(maximum)} y2={y(maximum)} stroke="var(--graph-grille)" strokeDasharray="3 3" />
            <text x={MARGE.gauche - 8} y={y(maximum) + 4} textAnchor="end" fontSize={12} fill="currentColor">
              {formaterMontant(maximum)}
            </text>
          </>
        )}
        {minimum < 0 && (
          <>
            <line x1={MARGE.gauche} x2={LARGEUR - MARGE.droite} y1={y(minimum)} y2={y(minimum)} stroke="var(--graph-grille)" strokeDasharray="3 3" />
            <text x={MARGE.gauche - 8} y={y(minimum) + 4} textAnchor="end" fontSize={12} fill="currentColor">
              {formaterMontant(minimum)}
            </text>
          </>
        )}

        {/* Mois (les mois futurs restent vides : le graphique s'arrête au mois affiché). */}
        {NOMS_MOIS_COURTS.map((nom, i) => (
          <text key={nom} x={x(i + 1)} y={HAUTEUR - 14} textAnchor="middle" fontSize={12} fill="currentColor">
            {nom}
          </text>
        ))}

        {SERIES.map((s) => (
          <g key={s.cle}>
            <polyline
              fill="none"
              stroke={s.couleur}
              strokeWidth={2.5}
              strokeDasharray={s.tirets}
              strokeLinecap="round"
              points={points.map((p) => `${x(p.mois)},${y(p[s.cle])}`).join(" ")}
            />
            {points.map((p) => (
              <Repere key={p.mois} forme={s.repere} x={x(p.mois)} y={y(p[s.cle])} couleur={s.couleur} />
            ))}
          </g>
        ))}

        {/* Légende : tracé + repère + libellé. */}
        {SERIES.map((s, i) => {
          const x0 = MARGE.gauche + i * 190;
          return (
            <g key={s.cle}>
              <line x1={x0} x2={x0 + 28} y1={20} y2={20} stroke={s.couleur} strokeWidth={2.5} strokeDasharray={s.tirets} strokeLinecap="round" />
              <Repere forme={s.repere} x={x0 + 14} y={20} couleur={s.couleur} />
              <text x={x0 + 36} y={24} fontSize={13} fill="currentColor">
                {s.libelle}
              </text>
            </g>
          );
        })}
      </svg>
    </figure>
  );
}
