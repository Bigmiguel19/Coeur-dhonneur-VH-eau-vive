-- ===========================================================================
-- Cœur d'Honneur — patch-06-admin-record-payment.sql
-- ---------------------------------------------------------------------------
-- Permet à l'administrateur d'enregistrer manuellement un paiement pour n'importe
-- quel membre (rattrapage historique, versement espèces, etc.)
-- et de modifier un paiement.
-- ===========================================================================

-- 1. Fonction RPC sécurisée pour qu'un admin puisse insérer un paiement validé directement
create or replace function public.admin_record_payment(
  p_member_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_reference text default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid := auth.uid();
  v_payment_id uuid;
  v_member_ok boolean;
begin
  if not public.is_admin() then
    raise exception 'Seule l''administration peut enregistrer un versement directement'
      using errcode = '42501';
  end if;

  select is_active into v_member_ok
  from public.profiles
  where id = p_member_id and role = 'member';

  if v_member_ok is null then
    raise exception 'Membre introuvable' using errcode = 'P0002';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Le montant doit être supérieur à 0' using errcode = '22023';
  end if;

  insert into public.payments (
    member_id,
    amount,
    payment_date,
    transaction_reference,
    note,
    status,
    validated_at,
    validated_by,
    submitted_at
  ) values (
    p_member_id,
    p_amount,
    coalesce(p_payment_date, current_date),
    coalesce(nullif(btrim(p_reference), ''), 'SAISIE-ADMIN'),
    p_note,
    'confirmed',
    now(),
    v_admin_id,
    now()
  )
  returning id into v_payment_id;

  return v_payment_id;
end;
$$;

revoke all on function public.admin_record_payment(uuid, numeric, date, text, text) from public, anon;
grant execute on function public.admin_record_payment(uuid, numeric, date, text, text) to authenticated;

-- 2. Adapter payments_before_insert pour ne pas forcer 'pending' si admin_record_payment insère
create or replace function public.payments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid := auth.uid();
  v_min_amount   numeric;
  v_member_ok    boolean;
begin
  -- Session navigateur non-admin : un membre ne déclare que pour lui-même
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

  -- Si un administrateur insère directement un paiement confirmé (historique ou guichet)
  if public.is_admin() and new.status = 'confirmed' then
    new.validated_at := coalesce(new.validated_at, now());
    new.validated_by := coalesce(new.validated_by, v_uid);
  else
    -- Pour un membre normal, c'est toujours en attente
    new.status           := 'pending';
    new.validated_at     := null;
    new.validated_by     := null;
    new.rejection_reason := null;
  end if;

  new.submitted_at := coalesce(new.submitted_at, now());
  new.payment_date := coalesce(new.payment_date, current_date);
  new.created_at   := now();
  new.updated_at   := now();

  return new;
end;
$$;
