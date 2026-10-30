/* ==========================================================================
   Cœur d'Honneur — app-shell.js
   ---------------------------------------------------------------------------
   Coque commune des espaces privés : barre latérale, barre supérieure,
   tiroir mobile, déconnexion.

   Une seule source de vérité pour la navigation : les pages ne décrivent que
   leur contenu et déclarent la rubrique active.

       mountShell({ role: "member", active: "payment" });
       paintIdentity(profile);
   ========================================================================== */

import { signOut } from "./auth.js";

const ICONS = {
  grid: '<rect x="3" y="3" width="7" height="9" rx="2"/><rect x="14" y="3" width="7" height="5" rx="2"/><rect x="14" y="12" width="7" height="9" rx="2"/><rect x="3" y="16" width="7" height="5" rx="2"/>',
  wallet:
    '<path d="M3 8a2 2 0 0 1 2-2h11a2 2 0 0 1 2 2"/><path d="M3 8v9a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2H5a2 2 0 0 1-2-2Z"/><path d="M16 13h.01"/>',
  list: '<path d="M8 6h13"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M3 6h.01"/><path d="M3 12h.01"/><path d="M3 18h.01"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  users:
    '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  layers:
    '<path d="m12 2 10 6-10 6L2 8l10-6Z"/><path d="m2 14 10 6 10-6"/>',
  chart:
    '<path d="M3 3v18h18"/><path d="M7 16v-5"/><path d="M12 16V8"/><path d="M17 16v-3"/>',
  sliders:
    '<path d="M4 21v-7"/><path d="M4 10V3"/><path d="M12 21v-9"/><path d="M12 8V3"/><path d="M20 21v-5"/><path d="M20 12V3"/><path d="M2 14h4"/><path d="M10 8h4"/><path d="M18 16h4"/>',
  alert:
    '<path d="M10.3 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.7 3.86a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  shield: '<path d="M12 3 4 6v6c0 4.4 3.4 8.3 8 9 4.6-.7 8-4.6 8-9V6l-8-3Z"/>',
  logout:
    '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>',
};

const BRAND_MARK =
  '<path d="M19.5 12.6 12 20l-7.5-7.4a4.6 4.6 0 0 1 0-6.5 4.6 4.6 0 0 1 6.5 0l1 1 1-1a4.6 4.6 0 0 1 6.5 0 4.6 4.6 0 0 1 0 6.5Z"/>';

const MENUS = {
  member: [
    {
      title: "Espace membre",
      items: [
        { key: "dashboard", label: "Tableau de bord", href: "dashboard.html", icon: "grid" },
        { key: "payment", label: "Déclarer un versement", href: "payment.html", icon: "wallet" },
        { key: "history", label: "Historique", href: "history.html", icon: "list" },
        { key: "profile", label: "Mon profil", href: "profile.html", icon: "user" },
      ],
    },
  ],
  admin: [
    {
      title: "Administration",
      items: [
        { key: "dashboard", label: "Tableau de bord", href: "index.html", icon: "grid" },
        { key: "members", label: "Membres", href: "members.html", icon: "users" },
        { key: "arrears", label: "Retards", href: "arrears.html", icon: "alert" },
        { key: "tiers", label: "Paliers", href: "tiers.html", icon: "layers" },
        { key: "reports", label: "Rapports", href: "reports.html", icon: "chart" },
        { key: "settings", label: "Paramètres", href: "settings.html", icon: "sliders" },
      ],
    },
    {
      title: "Mon compte",
      items: [{ key: "member-space", label: "Mon espace membre", href: "../dashboard.html", icon: "user" }],
    },
  ],
};

function link(item, active) {
  const isActive = item.key === active;
  return `
    <a class="nav-link${isActive ? " is-active" : ""}" href="${item.href}"
       ${isActive ? 'aria-current="page"' : ""}>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
        stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[item.icon] ?? ""}</svg>
      ${item.label}
    </a>`;
}

function sidebarHtml(role, active, prefix) {
  const menu = MENUS[role] ?? MENUS.member;

  const groups = menu
    .map(
      (group) => `
      <p class="sidebar__group">${group.title}</p>
      ${group.items.map((item) => link(item, active)).join("")}`
    )
    .join("");

  // Emplacement réservé au lien d'administration : rempli seulement si le
  // profil connecté a le rôle admin (donnée lue en base, jamais devinée).
  const adminSlot =
    role === "member"
      ? `<div id="shell-admin-slot" hidden>
          <p class="sidebar__group">Administration</p>
          <a class="nav-link" href="admin/index.html">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
              stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS.shield}</svg>
            Administration
          </a>
        </div>`
      : "";

  return `
    <a class="brand sidebar__brand" href="${prefix}index.html" aria-label="Cœur d'Honneur, accueil">
      <span class="brand__mark" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
          stroke-linecap="round" stroke-linejoin="round">${BRAND_MARK}</svg>
      </span>
      <span class="brand__word">Cœur d’Honneur</span>
    </a>

    <nav class="sidebar__nav" aria-label="Sections">${groups}${adminSlot}</nav>

    <div class="sidebar__foot">
      <div class="user-chip">
        <span class="avatar" id="user-initials" aria-hidden="true">—</span>
        <span class="user-chip__text">
          <span class="user-chip__name" id="user-name">Chargement…</span>
          <span class="user-chip__role" id="user-role">Membre</span>
        </span>
      </div>

      <button style="color:white;"class="btn btn--ghost btn--sm btn--block" type="button" data-logout>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
          stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
          style="width: 16px; height: 16px">${ICONS.logout}</svg>
        Se déconnecter
      </button>
    </div>`;
}

function topbarHtml(prefix) {
  return `
    <button class="btn btn--ghost btn--icon topbar__toggle" type="button" id="sidebar-toggle"
      aria-expanded="false" aria-controls="app-sidebar" aria-label="Ouvrir le menu">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
        stroke-linecap="round" aria-hidden="true">
        <path d="M4 7h16"/><path d="M4 12h16"/><path d="M4 17h16"/>
      </svg>
    </button>

    <div class="topbar__hello">
      <span class="topbar__name" id="topbar-name">Bonjour</span>
      <span class="topbar__date" id="topbar-date"></span>
    </div>

    <span class="topbar__spacer"></span>

    <a class="btn btn--ghost btn--sm" href="${prefix}index.html">Voir le site</a>`;
}

/* --------------------------------------------------------------------------
   Montage
   -------------------------------------------------------------------------- */

/**
 * Remplit la barre latérale et la barre supérieure.
 * @param {{ role?: "member"|"admin", active?: string, prefix?: string }} options
 */
export function mountShell({ role = "member", active = "", prefix = "" } = {}) {
  const sidebar = document.getElementById("app-sidebar");
  const topbar = document.getElementById("app-topbar");

  if (sidebar) sidebar.innerHTML = sidebarHtml(role, active, prefix);
  if (topbar) topbar.innerHTML = topbarHtml(prefix);

  initDrawer();
  initLogout(prefix);
}

/**
 * Affiche l'identité du membre connecté.
 * @param {{ full_name?: string, email?: string, role?: string }} profile
 */
export function paintIdentity(profile = {}) {
  const name = profile.full_name || profile.email || "Membre";
  const first = String(name).split(" ")[0];

  setText("user-name", name);
  setText("user-initials", initialsOf(name));
  setText("user-role", profile.role === "admin" ? "Administrateur" : "Membre");
  setText("topbar-name", `Bonjour, ${first}`);
  setText(
    "topbar-date",
    new Intl.DateTimeFormat("fr-FR", {
      weekday: "long",
      day: "numeric",
      month: "long",
      year: "numeric",
    }).format(new Date())
  );

  const adminSlot = document.getElementById("shell-admin-slot");
  if (adminSlot) adminSlot.hidden = profile.role !== "admin";
}

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

function initialsOf(name) {
  return String(name)
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join("");
}

/**
 * Met à jour uniquement le nom affiché (après modification du profil),
 * sans avoir à recharger la page.
 * @param {{ full_name?: string }} partial
 */
export function refreshIdentity(partial = {}) {
  const current = document.getElementById("user-name")?.textContent ?? "Membre";
  const name = partial.full_name?.trim() || current;

  setText("user-name", name);
  setText("user-initials", initialsOf(name));
  setText("topbar-name", `Bonjour, ${String(name).split(" ")[0]}`);
}

/* --------------------------------------------------------------------------
   Interactions
   -------------------------------------------------------------------------- */
function initDrawer() {
  const sidebar = document.getElementById("app-sidebar");
  const scrim = document.getElementById("scrim");
  const toggle = document.getElementById("sidebar-toggle");
  if (!sidebar || !scrim || !toggle) return;

  const setOpen = (open) => {
    sidebar.classList.toggle("is-open", open);
    scrim.hidden = !open;
    scrim.classList.toggle("is-visible", open);
    toggle.setAttribute("aria-expanded", String(open));
  };

  toggle.addEventListener("click", () => setOpen(!sidebar.classList.contains("is-open")));
  scrim.addEventListener("click", () => setOpen(false));
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setOpen(false);
  });
  sidebar.addEventListener("click", (event) => {
    if (event.target.closest("a")) setOpen(false);
  });
}

function initLogout(prefix = "") {
  document.querySelectorAll("[data-logout]").forEach((button) => {
    button.addEventListener("click", async () => {
      button.disabled = true;
      await signOut({ redirectTo: `${prefix}index.html` });
    });
  });
}
