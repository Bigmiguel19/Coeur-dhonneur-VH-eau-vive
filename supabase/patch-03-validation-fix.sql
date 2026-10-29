-- ===========================================================================
-- Cœur d'Honneur — patch-03-validation-fix.sql
-- ---------------------------------------------------------------------------
-- À exécuter dans le SQL Editor de Supabase. Idempotent.
--
-- POURQUOI LA VALIDATION ÉCHOUE ENCORE
--
--   Deux verrous indépendants, et c'est le second qui bloque :
--
--   1. La garde exigeait un administrateur via auth.uid(). Or l'éditeur SQL
--      et l'éditeur de table n'ont aucun jeton : auth.uid() vaut NULL.
--      → « 42501: Seule l'administration peut modifier un paiement ».
--
--   2. Même si la garde laisse passer, la contrainte
--      payments_confirmed_requires_validation exige que validated_by soit
--      renseigné pour un statut « confirmed ». Une mise à jour manuelle qui
--      ne fournit que le statut laisse validated_by à NULL.
--      → « violates check constraint payments_confirmed_requires_validation ».
--
--   Le trigger prend maintenant sa décision sur auth.uid() (et non sur le
--   contenu des jetons JWT, qui n'est pas homogène d'un canal à l'autre) :
--
--     — session navigateur  → contrôle d'administration conservé ;
--     — aucun jeton         → éditeur SQL, migration, backend service_role :
--                             action autorisée, auteur résolu automatiquement ;
--     — anon / authenticated sans droit : les GRANT et les RLS restent la
--       barrière, le trigger n'est jamais atteint.
--
-- À la fin : le bloc de vérification affiche le résultat du traitement.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 0. DIAGNOSTIC — lisez ce que la console voit avant de corriger
--    (exécutez cette section seule si vous voulez comprendre le contexte)
-- ---------------------------------------------------------------------------
select
  current_user                                             as role_connexion,
  session_user                                             as utilisateur_session,
  auth.uid()                                               as utilisateur_jeton,
  nullif(current_setting('request.jwt.claims', true), '')  as jetons_bruts;

select
  id,
  member_id,
  amount,
  status,
  validated_at,
  validated_by,
  rejection_reason
from public.payments
order by submitted_at desc
limit 20;


-- ---------------------------------------------------------------------------
-- 1. Contrôle avant insertion — même logique de confiance
-- ---------------------------------------------------------------------------
create or replace function public.payments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_min_amount numeric;
  v_member_ok  boolean;
begin
  -- Session navigateur : un membre ne déclare que pour lui-même.
  if v_uid is not null and not public.is_admin() and new.member_id <> v_uid then
    raise exception 'Vous ne pouvez déclarer un paiement que pour votre propre compte'
      using errcode = '42501';
  end if;

  select is_active into v_member_ok
  from public.profiles
  where id = new.member_id;

  if v_member_ok is not true then
    raise exception 'Compte membre introuvable ou désactivé'
      using errcode = '42501';
  end if;

  select coalesce(min_payment_amount, 500) into v_min_amount
  from public.app_settings
  limit 1;

  v_min_amount := coalesce(v_min_amount, 500);

  if new.amount is null or new.amount < v_min_amount then
    raise exception 'Le montant minimum d''un paiement est de % FCFA', v_min_amount
      using errcode = '22023';
  end if;

  -- Le statut d'une déclaration est toujours « en attente »
  new.status           := 'pending';
  new.validated_at     := null;
  new.validated_by     := null;
  new.rejection_reason := null;
  new.submitted_at     := coalesce(new.submitted_at, now());
  new.payment_date     := coalesce(new.payment_date, current_date);
  new.created_at       := now();
  new.updated_at       := now();

  return new;
end;
$$;


-- ---------------------------------------------------------------------------
-- 2. Contrôle avant mise à jour — le correctif principal
-- ---------------------------------------------------------------------------
create or replace function public.payments_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_admin uuid;
begin
  -- Aucun jeton (éditeur SQL, éditeur de table, migration, service_role) :
  -- la requête ne vient pas d'un navigateur, on ne peut pas exiger
  -- d'administrateur. Les GRANT et les RLS barrent déjà anon/authenticated.
  if v_uid is not null and not public.is_admin() then
    raise exception 'Seule l''administration peut modifier un paiement'
      using errcode = '42501';
  end if;

  if old.status <> 'pending' then
    raise exception 'Ce paiement a déjà été traité (statut : %)', old.status
      using errcode = 'P0001';
  end if;

  if new.status not in ('confirmed', 'rejected') then
    raise exception 'Transition de statut non autorisée : % → %', old.status, new.status
      using errcode = '22023';
  end if;

  if new.status = 'rejected'
     and length(btrim(coalesce(new.rejection_reason, ''))) < 5 then
    raise exception 'Un motif d''au moins 5 caractères est obligatoire en cas de refus'
      using errcode = '22023';
  end if;

  -- Données financières immuables : seul le statut change
  new.member_id    := old.member_id;
  new.amount       := old.amount;
  new.payment_date := old.payment_date;
  new.proof_path   := old.proof_path;
  new.submitted_at := old.submitted_at;
  new.created_at   := old.created_at;

  -- Auteur de la décision : la session si elle existe, sinon celui fourni
  -- par la requête, sinon l'administrateur enregistré.
  new.validated_by := coalesce(v_uid, new.validated_by, old.validated_by);

  if new.validated_by is null then
    select p.id into v_admin
    from public.profiles p
    where p.role = 'admin' and p.is_active
    order by p.created_at
    limit 1;

    new.validated_by := v_admin;
  end if;

  if new.status = 'confirmed' and new.validated_by is null then
    raise exception 'Aucun administrateur actif enregistré : la validation ne peut pas être attribuée'
      using errcode = 'P0001';
  end if;

  new.validated_at := now();
  new.updated_at   := now();

  if new.status = 'confirmed' then
    new.rejection_reason := null;
  end if;

  return new;
end;
$$;


-- ---------------------------------------------------------------------------
-- 3. Garde sur les profils — même critère, pour rester cohérent
-- ---------------------------------------------------------------------------
create or replace function public.profiles_guard_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- Éditeur SQL, migration, service_role : on laisse passer.
  -- Session navigateur d'administration : on laisse passer.
  if v_uid is null or public.is_admin() then
    return new;
  end if;

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

  return new;
end;
$$;


-- ---------------------------------------------------------------------------
-- 4. VÉRIFICATION — exécutez ce bloc tel quel
--    Il valide la plus ancienne déclaration en attente et affiche le résultat.
-- ---------------------------------------------------------------------------
-- update public.payments
-- set status = 'confirmed'
-- where id = (
--   select id from public.payments
--   where status = 'pending'
--   order by submitted_at
--   limit 1
-- );

-- Contrôle après coup : la ligne doit être « confirmed », avec validated_at
-- et validated_by renseignés par le serveur.
-- select id, status, validated_at, validated_by, rejection_reason
-- from public.payments
-- order by submitted_at desc
-- limit 10;

-- ===========================================================================
-- Fin de patch-03-validation-fix.sql
-- ===========================================================================
