-- ===========================================================================
-- Cœur d'Honneur — patch-01-admin.sql
-- ---------------------------------------------------------------------------
-- À exécuter UNE SEULE FOIS, dans le SQL Editor de Supabase, si
-- bootstrap-admin.sql a échoué avec :
--     ERROR 42501: Le rôle ne peut pas être modifié par le membre
--
-- Cause : le garde-fou de la table profiles lisait auth.uid(). Dans l'éditeur
-- SQL, il n'y a pas de jeton d'authentification, donc auth.uid() vaut NULL :
-- la fonction prenait l'administrateur pour un membre.
--
-- Ce fichier :
--   1. corrige la fonction de garde (elle ne s'applique plus qu'aux appels
--      venant de l'API, plus jamais à la console SQL ni au backend) ;
--   2. garantit que la ligne de profil existe pour le compte visé ;
--   3. promeut le compte en administrateur ;
--   4. affiche le résultat.
--
-- Le fichier est idempotent : on peut le relancer sans risque.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Fonction de garde corrigée
--    Le rôle JWT n'est lu que s'il existe. En console SQL (session directe),
--    'request.jwt.claims' est vide : la garde s'efface.
-- ---------------------------------------------------------------------------
create or replace function public.profiles_guard_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_api_role text := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
begin
  -- Console SQL, migrations, scripts : aucune restriction.
  -- Backend de confiance (clé service_role) : aucune restriction.
  if v_api_role is null or v_api_role = 'service_role' then
    return new;
  end if;

  -- Appel venu du navigateur : seul un administrateur peut changer ces champs.
  if not public.is_admin() then
    if new.role is distinct from old.role then
      raise exception 'Le rôle ne peut pas être modifié par le membre'
        using errcode = '42501';
    end if;

    if new.is_active is distinct from old.is_active then
      raise exception 'Le statut du compte ne peut pas être modifié par le membre'
        using errcode = '42501';
    end if;

    if new.email is distinct from old.email then
      raise exception 'L''adresse e-mail se modifie via le mécanisme d''authentification'
        using errcode = '42501';
    end if;

    if new.tier_id is distinct from old.tier_id then
      raise exception 'La tranche de cotisation est attribuée par l''administration'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. S'assurer que le profil existe
--    Si le compte a été créé avant l'installation du schéma, le déclencheur
--    handle_new_user n'a pas pu tourner : on crée la ligne manquante.
-- ---------------------------------------------------------------------------
insert into public.profiles (id, full_name, email)
select
  u.id,
  coalesce(
    nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
    split_part(coalesce(u.email, 'membre'), '@', 1)
  ),
  coalesce(u.email, '')
from auth.users u
where lower(u.email) = lower('vienscoder@gmail.com')   -- ← REMPLACER SI BESOIN
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Promotion en administrateur
-- ---------------------------------------------------------------------------
update public.profiles
set role = 'admin',
    is_active = true
where lower(email) = lower('vienscoder@gmail.com');     -- ← REMPLACER SI BESOIN

-- ---------------------------------------------------------------------------
-- 4. Vérification : role doit valoir « admin » et is_active « true »
-- ---------------------------------------------------------------------------
select
  id,
  full_name,
  email,
  role,
  is_active,
  tier_id,
  created_at
from public.profiles
where lower(email) = lower('vienscoder@gmail.com');     -- ← REMPLACER SI BESOIN
