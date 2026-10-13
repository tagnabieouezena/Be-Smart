import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function SupervisionPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Contrôle côté serveur, pas seulement une entrée cachée dans la nav :
  // même claim que public.is_super_admin_be_smart() côté base.
  const estSuperAdmin = user?.app_metadata?.super_admin === true;

  if (!estSuperAdmin) {
    notFound();
  }

  // Filtré une deuxième fois par la vue elle-même (voir migration Phase 0) :
  // colonnes non financières uniquement, même en cas d'erreur ici.
  const { data: entreprises } = await supabase
    .from("v_entreprises_supervision")
    .select("id, nom, secteur, created_at")
    .order("created_at", { ascending: true });

  return (
    <main style={{ padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Supervision Be Smart — entreprises clientes</h1>
      <p>Lecture seule, métadonnées non financières.</p>
      <ul>
        {entreprises?.map((e) => (
          <li key={e.id}>
            {e.nom} — {e.secteur ?? "secteur non renseigné"}
          </li>
        ))}
      </ul>
    </main>
  );
}
