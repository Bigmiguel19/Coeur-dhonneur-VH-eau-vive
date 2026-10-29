/* ==========================================================================
   Cœur d'Honneur — auth.js
   ---------------------------------------------------------------------------
   Authentification, session et profil.

   Règles :
   — le rôle n'est jamais choisi par le navigateur, il est lu en base ;
   — aucune inscription publique : les comptes sont créés par l'administration ;
   — les erreurs Supabase sont traduites en français avant d'être affichées.
   ========================================================================== */

import { supabase, CONFIG_ERROR, IS_CONFIGURED } from "./supabase-client.js";

/** Page d'accueil selon le rôle. */
export const ROLE_HOME = Object.freeze({
  admin: "admin/index.html",
  member: "dashboard.html",
});

/**
 * Destination après connexion pour un rôle donné.
 * @param {"admin"|"member"|string|null|undefined} role
 * @returns {string}
 */
export function homeForRole(role) {
  return ROLE_HOME[role] ?? ROLE_HOME.member;
}

/** Préfixe relatif vers la racine du site ("", "../", "../../"…). */
export function sitePrefix() {
  const depth = window.location.pathname.split("/").filter(Boolean).length - 1;
  return "../".repeat(Math.max(0, depth));
}

/** Construit une URL absolue vers une page du site, quel que soit le niveau. */
export function appUrl(page, search = "") {
  const url = new URL(`${sitePrefix()}${page}`, window.location.href);
  if (search) url.search = search;
  return url.href;
}

/* --------------------------------------------------------------------------
   1. Traduction des erreurs
   -------------------------------------------------------------------------- */
const AUTH_MESSAGES = [
  ["invalid login credentials", "E-mail ou mot de passe incorrect."],
  ["email not confirmed", "Votre adresse e-mail n’a pas encore été confirmée. Contactez l’administration."],
  ["invalid email", "Cette adresse e-mail n’est pas valide."],
  ["user not found", "Aucun compte ne correspond à cette adresse."],
  ["too many requests", "Trop de tentatives. Patientez quelques minutes avant de réessayer."],
  ["rate limit", "Trop de tentatives. Patientez quelques minutes avant de réessayer."],
  ["password should be at least", "Le mot de passe est trop court : 8 caractères minimum."],
  ["weak password", "Ce mot de passe est trop faible. Choisissez-en un plus solide."],
  ["same password", "Le nouveau mot de passe doit être différent de l’ancien."],
  ["auth session missing", "Votre session a expiré. Merci de vous reconnecter."],
  ["jwt expired", "Votre session a expiré. Merci de vous reconnecter."],
  ["network", "Connexion au serveur impossible. Vérifiez votre connexion internet."],
  ["failed to fetch", "Connexion au serveur impossible. Vérifiez votre connexion internet."],
];

/**
 * Message français à partir d'une erreur Supabase.
 * @param {unknown} error
 * @returns {string}
 */
export function authErrorMessage(error) {
  if (!error) return "Une erreur inattendue est survenue.";
  if (!IS_CONFIGURED) return CONFIG_ERROR;

  const code = String(error.code ?? "").toLowerCase();
  const message = String(error.message ?? "").toLowerCase();

  // Tables absentes : la base n'a pas encore été installée.
  if (code === "pgrst205" || /could not find the table/.test(message)) {
    return "La base de données n’est pas encore installée sur le projet Supabase. Exécutez les scripts SQL fournis (schema.sql, policies.sql, seed.example.sql).";
  }
  if (code === "42501" || /permission denied/.test(message)) {
    return "Action non autorisée pour votre compte.";
  }

  for (const [needle, translation] of AUTH_MESSAGES) {
    if (message.includes(needle) || code.includes(needle)) return translation;
  }
  return error.message || "Une erreur inattendue est survenue.";
}

/* --------------------------------------------------------------------------
   2. Session
   -------------------------------------------------------------------------- */

/**
 * Session courante, ou null.
 * @returns {Promise<{ session: import("@supabase/supabase-js").Session|null, error: unknown }>}
 */
export async function getSession() {
  if (!supabase) return { session: null, error: new Error(CONFIG_ERROR) };
  const { data, error } = await supabase.auth.getSession();
  return { session: data?.session ?? null, error };
}

/**
 * Connexion par e-mail et mot de passe.
 * @param {string} email
 * @param {string} password
 */
export async function signIn(email, password) {
  if (!supabase) return { session: null, error: new Error(CONFIG_ERROR) };
  const { data, error } = await supabase.auth.signInWithPassword({
    email: String(email).trim().toLowerCase(),
    password,
  });
  if (error) return { session: null, user: null, error };
  return { session: data.session, user: data.user, error: null };
}

/**
 * Déconnexion puis redirection facultative.
 * @param {{ redirectTo?: string|null }} [options]
 */
export async function signOut({ redirectTo = "index.html" } = {}) {
  if (supabase) {
    try {
      await supabase.auth.signOut();
    } catch {
      /* une session déjà invalide ne doit pas bloquer la sortie */
    }
  }
  if (redirectTo) window.location.replace(appUrl(redirectTo));
}

/* --------------------------------------------------------------------------
   3. Profil
   -------------------------------------------------------------------------- */

/**
 * Profil du membre connecté (rôle, activation, coordonnées).
 * @param {string} userId
 * @returns {Promise<{ profile: null|Record<string, unknown>, error: unknown }>}
 */
export async function fetchProfile(userId) {
  if (!supabase) return { profile: null, error: new Error(CONFIG_ERROR) };
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, email, phone, role, is_active, created_at")
    .eq("id", userId)
    .maybeSingle();

  if (error) return { profile: null, error };
  return { profile: data ?? null, error: null };
}

/**
 * Session + profil en un seul appel, avec contrôle du compte.
 * Retourne `{ session: null }` si personne n'est connecté.
 * @returns {Promise<{ session: any|null, profile: Record<string, any>|null, error: unknown }>}
 */
export async function getAuthenticatedProfile() {
  const { session, error } = await getSession();
  if (error || !session) return { session: null, profile: null, error };

  const { profile, error: profileError } = await fetchProfile(session.user.id);
  return { session, profile, error: profileError };
}

/* --------------------------------------------------------------------------
   4. Mot de passe
   -------------------------------------------------------------------------- */

/**
 * Envoie un lien de réinitialisation vers l'adresse indiquée.
 * La réponse est volontairement neutre : elle ne doit pas révéler
 * l'existence ou non d'un compte.
 * @param {string} email
 */
export async function requestPasswordReset(email) {
  if (!supabase) return { ok: false, error: new Error(CONFIG_ERROR) };

  const { error } = await supabase.auth.resetPasswordForEmail(
    String(email).trim().toLowerCase(),
    { redirectTo: appUrl("reset-password.html") }
  );

  // Une erreur de limitation de débit est la seule à signaler explicitement.
  if (error && /rate limit|too many requests/i.test(`${error.code} ${error.message}`)) {
    return { ok: false, error };
  }
  return { ok: true, error: null };
}

/**
 * Remplace le mot de passe de la session courante (lien de récupération).
 * @param {string} password
 */
export async function updatePassword(password) {
  if (!supabase) return { ok: false, error: new Error(CONFIG_ERROR) };
  const { error } = await supabase.auth.updateUser({ password });
  return { ok: !error, error };
}
