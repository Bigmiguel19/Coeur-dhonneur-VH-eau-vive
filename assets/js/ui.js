/* ==========================================================================
   Cœur d'Honneur — ui.js
   Comportements d'interface partagés par toutes les pages :
   notifications toast, apparition au défilement, menu mobile,
   affichage du mot de passe, fenêtres de confirmation, états de chargement.

   Ce module n'accède ni au réseau ni à Supabase.
   ========================================================================== */

import { $, $$, createEl } from "./utils.js";

/* --------------------------------------------------------------------------
   1. Notifications toast
   -------------------------------------------------------------------------- */
const TOAST_ICONS = {
  success: '<path d="m5 12 4 4L19 6"/>',
  error: '<path d="M12 8v5"/><path d="M12 16h.01"/>',
  warning: '<path d="M12 9v4"/><path d="M12 17h.01"/>',
  info: '<path d="M12 8h.01"/><path d="M11 12h1v5h1"/>',
};

const TOAST_LABELS = {
  success: "Succès",
  error: "Erreur",
  warning: "Attention",
  info: "Information",
};

let toastRegion = null;

function ensureToastRegion() {
  if (toastRegion?.isConnected) return toastRegion;
  toastRegion = $("#toast-region");
  if (!toastRegion) {
    toastRegion = createEl("div", {
      id: "toast-region",
      class: "toast-stack",
      role: "status",
      "aria-live": "polite",
      "aria-atomic": "false",
    });
    document.body.append(toastRegion);
  }
  return toastRegion;
}

/**
 * Affiche une notification non bloquante.
 * @param {string} message
 * @param {"success"|"error"|"warning"|"info"} [type]
 * @param {{ title?: string, duration?: number }} [options]
 */
export function toast(message, type = "info", options = {}) {
  const { title = TOAST_LABELS[type] ?? "", duration = 5000 } = options;
  const region = ensureToastRegion();

  const icon = createEl("span", { class: "toast__icon", "aria-hidden": "true" });
  icon.innerHTML = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none"
    stroke="currentColor" stroke-width="2.4" stroke-linecap="round"
    stroke-linejoin="round">${TOAST_ICONS[type] ?? TOAST_ICONS.info}</svg>`;

  const closeBtn = createEl("button", {
    type: "button",
    class: "toast__close",
    "aria-label": "Fermer la notification",
  });
  closeBtn.innerHTML =
    '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M18 6 6 18M6 6l12 12"/></svg>';

  const content = createEl("div", { class: "toast__content" });
  if (title) content.append(createEl("p", { class: "toast__title", text: title }));
  content.append(createEl("p", { text: message }));

  const el = createEl("div", { class: `toast toast--${type}`, role: "alert" }, [
    icon,
    content,
    closeBtn,
  ]);

  const remove = () => {
    if (!el.isConnected) return;
    el.classList.add("is-leaving");
    el.addEventListener("animationend", () => el.remove(), { once: true });
    // Filet de sécurité si l'animation est neutralisée
    setTimeout(() => el.remove(), 400);
  };

  closeBtn.addEventListener("click", remove);
  region.append(el);

  if (duration > 0) setTimeout(remove, duration);
  return { close: remove, element: el };
}

/* --------------------------------------------------------------------------
   2. Apparition au défilement
   -------------------------------------------------------------------------- */
let revealObserver = null;

export function initReveal(scope = document) {
  const targets = $$(".reveal:not(.is-visible)", scope);
  if (!targets.length) return;

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduced || !("IntersectionObserver" in window)) {
    targets.forEach((el) => el.classList.add("is-visible"));
    return;
  }

  if (!revealObserver) {
    revealObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.classList.add("is-visible");
          revealObserver.unobserve(entry.target);
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );
  }

  targets.forEach((el) => revealObserver.observe(el));
}

/* --------------------------------------------------------------------------
   3. Menu mobile
   -------------------------------------------------------------------------- */
export function initMobileNav() {
  const toggle = $("[data-nav-toggle]");
  const menu = $("[data-mobile-menu]");
  if (!toggle || !menu) return;

  const setOpen = (open) => {
    toggle.setAttribute("aria-expanded", String(open));
    menu.hidden = !open;
  };

  toggle.addEventListener("click", () => {
    setOpen(menu.hidden);
  });

  // Fermeture au clavier et après un clic sur un lien
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !menu.hidden) {
      setOpen(false);
      toggle.focus();
    }
  });

  menu.addEventListener("click", (event) => {
    if (event.target.closest("a")) setOpen(false);
  });
}

/* --------------------------------------------------------------------------
   4. Affichage / masquage du mot de passe
   -------------------------------------------------------------------------- */
const EYE_OPEN =
  '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>';
const EYE_OFF =
  '<path d="M3 3l18 18"/><path d="M10.6 6.3A9.7 9.7 0 0 1 12 6c6.5 0 10 6 10 6a17 17 0 0 1-3.2 3.9"/><path d="M6.2 7.5A16.4 16.4 0 0 0 2 12s3.5 6 10 6a9.9 9.9 0 0 0 4-.8"/><path d="M9.9 10a3 3 0 0 0 4.2 4.2"/>';

export function initPasswordToggles(scope = document) {
  $$("[data-password-toggle]", scope).forEach((button) => {
    const input = document.getElementById(button.dataset.passwordToggle);
    if (!input) return;

    const paint = (visible) => {
      button.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
        stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${
          visible ? EYE_OFF : EYE_OPEN
        }</svg>`;
      button.setAttribute("aria-pressed", String(visible));
      button.setAttribute(
        "aria-label",
        visible ? "Masquer le mot de passe" : "Afficher le mot de passe"
      );
    };

    paint(false);
    button.addEventListener("click", () => {
      const visible = input.type === "password";
      input.type = visible ? "text" : "password";
      paint(visible);
      input.focus({ preventScroll: true });
    });
  });
}

/* --------------------------------------------------------------------------
   5. Fenêtres de confirmation (élément <dialog> natif)
   -------------------------------------------------------------------------- */

/**
 * Ouvre une confirmation accessible et renvoie une promesse booléenne.
 * Le focus est piégé nativement par <dialog>, Échap annule.
 *
 * @param {{ title: string, message: string, confirmLabel?: string,
 *           cancelLabel?: string, tone?: "danger"|"primary" }} options
 * @returns {Promise<boolean>}
 */
export function confirmDialog(options) {
  const {
    title,
    message,
    confirmLabel = "Confirmer",
    cancelLabel = "Annuler",
    tone = "primary",
  } = options;

  const dialog = createEl("dialog", { class: "dialog" });
  const isDanger = tone === "danger";

  dialog.innerHTML = `
    <div class="dialog__head">
      <h2 class="dialog__title"></h2>
      <button type="button" class="btn btn--ghost btn--icon btn--sm" data-cancel
        aria-label="Fermer">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
          stroke-linecap="round"><path d="M18 6 6 18M6 6l12 12"/></svg>
      </button>
    </div>
    <div class="dialog__body"><p data-message></p></div>
    <div class="dialog__foot">
      <button type="button" class="btn btn--secondary" data-cancel></button>
      <button type="button" class="btn ${isDanger ? "btn--danger" : "btn--primary"}"
        data-confirm></button>
    </div>
  `;

  // Contenu inséré en texte : aucune injection HTML possible
  dialog.querySelector(".dialog__title").textContent = title;
  dialog.querySelector("[data-message]").textContent = message;
  dialog.querySelector("[data-confirm]").textContent = confirmLabel;
  dialog.querySelectorAll(".dialog__foot [data-cancel]")[0].textContent =
    cancelLabel;

  document.body.append(dialog);

  return new Promise((resolve) => {
    const finish = (value) => {
      dialog.close();
      dialog.remove();
      resolve(value);
    };

    dialog.querySelector("[data-confirm]").addEventListener("click", () => finish(true));
    dialog.querySelectorAll("[data-cancel]").forEach((btn) =>
      btn.addEventListener("click", () => finish(false))
    );
    dialog.addEventListener("cancel", (event) => {
      event.preventDefault();
      finish(false);
    });
    dialog.addEventListener("click", (event) => {
      // Clic sur le fond (backdrop)
      if (event.target === dialog) finish(false);
    });

    dialog.showModal();
    dialog.querySelector("[data-confirm]").focus();
  });
}

/* --------------------------------------------------------------------------
   6. Erreurs de formulaire
   -------------------------------------------------------------------------- */

/**
 * Affiche ou efface le message d'erreur d'un champ.
 * @param {HTMLElement} input
 * @param {string} [message] message vide ou absent = effacement
 */
export function setFieldError(input, message = "") {
  const field = input.closest(".field");
  if (!field) return;
  const slot = field.querySelector(".field__error");

  if (message) {
    field.classList.add("has-error");
    input.setAttribute("aria-invalid", "true");
    if (input.id) input.setAttribute("aria-describedby", `${input.id}-error`);
    if (slot) {
      slot.id = `${input.id}-error`;
      slot.innerHTML =
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 8v4"/><path d="M12 16h.01"/></svg>';
      slot.append(document.createTextNode(message));
    }
  } else {
    field.classList.remove("has-error");
    input.removeAttribute("aria-invalid");
    if (slot) slot.textContent = "";
  }
}

/**
 * Efface les erreurs dès que l'utilisateur corrige sa saisie.
 */
export function bindFieldCleanup(form) {
  form.addEventListener("input", (event) => {
    const target = event.target;
    if (target instanceof HTMLElement && target.matches(".input, .select, .textarea")) {
      setFieldError(target, "");
    }
  });
}

/* --------------------------------------------------------------------------
   7. Comptage animé des statistiques
   -------------------------------------------------------------------------- */
export function countUp(element, target, { duration = 900, format } = {}) {
  const end = Number(target) || 0;
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (reduced) {
    element.textContent = format ? format(end) : String(end);
    return;
  }

  const start = performance.now();
  const tick = (now) => {
    const progress = Math.min(1, (now - start) / duration);
    const eased = 1 - Math.pow(1 - progress, 3);
    const value = Math.round(end * eased);
    element.textContent = format ? format(value) : String(value);
    if (progress < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

/* --------------------------------------------------------------------------
   8. Initialisation commune à toutes les pages
   -------------------------------------------------------------------------- */
export function initPage() {
  initReveal();
  initMobileNav();
  initPasswordToggles();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initPage, { once: true });
} else {
  initPage();
}
