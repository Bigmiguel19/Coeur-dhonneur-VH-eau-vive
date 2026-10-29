-- ===========================================================================
-- Cœur d'Honneur — bootstrap-admin.sql
-- Création sécurisée du PREMIER administrateur.
--
-- Pourquoi cette procédure manuelle ?
--   Aucun chemin d'auto-promotion n'existe dans l'application : ni dans
--   l'interface, ni dans une politique RLS, ni dans une fonction exposée au
--   navigateur. Le premier administrateur est donc désigné par une personne
--   ayant déjà accès au tableau de bord Supabase.
--
-- PROCÉDURE
--   1. Supabase → Authentication → Users → « Add user »
--        e-mail  : l'adresse de l'administrateur
--        mot de passe : un mot de passe solide, communiqué en privé
--        cocher « Auto Confirm User »
--      Le trigger handle_new_user crée automatiquement la ligne profiles.
--
--   2. Exécuter la requête 1 ci-dessous en remplaçant l'adresse e-mail.
--
--   ⚠️  Cette requête ne fonctionne QUE depuis le SQL Editor de Supabase
--       (session directe, sans jeton). Depuis le navigateur, la modification
--       du rôle est refusée par conception : c'est la garantie qu'aucun membre
--       ne peut s'auto-promouvoir.
--       Si l'exécution renvoie « 42501: Le rôle ne peut pas être modifié par
--       le membre », c'est que la fonction de garde est l'ancienne version :
--       exécuter d'abord patch-01-admin.sql, puis relancer ce fichier.
--
--   3. Vérifier le résultat affiché : la colonne role doit valoir « admin ».
--
--   4. Se connecter à la plateforme avec ce compte.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Promotion (à personnaliser)
-- ---------------------------------------------------------------------------
update public.profiles
set role = 'admin',
    is_active = true
where lower(email) = lower('admin@gmail.com');   -- ← REMPLACER

-- Contrôle immédiat
select id, full_name, email, role, is_active, created_at
from public.profiles
where lower(email) = lower('admin@gmail.com');   -- ← REMPLACER

-- ---------------------------------------------------------------------------
-- 2. Vérification que la promotion a bien eu lieu
--    (à exécuter après la requête 1 : doit renvoyer 1)
-- ---------------------------------------------------------------------------
-- select count(*) as administrateurs_actifs
-- from public.profiles
-- where role = 'admin' and is_active;

-- ---------------------------------------------------------------------------
-- 3. Création des membres suivants
--    Toujours via Authentication → Users (ou par la fonction serveur
--    /api/create-member), jamais par insertion directe dans auth.users.
--    Puis attribuer la tranche de cotisation :
-- ---------------------------------------------------------------------------
-- update public.profiles
-- set tier_id = (
--   select id from public.contribution_tiers
--   where monthly_amount = 2000 and is_active
-- )
-- where lower(email) = lower('membre@exemple.com');

-- ---------------------------------------------------------------------------
-- 4. En cas d'erreur : retirer le rôle administrateur
-- ---------------------------------------------------------------------------
-- update public.profiles
-- set role = 'member'
-- where lower(email) = lower('admin@exemple.com');
