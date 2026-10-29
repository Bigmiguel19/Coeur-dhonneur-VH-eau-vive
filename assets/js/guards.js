/* ==========================================================================
   Cœur d'Honneur — guards.js
   ---------------------------------------------------------------------------
   Protection des pages privées.

   Le contrôle est fait côté client pour l'expérience utilisateur, mais la
   véritable barrière reste la base de données : même si quelqu'un forçait
   l'affichage d'une page, les politiques RLS refuseraient les données.

   Utilisation en tête de page :
       const { session, profile, error } = await requireSession({ roles: ["admin"] });
       if (!session) return; // une redirection est déjà en cours
   ========================================================================== */

import { getSession, fetchProfile, homeForRole, appUrl } from "./auth.js";
import { IS_CONFIGURED, CONFIG_ERROR, supabase } from "./supabase-client.js";

/** URL de connexion avec mémorisation de la page demandée. */
function loginUrl(reason) {
  const current = `${window.location.pathname}${window.location.search}`;
  const url = new URL(appUrl("login.html"));
  if (reason) url.searchParams.set("reason", reason);
  if (current && current !== "/" && !/\/login\.html$/.test(window.location.pathname)) {
    url.searchParams.set("next", current);
  }
  return url.href;
}

/**
 * Exige une session valide (et éventuellement un rôle).
 * @param {{ roles?: string[], onRedirect?: () => void }} [options]
 * @returns {Promise<{ session: any|null, profile: Record<string, any>|null,
 *                     error: unknown, redirected: boolean }>}
 */
export async function requireSession({ roles = [] } = {}) {
  if (!IS_CONFIGURED) {
    return { session: null, profile: null, error: new Error(CONFIG_ERROR), redirected: false };
  }

  const { session, error } = await getSession();
  if (error || !session) {
    window.location.replace(loginUrl("expired"));
    return { session: null, profile: null, error, redirected: true };
  }

  const { profile, error: profileError } = await fetchProfile(session.user.id);

  if (profileError) {
    // Base non installée ou droits manquants : on n'enferme pas l'utilisateur
    // dans une boucle de redirection, la page affiche l'erreur.
    return { session, profile: null, error: profileError, redirected: false };
  }

  if (!profile) {
    await safeSignOut();
    window.location.replace(loginUrl("expired"));
    return { session: null, profile: null, error: new Error("Profil introuvable."), redirected: true };
  }

  if (profile.is_active === false) {
    await safeSignOut();
    window.location.replace(loginUrl("inactive"));
    return { session: null, profile: null, error: new Error("Compte désactivé."), redirected: true };
  }

  if (roles.length && !roles.includes(profile.role)) {
    window.location.replace(appUrl(homeForRole(profile.role), "?reason=denied"));
    return { session, profile, error: null, redirected: true };
  }

  return { session, profile, error: null, redirected: false };
}

/** Raccourci : espace membre. */
export function requireMember() {
  return requireSession({ roles: ["member", "admin"] });
}

/** Raccourci : espace administration. */
export function requireAdmin() {
  return requireSession({ roles: ["admin"] });
}

/**
 * Sur une page publique d'authentification : redirige un utilisateur
 * déjà connecté vers son espace.
 * @returns {Promise<boolean>} true si une redirection a été déclenchée
 */
export async function redirectIfAuthenticated() {
  if (!IS_CONFIGURED) return false;

  const { session } = await getSession();
  if (!session) return false;

  const { profile } = await fetchProfile(session.user.id);
  window.location.replace(appUrl(homeForRole(profile?.role)));
  return true;
}

async function safeSignOut() {
  try {
    await supabase.auth.signOut();
  } catch {
    /* ignore */
  }
}
