-- ===========================================================================
-- Cœur d'Honneur — patch-04-admin-members.sql
-- ---------------------------------------------------------------------------
-- À exécuter dans le SQL Editor de Supabase. Idempotent.
--
-- Objet : ouvrir à l'administration, depuis le navigateur, la gestion des
-- membres : palier de cotisation, activation du compte et rôle.
-- Auparavant, seules full_name et phone étaient modifiables en ligne —
-- le reste exigeait la console SQL ou la clé service_role.
--
-- Ce qui change :
--   1. Une politique d'update « administrateur » sur profiles, à côté de
--      l'update « soi-même » déjà existant (les politiques permissives
--      s'additionnent) ;
--   2. Les colonnes tier_id, is_active et role ouvertes en UPDATE.
--
-- Pourquoi un membre ne peut toujours rien faire de tout cela :
--   — RLS : la politique « soi-même » ne porte que sur sa propre ligne ;
--   — trigger profiles_guard_update : toute modification de role, is_active
--     ou tier_id par un non-administrateur est refusée (42501) ;
--   — le trigger est SECURITY DEFINER et lit le rôle réel en base.
--
-- Aucun DELETE n'est ouvert : la trace des comptes est conservée.
-- ===========================================================================

-- 1. Un administrateur connecté peut modifier n'importe quel profil
drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin
  on public.profiles
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 2. Colonnes ouvertes (full_name et phone l'étaient déjà pour le membre)
grant update (full_name, phone, tier_id, is_active, role)
  on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- Vérification
-- ---------------------------------------------------------------------------
select
  (select count(*) from public.profiles where role = 'admin' and is_active) as administrateurs_actifs,
  (select count(*) from public.profiles where role = 'member' and is_active) as membres_actifs,
  (select count(*) from public.profiles where role = 'member' and not is_active) as membres_suspendus,
  (select count(*) from public.profiles where role = 'member' and tier_id is null) as membres_sans_palier;

-- Test manuel (décommenter, coller un identifiant) :
-- update public.profiles
-- set is_active = false
-- where id = 'COLLER-L-IDENTIFIANT-ICI';

-- ===========================================================================
-- Fin de patch-04-admin-members.sql
-- ===========================================================================
