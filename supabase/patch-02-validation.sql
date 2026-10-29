-- ===========================================================================
-- Cœur d'Honneur — patch-02-validation.sql
-- ---------------------------------------------------------------------------
-- ⚠️  REMPLACÉ PAR patch-03-validation-fix.sql — ne pas exécuter ce fichier.
--     Il laissait passer la garde mais laissait validated_by à NULL, ce qui
--     déclenchait la contrainte payments_confirmed_requires_validation.
-- ---------------------------------------------------------------------------
-- À exécuter dans le SQL Editor de Supabase.
--
-- Objet : la fonction de garde des paiements appliquait la même règle que
-- celle des profils — elle exigeait un administrateur via auth.uid(). Depuis
-- la console SQL, il n'y a pas de jeton : toute validation ou tout refus
-- échouait avec « 42501: Seule l'administration peut modifier un paiement ».
--
-- Après ce patch :
--   — un appel venant du navigateur doit toujours venir d'un administrateur ;
--   — la console SQL et le backend de confiance (service_role) peuvent agir ;
--   — l'auteur de la décision (validated_by) est imposé par le serveur quand
--     une session existe, et conservé sinon.
--
-- Le fichier est idempotent.
-- ===========================================================================

create or replace function public.payments_before_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_api_role text := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
begin
  if v_api_role is not null and v_api_role <> 'service_role' then
    if not public.is_admin() then
      raise exception 'Seule l''administration peut modifier un paiement'
        using errcode = '42501';
    end if;
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
  new.member_id        := old.member_id;
  new.amount           := old.amount;
  new.payment_date     := old.payment_date;
  new.proof_path       := old.proof_path;
  new.submitted_at     := old.submitted_at;
  new.created_at       := old.created_at;

  new.validated_at     := now();
  new.validated_by     := coalesce(auth.uid(), new.validated_by, old.validated_by);
  new.updated_at       := now();

  if new.status = 'confirmed' then
    new.rejection_reason := null;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- OUTILS DE TEST (à décommenter au besoin)
-- L'espace d'administration qui valide en un clic arrive à la phase 6.
-- En attendant, on peut simuler la décision ici.
-- ---------------------------------------------------------------------------

-- 1. Voir la file d'attente
-- select id, member_id, amount, payment_date, transaction_reference, status
-- from public.payments
-- where status = 'pending'
-- order by submitted_at;

-- 2. Valider une déclaration précise
-- update public.payments
-- set status = 'confirmed',
--     validated_by = (
--       select id from public.profiles where role = 'admin' order by created_at limit 1
--     )
-- where id = 'COLLER-L-IDENTIFIANT-ICI';

-- 3. Refuser une déclaration (motif obligatoire, 5 caractères minimum)
-- update public.payments
-- set status = 'rejected',
--     rejection_reason = 'Référence introuvable chez Wave',
--     validated_by = (
--       select id from public.profiles where role = 'admin' order by created_at limit 1
--     )
-- where id = 'COLLER-L-IDENTIFIANT-ICI';
