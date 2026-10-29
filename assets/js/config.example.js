/**
 * Cœur d'Honneur — config.example.js
 * ---------------------------------------------------------------------------
 * MODÈLE à copier, ne jamais éditer directement.
 *
 *   copy assets\js\config.example.js assets\js\config.js      (Windows)
 *
 * Le fichier config.js est ignoré par Git. En production, il est généré au
 * déploiement par scripts/generate-config.mjs à partir des variables
 * d'environnement Vercel.
 *
 * ATTENTION : seule la clé « anon / publishable » a sa place ici.
 * La clé « service_role » ne doit jamais apparaître dans un fichier servi au
 * navigateur, ni dans le dépôt Git, ni dans une variable NEXT_PUBLIC_*.
 */

export const APP_CONFIG = {
  /** URL du projet Supabase, sans slash final. */
  SUPABASE_URL: "https://VOTRE-PROJET.supabase.co",

  /** Clé publique (anon). Visible par tous : la sécurité repose sur les RLS. */
  SUPABASE_ANON_KEY: "VOTRE_CLE_ANON_PUBLIQUE",

  /** "development" | "production" — utilisé pour les messages de debug. */
  APP_ENV: "development",

  /** Nom affiché si app_settings n'est pas encore chargé. */
  APP_NAME: "Cœur d'Honneur",

  /** Devise par défaut ; la valeur de app_settings.currency prévaut. */
  DEFAULT_CURRENCY: "XOF",
};
