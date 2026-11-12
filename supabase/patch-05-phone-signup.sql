-- Phone/password self-registration without SMS verification.
-- Apply in Supabase SQL Editor BEFORE enabling public signup and Phone Auth.
-- Existing email identities, profile IDs, roles, and financial records are preserved.
begin;

alter table public.profiles alter column email drop not null;
update public.profiles set email = null where btrim(email) = '';

-- The unique email index allows multiple NULL values, not duplicate real emails.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := nullif(btrim(new.phone), '');
  v_name text := nullif(btrim(new.raw_user_meta_data ->> 'full_name'), '');
begin
  if v_phone is not null then
    v_phone := '+' || ltrim(v_phone, '+');
  end if;
  if v_name is null or length(v_name) not between 2 and 120 then
    v_name := case when v_phone is not null then 'Membre ' || v_phone else 'Membre' end;
  end if;

  insert into public.profiles (id, full_name, email, phone, role, is_active, tier_id)
  values (
    new.id, v_name, nullif(btrim(new.email), ''),
    coalesce(v_phone, nullif(btrim(new.raw_user_meta_data ->> 'phone'), '')),
    'member', true, null
  );
  return new;
end;
$$;

-- Never allow even an administrator's profile-table write to desynchronize
-- a phone login. A legitimate Auth update is already visible to its AFTER trigger.
create or replace function public.profiles_guard_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_auth_phone text;
begin
  if new.phone is distinct from old.phone then
    select nullif(btrim(u.phone), '') into v_auth_phone
    from auth.users u where u.id = old.id;
    if v_auth_phone is not null
       and new.phone is distinct from ('+' || ltrim(v_auth_phone, '+')) then
      raise exception 'Le téléphone de connexion se modifie via l''authentification'
        using errcode = '42501';
    end if;
  end if;

  if v_uid is null or public.is_admin() then
    return new;
  end if;
  if new.role is distinct from old.role then
    raise exception 'Le rôle ne peut pas être modifié par le membre' using errcode = '42501';
  end if;
  if new.is_active is distinct from old.is_active then
    raise exception 'Le statut du compte ne peut pas être modifié par le membre' using errcode = '42501';
  end if;
  if new.email is distinct from old.email then
    raise exception 'L''adresse e-mail se modifie via le mécanisme d''authentification' using errcode = '42501';
  end if;
  if new.tier_id is distinct from old.tier_id then
    raise exception 'La tranche de cotisation est attribuée par l''administration' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.sync_auth_phone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set phone = case when nullif(btrim(new.phone), '') is null then null
                   else '+' || ltrim(btrim(new.phone), '+') end
  where id = new.id;
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.profiles_guard_update() from public, anon, authenticated;
revoke all on function public.sync_auth_phone() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.profiles_guard_update();

drop trigger if exists on_auth_phone_updated on auth.users;
create trigger on_auth_phone_updated
  after update of phone on auth.users
  for each row when (old.phone is distinct from new.phone)
  execute function public.sync_auth_phone();

-- Only existing Auth phone identities are synchronized; contact numbers are not linked.
update public.profiles p
set phone = '+' || ltrim(btrim(u.phone), '+')
from auth.users u
where u.id = p.id and nullif(btrim(u.phone), '') is not null
  and p.phone is distinct from ('+' || ltrim(btrim(u.phone), '+'));

commit;

-- Configure in Supabase Authentication after applying this migration:
-- Allow new users to sign up; enable Phone; disable Confirm phone.
-- Keep Email enabled for existing accounts. Set minimum password length to 8
-- and require letters and digits. Keep Auth rate limits enabled.
-- No SMS provider or service-role key is needed in the browser.
-- Recovery: a trusted operator must independently verify identity before using
-- Supabase Auth Admin tooling to set a temporary password; never log passwords.
-- Do not run old profile/guard patches after this migration.
