/* ==========================================================================
   Cœur d'Honneur — supabase-client.js
   ---------------------------------------------------------------------------
   Point d'entrée unique vers Supabase. Aucun autre module ne crée de client.

   Sécurité :
   — seule la clé publique « anon » est utilisée côté navigateur ;
   — la clé « service_role » ne doit jamais figurer dans ce dossier ;
   — toutes les autorisations sont appliquées par les politiques RLS.

   Le SDK est chargé depuis un CDN en import ESM : ce projet n'a pas d'étape
   de compilation, il n'y a donc ni node_modules ni bundler à maintenir.
   ========================================================================== */

import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { APP_CONFIG } from "./config.js";

const PLACEHOLDER = /REMPLACER|VOTRE_|your-/i;

/**
 * Vérifie que la configuration locale a bien été renseignée.
 * @returns {string|null} message d'erreur lisible, ou null si tout est bon
 */
function configurationError() {
  const url = APP_CONFIG?.SUPABASE_URL ?? "";
  const key = APP_CONFIG?.SUPABASE_ANON_KEY ?? "";

  if (!url || !key) {
    return "Configuration absente : renseignez assets/js/config.js.";
  }
  if (PLACEHOLDER.test(url) || PLACEHOLDER.test(key)) {
    return "Configuration incomplète : les valeurs de assets/js/config.js sont encore des exemples.";
  }
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url)) {
    return "Configuration invalide : SUPABASE_URL doit ressembler à https://xxxx.supabase.co.";
  }
  return null;
}

export const CONFIG_ERROR = configurationError();
export const IS_CONFIGURED = CONFIG_ERROR === null;

/**
 * Client Supabase partagé.
 * Vaut `null` si la configuration est absente : les pages affichent alors
 * un message explicite au lieu de planter silencieusement.
 */
export const supabase = IS_CONFIGURED
  ? createClient(APP_CONFIG.SUPABASE_URL, APP_CONFIG.SUPABASE_ANON_KEY, {
      auth: {
        // Session persistée et rafraîchie automatiquement : l'utilisateur
        // n'a pas à se reconnecter à chaque visite.
        persistSession: true,
        autoRefreshToken: true,
        // Nécessaire pour les retours de lien de réinitialisation.
        detectSessionInUrl: true,
        storageKey: "cdh-auth",
      },
      global: {
        headers: { "x-client-info": "coeur-honneur-web" },
      },
      db: { schema: "public" },
    })
  : null;

export { APP_CONFIG };

/**
 * Garde-fou utilisé par les pages : lève une erreur claire si le client
 * n'est pas disponible.
 */
export function requireClient() {
  if (!supabase) {
    throw new Error(CONFIG_ERROR ?? "Client Supabase indisponible.");
  }
  return supabase;
}
