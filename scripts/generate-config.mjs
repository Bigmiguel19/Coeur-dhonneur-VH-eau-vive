/**
 * scripts/generate-config.mjs
 * Génère assets/js/config.js à partir des variables d'environnement Vercel
 */
import fs from "node:fs";
import path from "node:path";

const supabaseUrl = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || "https://mlisdelyezmnuvfyymzg.supabase.co";
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1saXNkZWx5ZXptbnV2Znl5bXpnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyNTcwMDMsImV4cCI6MjEwODgzMzAwM30.C4SuZX3uYLXJ9fMRebOtCuRsnsALrlggGJ1TKLsgrb0";

const content = `// Fichier généré automatiquement au déploiement Vercel
export const APP_CONFIG = {
  SUPABASE_URL: "${supabaseUrl.replace(/\/$/, "")}",
  SUPABASE_ANON_KEY: "${supabaseAnonKey}",
  APP_ENV: "${process.env.NODE_ENV || 'production'}",
  APP_NAME: "Cœur d'Honneur",
  DEFAULT_CURRENCY: "XOF",
};
`;

const targetDir = path.resolve("assets", "js");
if (!fs.existsSync(targetDir)) {
  fs.mkdirSync(targetDir, { recursive: true });
}

fs.writeFileSync(path.join(targetDir, "config.js"), content, "utf8");
console.log("assets/js/config.js généré avec succès !");
