-- ===========================================================================
-- Cœur d'Honneur — schema.sql
-- Centre Eau Vive Williamsville, Vases d'Honneur
--
-- Structure complète de la base Supabase / PostgreSQL :
--   • types énumérés
--   • tables, contraintes et index
--   • fonctions métier (montant attendu, validation des paiements)
--   • vues calculées (statuts, retards, totaux) — aucune donnée dérivée stockée
--   • déclencheurs (profil automatique, audit, notifications)
--
-- À exécuter EN PREMIER dans l'éditeur SQL Supabase, avant policies.sql.
-- Le script est idempotent : il peut être relancé sans perdre de données.
--
-- Modèle financier retenu :
--   Les paiements forment un REGISTRE libre (tout montant >= minimum configuré,
--   à tout moment). Le système impute automatiquement les paiements validés sur
--   les périodes les plus anciennes non couvertes. Le reste à payer, les statuts
--   mensuels et les retards sont donc toujours CALCULÉS, jamais saisis.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 0. Extensions
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto; -- gen_random_uuid()
create extension if not exists pg_trgm;  -- recherche par nom / téléphone

-- ---------------------------------------------------------------------------
-- 1. Types énumérés
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type public.user_role as enum ('member', 'admin');
  end if;

  if not exists (select 1 from pg_type where typname = 'payment_status') then
    create type public.payment_status as enum ('pending', 'confirmed', 'rejected');
  end if;

  if not exists (select 1 from pg_type where typname = 'notification_type') then
    create type public.notification_type as enum (
      'payment_confirmed',
      'payment_rejected',
      'payment_pending',
      'arrears',
      'reminder',
      'system'
    );
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Fonction utilitaire : mise à jour de updated_at
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Table profiles — 1:1 avec auth.users
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null check (length(btrim(full_name)) between 2 and 120),
  email       text not null,
  phone       text,
  role        public.user_role not null default 'member',
  tier_id     uuid,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is
  'Profil applicatif de chaque utilisateur. Le rôle est la seule source de vérité des droits.';

create unique index if not exists profiles_email_key
  on public.profiles (lower(email));

create index if not exists profiles_role_active_idx
  on public.profiles (role, is_active);

create index if not exists profiles_full_name_trgm_idx
  on public.profiles using gin (full_name gin_trgm_ops);

create index if not exists profiles_phone_trgm_idx
  on public.profiles using gin (phone gin_trgm_ops);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. Table contribution_tiers — les 5 tranches mensuelles
-- ---------------------------------------------------------------------------
create table if not exists public.contribution_tiers (
  id             uuid primary key default gen_random_uuid(),
  label          text not null,
  monthly_amount numeric(12, 2) not null check (monthly_amount > 0),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create unique index if not exists contribution_tiers_label_key
  on public.contribution_tiers (lower(label));

create unique index if not exists contribution_tiers_amount_key
  on public.contribution_tiers (monthly_amount) where is_active;

alter table public.profiles
  drop constraint if exists profiles_tier_fk;
alter table public.profiles
  add constraint profiles_tier_fk
  foreign key (tier_id) references public.contribution_tiers (id) on delete restrict;

drop trigger if exists contribution_tiers_set_updated_at on public.contribution_tiers;
create trigger contribution_tiers_set_updated_at
  before update on public.contribution_tiers
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 5. Table contribution_periods — une ligne par mois
-- ---------------------------------------------------------------------------
create table if not exists public.contribution_periods (
  id              uuid primary key default gen_random_uuid(),
  label           text not null,
  year            smallint not null check (year between 2000 and 2100),
  month           smallint not null check (month between 1 and 12),
  due_date        date not null,
  expected_amount numeric(12, 2) not null default 0 check (expected_amount >= 0),
  is_open         boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint contribution_periods_unique_month unique (year, month)
);

create index if not exists contribution_periods_open_due_idx
  on public.contribution_periods (is_open, due_date);

drop trigger if exists contribution_periods_set_updated_at on public.contribution_periods;
create trigger contribution_periods_set_updated_at
  before update on public.contribution_periods
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 6. Table contribution_exceptions — dérogation individuelle du montant attendu
-- ---------------------------------------------------------------------------
create table if not exists public.contribution_exceptions (
  id              uuid primary key default gen_random_uuid(),
  member_id       uuid not null references public.profiles (id) on delete cascade,
  period_id       uuid not null references public.contribution_periods (id) on delete cascade,
  expected_amount numeric(12, 2) not null check (expected_amount >= 0),
  reason          text,
  created_by      uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint contribution_exceptions_unique unique (member_id, period_id)
);

create index if not exists contribution_exceptions_period_idx
  on public.contribution_exceptions (period_id);

drop trigger if exists contribution_exceptions_set_updated_at on public.contribution_exceptions;
create trigger contribution_exceptions_set_updated_at
  before update on public.contribution_exceptions
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 7. Table app_settings — ligne unique de configuration
-- ---------------------------------------------------------------------------
create table if not exists public.app_settings (
  id                     uuid primary key default gen_random_uuid(),
  church_name            text not null default 'Cœur d''Honneur',
  logo_url               text,
  wave_payment_url       text,
  wave_instructions      text,
  default_monthly_amount numeric(12, 2) not null default 2000 check (default_monthly_amount > 0),
  min_payment_amount     numeric(12, 2) not null default 500 check (min_payment_amount > 0),
  currency               char(3) not null default 'XOF',
  active_year            smallint not null default extract(year from now())::smallint,
  due_day                smallint not null default 10 check (due_day between 1 and 28),
  grace_days             smallint not null default 5 check (grace_days between 0 and 60),
  contact_information    jsonb not null default '{}'::jsonb,
  reminder_settings      jsonb not null default '{}'::jsonb,
  updated_at             timestamptz not null default now(),
  updated_by             uuid references public.profiles (id) on delete set null
);

-- Garantit l'unicité de la ligne de configuration
create unique index if not exists app_settings_singleton_idx
  on public.app_settings ((true));

drop trigger if exists app_settings_set_updated_at on public.app_settings;
create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 8. Table payments — le registre des versements
--    Aucune période n'est imposée : l'imputation est calculée.
-- ---------------------------------------------------------------------------
create table if not exists public.payments (
  id                    uuid primary key default gen_random_uuid(),
  member_id             uuid not null references public.profiles (id) on delete restrict,
  amount                numeric(12, 2) not null check (amount > 0),
  payment_date          date not null default current_date,
  transaction_reference text,
  note                  text,
  status                public.payment_status not null default 'pending',
  proof_path            text,
  submitted_at          timestamptz not null default now(),
  validated_at          timestamptz,
  validated_by          uuid references public.profiles (id) on delete set null,
  rejection_reason      text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  -- Un refus exige un motif
  constraint payments_rejected_requires_reason
    check (status <> 'rejected' or length(btrim(coalesce(rejection_reason, ''))) >= 5),

  -- Une validation exige son horodatage et son auteur
  constraint payments_confirmed_requires_validation
    check (status <> 'confirmed' or (validated_at is not null and validated_by is not null)),

  -- Une déclaration en attente ne peut pas déjà porter une décision
  constraint payments_pending_without_decision
    check (status <> 'pending' or (validated_at is null and validated_by is null))
);

comment on table public.payments is
  'Registre des versements déclarés par les membres. Imputation FIFO calculée sur les périodes.';

create index if not exists payments_member_idx
  on public.payments (member_id, payment_date desc);

create index if not exists payments_status_idx
  on public.payments (status, submitted_at desc);

create index if not exists payments_validated_by_idx
  on public.payments (validated_by);

-- Une seule déclaration en attente par membre : protège des doubles envois
create unique index if not exists payments_one_pending_per_member_idx
  on public.payments (member_id) where status = 'pending';

drop trigger if exists payments_set_updated_at on public.payments;
create trigger payments_set_updated_at
  before update on public.payments
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 9. Table notifications
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  member_id  uuid not null references public.profiles (id) on delete cascade,
  title      text not null,
  message    text not null,
  type       public.notification_type not null default 'system',
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_member_idx
  on public.notifications (member_id, is_read, created_at desc);

-- ---------------------------------------------------------------------------
-- 10. Table audit_logs — journal en ajout seul
-- ---------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references public.profiles (id) on delete set null,
  action      text not null,
  entity_type text not null,
  entity_id   uuid,
  metadata    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists audit_logs_created_idx
  on public.audit_logs (created_at desc);

create index if not exists audit_logs_entity_idx
  on public.audit_logs (entity_type, entity_id);

-- ---------------------------------------------------------------------------
-- 11. Table payment_reminders — rappels de retard envoyés
-- ---------------------------------------------------------------------------
create table if not exists public.payment_reminders (
  id         uuid primary key default gen_random_uuid(),
  member_id  uuid not null references public.profiles (id) on delete cascade,
  period_id  uuid references public.contribution_periods (id) on delete set null,
  channel    text not null default 'manual',
  sent_at    timestamptz not null default now(),
  sent_by    uuid references public.profiles (id) on delete set null
);

create index if not exists payment_reminders_member_idx
  on public.payment_reminders (member_id, sent_at desc);

-- ---------------------------------------------------------------------------
-- 12. Fonction is_admin() — vérification non récursive du rôle
--     SECURITY DEFINER : lit profiles sans déclencher les RLS, donc aucune
--     récursion de politique. Ne renvoie qu'un booléen, rien d'autre.
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
      and is_active
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- 13. Fonction expected_amount_for() — montant attendu d'un membre pour une
--     période, par ordre de priorité :
--       1. dérogation individuelle
--       2. tranche du membre
--       3. montant mensuel par défaut des paramètres
--       4. montant de la période elle-même
--     Une seule source de vérité, utilisée par les vues et les déclencheurs.
-- ---------------------------------------------------------------------------
create or replace function public.expected_amount_for(p_member_id uuid, p_period_id uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (
      select e.expected_amount
      from public.contribution_exceptions e
      where e.member_id = p_member_id
        and e.period_id = p_period_id
    ),
    (
      select t.monthly_amount
      from public.profiles p
      join public.contribution_tiers t on t.id = p.tier_id
      where p.id = p_member_id
        and t.is_active
    ),
    (select s.default_monthly_amount from public.app_settings s limit 1),
    (select p.expected_amount from public.contribution_periods p where p.id = p_period_id),
    0
  );
$$;

-- ---------------------------------------------------------------------------
-- 14. Vues calculées
-- ---------------------------------------------------------------------------

-- 14.a Statut de chaque couple membre × période, avec imputation FIFO
drop view if exists public.v_member_period_status;
create view public.v_member_period_status
with (security_invoker = true)
as
with settings as (
  select
    coalesce(grace_days, 0) as grace_days
  from public.app_settings
),
expected as (
  select
    pr.id  as member_id,
    p.id   as period_id,
    p.label,
    p.year,
    p.month,
    p.due_date,
    p.is_open,
    public.expected_amount_for(pr.id, p.id) as expected
  from public.profiles pr
  join public.contribution_periods p on true
  where pr.role = 'member'
),
cumulative as (
  select
    e.*,
    coalesce(sum(e.expected) over w_prev, 0)   as cum_before,
    coalesce(sum(e.expected) over w_through, 0) as cum_through
  from expected e
  window
    w_prev    as (partition by e.member_id order by e.year, e.month
                  rows between unbounded preceding and 1 preceding),
    w_through as (partition by e.member_id order by e.year, e.month
                  rows between unbounded preceding and current row)
),
funds as (
  select
    member_id,
    coalesce(sum(amount) filter (where status = 'confirmed'), 0) as confirmed_total,
    coalesce(sum(amount) filter (where status = 'pending'), 0)   as pending_total
  from public.payments
  group by member_id
),
calc as (
  select
    c.member_id,
    c.period_id,
    c.label,
    c.year,
    c.month,
    c.due_date,
    c.is_open,
    c.expected,
    coalesce(f.confirmed_total, 0) as confirmed_total,
    coalesce(f.pending_total, 0)   as pending_total,
    -- Imputation : ce qui reste du pot après avoir couvert les périodes précédentes
    greatest(
      least(coalesce(f.confirmed_total, 0) - c.cum_before, c.expected),
      0
    ) as paid_amount
  from cumulative c
  left join funds f on f.member_id = c.member_id
)
select
  c.member_id,
  c.period_id,
  c.label,
  c.year,
  c.month,
  c.due_date,
  c.is_open,
  round(c.expected, 2)                      as expected,
  round(c.paid_amount, 2)                   as paid_amount,
  round(greatest(c.expected - c.paid_amount, 0), 2) as remaining,
  round(c.confirmed_total, 2)               as confirmed_total,
  round(c.pending_total, 2)                 as pending_total,
  case
    when c.expected = 0 then 'paid'
    when c.paid_amount >= c.expected then 'paid'
    when c.paid_amount > 0 then 'partial'
    when c.pending_total > 0 then 'pending'
    else 'unpaid'
  end as payment_state,
  (
    current_date > (c.due_date + make_interval(days => coalesce(s.grace_days, 0)))
    and c.paid_amount < c.expected
  ) as is_overdue,
  case
    when current_date > (c.due_date + make_interval(days => coalesce(s.grace_days, 0)))
     and c.paid_amount < c.expected then 'late'
    when c.expected = 0 then 'paid'
    when c.paid_amount >= c.expected then 'paid'
    when c.paid_amount > 0 then 'partial'
    when c.pending_total > 0 then 'pending'
    else 'unpaid'
  end as display_status
from calc c
left join settings s on true;

comment on view public.v_member_period_status is
  'Statut calculé par membre et par période. is_overdue ignore volontairement les paiements en attente.';

-- 14.b Synthèse par membre
drop view if exists public.v_member_summary;
create view public.v_member_summary
with (security_invoker = true)
as
select
  s.member_id,
  round(sum(s.expected), 2)                                        as expected_total,
  round(sum(s.paid_amount), 2)                                     as paid_total,
  round(sum(s.remaining), 2)                                       as remaining_total,
  count(*) filter (where s.display_status = 'paid')                as months_paid,
  count(*) filter (where s.is_overdue)                             as months_late,
  count(*) filter (where s.payment_state = 'pending')              as months_pending,
  count(*)                                                         as months_total,
  case
    when sum(s.expected) > 0
      then round(sum(s.paid_amount) / sum(s.expected) * 100, 1)
    else 0
  end                                                              as progress_percent,
  (min((s.year::int * 100 + s.month)) filter (where s.payment_state <> 'paid' and s.is_open)) / 100
                                                                   as next_period_year,
  (min((s.year::int * 100 + s.month)) filter (where s.payment_state <> 'paid' and s.is_open)) % 100
                                                                   as next_period_month
from public.v_member_period_status s
group by s.member_id;

-- 14.c Totaux par période (graphique du tableau de bord admin)
drop view if exists public.v_period_totals;
create view public.v_period_totals
with (security_invoker = true)
as
select
  s.period_id,
  s.label,
  s.year,
  s.month,
  s.due_date,
  count(*) filter (where s.expected > 0)      as members_concerned,
  round(sum(s.expected), 2)                   as expected_total,
  round(sum(s.paid_amount), 2)                as confirmed_total,
  round(sum(s.remaining), 2)                  as remaining_total
from public.v_member_period_status s
group by s.period_id, s.label, s.year, s.month, s.due_date;

-- 14.d Retards par membre
drop view if exists public.v_member_arrears;
create view public.v_member_arrears
with (security_invoker = true)
as
select
  s.member_id,
  p.full_name,
  p.email,
  p.phone,
  p.is_active,
  count(*)                                    as months_late,
  round(sum(s.remaining), 2)                  as amount_due,
  min(s.year::int * 100 + s.month)            as first_late_key,
  min(s.due_date)                             as first_due_date
from public.v_member_period_status s
join public.profiles p on p.id = s.member_id
where s.is_overdue
group by s.member_id, p.full_name, p.email, p.phone, p.is_active;

-- 14.e File d'attente administrative des paiements
drop view if exists public.v_payments_queue;
create view public.v_payments_queue
with (security_invoker = true)
as
select
  pay.id,
  pay.member_id,
  pr.full_name,
  pr.email,
  pr.phone,
  pay.amount,
  pay.payment_date,
  pay.transaction_reference,
  pay.note,
  pay.status,
  pay.proof_path,
  pay.submitted_at,
  pay.validated_at,
  pay.validated_by,
  v.full_name as validated_by_name,
  pay.rejection_reason
from public.payments pay
join public.profiles pr on pr.id = pay.member_id
left join public.profiles v on v.id = pay.validated_by;

-- ---------------------------------------------------------------------------
-- 15. Statistiques du tableau de bord administrateur (un seul aller-retour)
--     SECURITY DEFINER + contrôle de rôle interne : impossible à appeler
--     en tant que membre.
-- ---------------------------------------------------------------------------
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_active_members  integer;
  v_expected        numeric;
  v_confirmed       numeric;
  v_pending_count   integer;
  v_pending_amount  numeric;
  v_arrears_members integer;
begin
  if not public.is_admin() then
    raise exception 'Accès réservé à l''administration'
      using errcode = '42501';
  end if;

  select count(*) into v_active_members
  from public.profiles
  where role = 'member' and is_active;

  select coalesce(sum(expected), 0), coalesce(sum(paid_amount), 0)
    into v_expected, v_confirmed
  from public.v_member_period_status;

  select count(*), coalesce(sum(amount), 0)
    into v_pending_count, v_pending_amount
  from public.payments
  where status = 'pending';

  select count(distinct member_id) into v_arrears_members
  from public.v_member_period_status
  where is_overdue;

  return jsonb_build_object(
    'active_members',   v_active_members,
    'expected_total',   round(v_expected, 2),
    'confirmed_total',  round(v_confirmed, 2),
    'remaining_total',  round(greatest(v_expected - v_confirmed, 0), 2),
    'pending_count',    v_pending_count,
    'pending_amount',   round(v_pending_amount, 2),
    'arrears_members',  v_arrears_members,
    'collection_rate',  case
                          when v_expected > 0
                            then round(v_confirmed / v_expected * 100, 1)
                          else 0
                        end
  );
end;
$$;

revoke all on function public.admin_dashboard_stats() from public;
grant execute on function public.admin_dashboard_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- 16. Déclencheur : création automatique du profil après inscription
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, phone)
  values (
    new.id,
    coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      split_part(coalesce(new.email, 'membre'), '@', 1)
    ),
    coalesce(new.email, ''),
    nullif(btrim(new.raw_user_meta_data ->> 'phone'), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 17. Déclencheurs de contrôle sur les paiements
-- ---------------------------------------------------------------------------

-- 17.a Avant insertion : le client ne décide ni du statut ni de la décision
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

drop trigger if exists payments_guard_insert on public.payments;
create trigger payments_guard_insert
  before insert on public.payments
  for each row execute function public.payments_before_insert();

-- 17.b Avant mise à jour : machine à états et horodatage serveur
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
  -- auth.uid() est NULL hors session navigateur (éditeur SQL, éditeur de
  -- table, migration, service_role) : on ne peut pas exiger d'administrateur,
  -- et les GRANT/RLS barrent déjà anon et authenticated.
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
  new.member_id        := old.member_id;
  new.amount           := old.amount;
  new.payment_date     := old.payment_date;
  new.proof_path       := old.proof_path;
  new.submitted_at     := old.submitted_at;
  new.created_at       := old.created_at;

  -- Décision attribuée côté serveur : la session impose l'auteur ; sans
  -- session, l'auteur fourni est conservé, à défaut l'administrateur actif
  -- enregistré (sinon la contrainte de validation resterait insatisfaite).
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

  new.validated_at     := now();
  new.updated_at       := now();

  if new.status = 'confirmed' then
    new.rejection_reason := null;
  end if;

  return new;
end;
$$;

drop trigger if exists payments_guard_update on public.payments;
create trigger payments_guard_update
  before update on public.payments
  for each row execute function public.payments_before_update();

-- 17.c Après décision : notification du membre
create or replace function public.payments_notify_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount text;
begin
  if new.status = old.status then
    return new;
  end if;

  v_amount := to_char(new.amount, 'FM999G999G999D00');

  if new.status = 'confirmed' then
    insert into public.notifications (member_id, title, message, type)
    values (
      new.member_id,
      'Paiement validé',
      'Votre paiement de ' || v_amount || ' FCFA du '
        || to_char(new.payment_date, 'DD/MM/YYYY')
        || ' a été vérifié et enregistré.',
      'payment_confirmed'
    );
  elsif new.status = 'rejected' then
    insert into public.notifications (member_id, title, message, type)
    values (
      new.member_id,
      'Paiement non validé',
      'Votre déclaration de ' || v_amount || ' FCFA n''a pas pu être validée. Motif : '
        || coalesce(new.rejection_reason, 'non précisé'),
      'payment_rejected'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists payments_notify on public.payments;
create trigger payments_notify
  after update on public.payments
  for each row execute function public.payments_notify_member();

-- ---------------------------------------------------------------------------
-- 18. Déclencheur générique d'audit
-- ---------------------------------------------------------------------------
create or replace function public.audit_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action    text;
  v_entity_id uuid;
  v_metadata  jsonb;
begin
  v_action := lower(tg_op) || '_' || tg_table_name;

  if tg_op = 'DELETE' then
    v_entity_id := (to_jsonb(old) ->> 'id')::uuid;
    v_metadata  := jsonb_build_object('old', to_jsonb(old));
  elsif tg_op = 'UPDATE' then
    v_entity_id := (to_jsonb(new) ->> 'id')::uuid;
    v_metadata  := jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new));
  else
    v_entity_id := (to_jsonb(new) ->> 'id')::uuid;
    v_metadata  := jsonb_build_object('new', to_jsonb(new));
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), v_action, tg_table_name, v_entity_id, v_metadata);

  return null;
end;
$$;

drop trigger if exists audit_payments_insert on public.payments;
create trigger audit_payments_insert
  after insert on public.payments
  for each row execute function public.audit_row();

drop trigger if exists audit_payments_update on public.payments;
create trigger audit_payments_update
  after update on public.payments
  for each row execute function public.audit_row();

drop trigger if exists audit_profiles on public.profiles;
create trigger audit_profiles
  after update on public.profiles
  for each row execute function public.audit_row();

drop trigger if exists audit_app_settings on public.app_settings;
create trigger audit_app_settings
  after update on public.app_settings
  for each row execute function public.audit_row();

drop trigger if exists audit_periods on public.contribution_periods;
create trigger audit_periods
  after insert or update or delete on public.contribution_periods
  for each row execute function public.audit_row();

drop trigger if exists audit_exceptions on public.contribution_exceptions;
create trigger audit_exceptions
  after insert or update or delete on public.contribution_exceptions
  for each row execute function public.audit_row();

-- ---------------------------------------------------------------------------
-- 19. Garde-fou sur profiles : rôle, statut et e-mail non modifiables par
--     un membre (défense en profondeur, en plus des GRANT et des RLS).
-- ---------------------------------------------------------------------------
create or replace function public.profiles_guard_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- auth.uid() est NULL hors session navigateur : éditeur SQL, éditeur de
  -- table, migration, backend service_role. Dans ce cas la requête ne vient
  -- pas d'un membre et n'est pas soumise à cette garde (les GRANT et les RLS
  -- restent la barrière d'anon et d'authenticated).
  v_uid uuid := auth.uid();
begin
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

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.profiles_guard_update();

-- ---------------------------------------------------------------------------
-- 20. Génération des périodes d'une année (utilisée par l'espace admin)
--     Crée uniquement les mois manquants, avec la date d'échéance et le
--     montant par défaut des paramètres. Ne touche jamais aux mois existants.
-- ---------------------------------------------------------------------------
create or replace function public.admin_generate_periods(p_year smallint)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_due_day  smallint;
  v_amount   numeric;
  v_month    smallint;
  v_label    text;
  v_created  integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Accès réservé à l''administration'
      using errcode = '42501';
  end if;

  if p_year is null or p_year < 2000 or p_year > 2100 then
    raise exception 'Année invalide' using errcode = '22023';
  end if;

  select coalesce(due_day, 10), coalesce(default_monthly_amount, 0)
    into v_due_day, v_amount
  from public.app_settings
  limit 1;

  v_due_day := coalesce(v_due_day, 10);
  v_amount  := coalesce(v_amount, 0);

  for v_month in 1..12 loop
    v_label := initcap(
      (array['janvier','février','mars','avril','mai','juin','juillet',
             'août','septembre','octobre','novembre','décembre'])[v_month]
    ) || ' ' || p_year::text;

    insert into public.contribution_periods (label, year, month, due_date, expected_amount, is_open)
    values (
      v_label,
      p_year,
      v_month,
      make_date(p_year, v_month, v_due_day),
      v_amount,
      true
    )
    on conflict (year, month) do nothing;

    if found then
      v_created := v_created + 1;
    end if;
  end loop;

  return v_created;
end;
$$;

revoke all on function public.admin_generate_periods(smallint) from public;
grant execute on function public.admin_generate_periods(smallint) to authenticated;

-- ===========================================================================
-- Fin de schema.sql — exécuter ensuite policies.sql
-- ===========================================================================
