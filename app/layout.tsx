import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

// Inter, auto-hébergée par next/font au moment du build : aucune requête vers
// Google Fonts à l'exécution (docs/06, décision 3). Exposée en --font-inter,
// lue par --police-texte avec repli sur la pile système.
const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "Be Smart Pilotage",
  description: "Pilotage financier pour TPE/PME",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="fr" className={inter.variable}>
      <body>{children}</body>
    </html>
  );
}
