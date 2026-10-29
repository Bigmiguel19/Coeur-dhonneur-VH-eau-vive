/* ==========================================================================
   Cœur d'Honneur — utils.js
   Fonctions pures et sans dépendance : formatage, validation, manipulation
   du DOM. Aucun accès réseau, aucune référence à Supabase.

   Devise : XOF (franc CFA BCEAO), format français, sans décimale.
   ========================================================================== */

/** Locale unique de l'application. */
export const LOCALE = "fr-FR";

/** Devise par défaut ; peut être surchargée par app_settings.currency. */
export const DEFAULT_CURRENCY = "XOF";

/* --------------------------------------------------------------------------
   1. Montants
   -------------------------------------------------------------------------- */

/**
 * Formate un montant en FCFA : 12 000 FCFA
 * @param {number|string} amount
 * @param {string} [currency]
 * @returns {string}
 */
export function formatMoney(amount, currency = DEFAULT_CURRENCY) {
  const value = toNumber(amount);
  return new Intl.NumberFormat(LOCALE, {
    style: "currency",
    currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value);
}

/**
 * Formate un nombre sans symbole monétaire : 12 000
 */
export function formatNumber(value) {
  return new Intl.NumberFormat(LOCALE, {
    maximumFractionDigits: 0,
  }).format(toNumber(value));
}

/**
 * Convertit une saisie utilisateur ("1 500", "1500,50", "1.500") en nombre.
 * Retourne 0 si la valeur n'est pas numérique.
 */
export function toNumber(input) {
  if (typeof input === "number") return Number.isFinite(input) ? input : 0;
  if (input === null || input === undefined) return 0;
  const cleaned = String(input)
    .replace(/[\s\u00A0\u202F]/g, "")
    .replace(/FCFA/gi, "")
    .replace(",", ".")
    .replace(/[^\d.-]/g, "");
  const value = Number.parseFloat(cleaned);
  return Number.isFinite(value) ? value : 0;
}

/**
 * Formate un montant « compact » pour les graphiques : 12,5 k.
 */
export function formatCompact(amount) {
  const value = toNumber(amount);
  if (Math.abs(value) >= 1_000_000) {
    return `${new Intl.NumberFormat(LOCALE, { maximumFractionDigits: 1 }).format(value / 1_000_000)} M`;
  }
  if (Math.abs(value) >= 1_000) {
    return `${new Intl.NumberFormat(LOCALE, { maximumFractionDigits: 1 }).format(value / 1_000)} k`;
  }
  return formatNumber(value);
}

/* --------------------------------------------------------------------------
   2. Dates
   -------------------------------------------------------------------------- */

/** "12 octobre 2026" */
export function formatDate(value) {
  const date = toDate(value);
  if (!date) return "—";
  return new Intl.DateTimeFormat(LOCALE, {
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(date);
}

/** "12/10/2026" */
export function formatDateShort(value) {
  const date = toDate(value);
  if (!date) return "—";
  return new Intl.DateTimeFormat(LOCALE, {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(date);
}

/** "aujourd'hui", "hier", "il y a 3 j", sinon date courte */
export function formatRelative(value) {
  const date = toDate(value);
  if (!date) return "—";
  const today = startOfDay(new Date());
  const target = startOfDay(date);
  const diffDays = Math.round((today - target) / 86_400_000);

  if (diffDays === 0) return "aujourd'hui";
  if (diffDays === 1) return "hier";
  if (diffDays > 1 && diffDays < 7) return `il y a ${diffDays} j`;
  return formatDateShort(date);
}

/** Valeur pour un <input type="date"> (AAAA-MM-JJ), en heure locale. */
export function toDateInputValue(value = new Date()) {
  const date = toDate(value);
  if (!date) return "";
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 10);
}

/** Noms de mois en français : MOIS[0] === "janvier". */
export const MOIS = [
  "janvier",
  "février",
  "mars",
  "avril",
  "mai",
  "juin",
  "juillet",
  "août",
  "septembre",
  "octobre",
  "novembre",
  "décembre",
];

export function monthLabel(year, month) {
  const name = MOIS[Math.max(0, Math.min(11, Number(month) - 1))] ?? "";
  return `${name.charAt(0).toUpperCase()}${name.slice(1)} ${year}`;
}

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function startOfDay(date) {
  const copy = new Date(date);
  copy.setHours(0, 0, 0, 0);
  return copy;
}

/* --------------------------------------------------------------------------
   3. Validation
   -------------------------------------------------------------------------- */

/**
 * Valide un e-mail de façon permissive mais utile.
 */
export function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test(String(value ?? "").trim());
}

/**
 * Valide un numéro de téléphone ivoirien ou international.
 * Accepte : 07 00 00 00 00, +2250700000000, 0700000000.
 */
export function isValidPhone(value) {
  const digits = String(value ?? "").replace(/[^\d+]/g, "");
  return /^\+?\d{8,15}$/.test(digits);
}

/**
 * Nettoie un nom : espaces multiples supprimés, bornes retirées.
 */
export function normalizeName(value) {
  return String(value ?? "")
    .replace(/\s+/g, " ")
    .trim();
}

/* --------------------------------------------------------------------------
   4. Sécurité — redirections internes uniquement
   -------------------------------------------------------------------------- */

/**
 * N'accepte qu'un chemin relatif de même origine ("/dashboard.html?x=1").
 * Retourne `fallback` pour toute tentative d'URL absolue ou de protocole.
 */
export function safeNextPath(candidate, fallback = "dashboard.html") {
  if (!candidate || typeof candidate !== "string") return fallback;
  const value = candidate.trim();
  if (!value.startsWith("/") || value.startsWith("//")) return fallback;
  if (/^\\/.test(value)) return fallback;
  if (/^[a-z]+:/i.test(value)) return fallback;
  return value.slice(1);
}

/* --------------------------------------------------------------------------
   5. DOM
   -------------------------------------------------------------------------- */

/**
 * Raccourci de sélection.
 */
export function $(selector, scope = document) {
  return scope.querySelector(selector);
}

export function $$(selector, scope = document) {
  return Array.from(scope.querySelectorAll(selector));
}

/**
 * Crée un élément avec attributs et contenu.
 * createEl("button", { class: "btn", type: "button" }, "Valider")
 */
export function createEl(tag, attributes = {}, children = []) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attributes)) {
    if (value === null || value === undefined || value === false) continue;
    if (key === "class") el.className = value;
    else if (key === "dataset") Object.assign(el.dataset, value);
    else if (key.startsWith("on") && typeof value === "function") {
      el.addEventListener(key.slice(2).toLowerCase(), value);
    } else if (key === "text") el.textContent = value;
    else el.setAttribute(key, value === true ? "" : String(value));
  }
  for (const child of [].concat(children)) {
    if (child === null || child === undefined) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

/**
 * Échappe une chaîne avant insertion dans innerHTML.
 * Préférer textContent ; cette fonction sert aux rares gabarits HTML.
 */
export function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Initiales pour les avatars : "Grâce Kouassi" → "GK".
 */
export function initials(fullName = "") {
  return normalizeName(fullName)
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join("");
}

/**
 * Empêche les doubles soumissions : désactive le bouton pendant l'attente.
 * Le bouton reprend son état initial en cas d'erreur.
 */
export async function withSubmitLock(button, task) {
  if (!button || button.dataset.busy === "true") return undefined;
  button.dataset.busy = "true";
  button.classList.add("is-loading");
  button.disabled = true;
  try {
    return await task();
  } finally {
    button.dataset.busy = "false";
    button.classList.remove("is-loading");
    button.disabled = false;
  }
}

/**
 * Retarde l'exécution (utile pour les champs de recherche).
 */
export function debounce(fn, delay = 300) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
}
