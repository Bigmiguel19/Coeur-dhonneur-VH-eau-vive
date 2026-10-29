-- ===========================================================================
-- Cœur d'Honneur — policies.sql
-- Sécurité : privilèges, Row Level Security et politiques de stockage.
--
-- À exécuter APRÈS schema.sql, dans l'éditeur SQL Supabase.
-- Script idempotent (drop policy if exists avant chaque création).
--
-- Principes :
--   1. Un membre ne lit que ses propres données ; jamais celles d'un autre.
--   2. Un membre ne peut ni changer son rôle, ni changer son statut de compte,
--      ni confirmer son propre paiement.
--   3. Les écritures sensibles (rôle, statut, tranche, création de compte)
--      passent par les fonctions serveur /api (service_role), jamais par le
--      navigateur.
--   4. Aucune politique n'interroge directement public.profiles pour éviter
--      la récursion : on utilise public.is_admin() (SECURITY DEFINER).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 0. Privilèges de base
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke all on all tables in schema public from authenticated;

grant usage on schema public to authenticated;

-- ---------------------------------------------------------------------------
-- 1. profiles
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

-- Lecture : sa propre ligne, ou tout pour un administrateur
drop policy if exists profiles_select on public.profiles;
create policy profiles_select
  on public.profiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or public.is_admin()
  );

-- Mise à jour : uniquement sa propre ligne (les colonnes autorisées sont
-- limitées par les GRANT ci-dessous, et le trigger profiles_guard fait le reste)
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
  on public.profiles
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

grant select on public.profiles to authenticated;

-- Seules ces deux colonnes sont modifiables par le membre.
-- role, is_active, tier_id et email sont réservés au serveur (service_role).
grant update (full_name, phone) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. contribution_tiers
-- ---------------------------------------------------------------------------
alter table public.contribution_tiers enable row level security;

drop policy if exists tiers_select on public.contribution_tiers;
create policy tiers_select
  on public.contribution_tiers
  for select
  to authenticated
  using (true);

drop policy if exists tiers_write_admin on public.contribution_tiers;
create policy tiers_write_admin
  on public.contribution_tiers
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select, insert, update, delete on public.contribution_tiers to authenticated;

-- ---------------------------------------------------------------------------
-- 3. contribution_periods
-- ---------------------------------------------------------------------------
alter table public.contribution_periods enable row level security;

drop policy if exists periods_select on public.contribution_periods;
create policy periods_select
  on public.contribution_periods
  for select
  to authenticated
  using (true);

drop policy if exists periods_write_admin on public.contribution_periods;
create policy periods_write_admin
  on public.contribution_periods
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select, insert, update, delete on public.contribution_periods to authenticated;

-- ---------------------------------------------------------------------------
-- 4. contribution_exceptions
-- ---------------------------------------------------------------------------
alter table public.contribution_exceptions enable row level security;

drop policy if exists exceptions_select on public.contribution_exceptions;
create policy exceptions_select
  on public.contribution_exceptions
  for select
  to authenticated
  using (
    member_id = (select auth.uid())
    or public.is_admin()
  );

drop policy if exists exceptions_write_admin on public.contribution_exceptions;
create policy exceptions_write_admin
  on public.contribution_exceptions
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select, insert, update, delete on public.contribution_exceptions to authenticated;

-- ---------------------------------------------------------------------------
-- 5. payments — le cœur du dispositif
-- ---------------------------------------------------------------------------
alter table public.payments enable row level security;

-- Lecture : ses propres paiements, ou tout pour un administrateur
drop policy if exists payments_select on public.payments;
create policy payments_select
  on public.payments
  for select
  to authenticated
  using (
    member_id = (select auth.uid())
    or public.is_admin()
  );

-- Déclaration : le membre ne peut créer que pour lui-même.
-- Le trigger payments_before_insert force le statut 'pending' et efface
-- toute décision, même si le client tente de la renseigner.
drop policy if exists payments_insert_self on public.payments;
create policy payments_insert_self
  on public.payments
  for insert
  to authenticated
  with check (
    member_id = (select auth.uid())
    and status = 'pending'
    and validated_at is null
    and validated_by is null
  );

-- Décision : réservée aux administrateurs. Un membre ne peut donc jamais
-- passer un paiement à 'confirmed', même par requête directe.
drop policy if exists payments_update_admin on public.payments;
create policy payments_update_admin
  on public.payments
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Aucune suppression : la trace financière est conservée.

grant select on public.payments to authenticated;

-- Colonnes inscriptibles par un membre. Ni status, ni validated_* :
-- ces valeurs sont posées côté serveur.
grant insert (member_id, amount, payment_date, transaction_reference, note, proof_path)
  on public.payments to authenticated;

-- Colonnes modifiables par un administrateur (la politique ci-dessus limite
-- les lignes aux administrateurs).
grant update (status, rejection_reason)
  on public.payments to authenticated;

-- ---------------------------------------------------------------------------
-- 6. notifications
-- ---------------------------------------------------------------------------
alter table public.notifications enable row level security;

drop policy if exists notifications_select on public.notifications;
create policy notifications_select
  on public.notifications
  for select
  to authenticated
  using (
    member_id = (select auth.uid())
    or public.is_admin()
  );

-- Le membre ne peut modifier que le statut de lecture
drop policy if exists notifications_update_self on public.notifications;
create policy notifications_update_self
  on public.notifications
  for update
  to authenticated
  using (member_id = (select auth.uid()))
  with check (member_id = (select auth.uid()));

-- Un administrateur peut créer une notification (rappel manuel)
drop policy if exists notifications_insert_admin on public.notifications;
create policy notifications_insert_admin
  on public.notifications
  for insert
  to authenticated
  with check (public.is_admin());

grant select on public.notifications to authenticated;
grant update (is_read) on public.notifications to authenticated;
grant insert on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- 7. app_settings
-- ---------------------------------------------------------------------------
alter table public.app_settings enable row level security;

drop policy if exists settings_select on public.app_settings;
create policy settings_select
  on public.app_settings
  for select
  to authenticated
  using (true);

drop policy if exists settings_update_admin on public.app_settings;
create policy settings_update_admin
  on public.app_settings
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists settings_insert_admin on public.app_settings;
create policy settings_insert_admin
  on public.app_settings
  for insert
  to authenticated
  with check (public.is_admin());

grant select on public.app_settings to authenticated;
grant insert, update on public.app_settings to authenticated;

-- ---------------------------------------------------------------------------
-- 8. audit_logs — lecture administrateur, écriture serveur uniquement
-- ---------------------------------------------------------------------------
alter table public.audit_logs enable row level security;

drop policy if exists audit_select_admin on public.audit_logs;
create policy audit_select_admin
  on public.audit_logs
  for select
  to authenticated
  using (public.is_admin());

grant select on public.audit_logs to authenticated;

-- ---------------------------------------------------------------------------
-- 9. payment_reminders
-- ---------------------------------------------------------------------------
alter table public.payment_reminders enable row level security;

drop policy if exists reminders_select_admin on public.payment_reminders;
create policy reminders_select_admin
  on public.payment_reminders
  for select
  to authenticated
  using (public.is_admin());

drop policy if exists reminders_insert_admin on public.payment_reminders;
create policy reminders_insert_admin
  on public.payment_reminders
  for insert
  to authenticated
  with check (public.is_admin());

grant select, insert on public.payment_reminders to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Vues calculées
--     security_invoker = true : les RLS des tables sous-jacentes s'appliquent,
--     donc un membre ne voit que ses propres lignes à travers les vues.
-- ---------------------------------------------------------------------------
grant select on public.v_member_period_status to authenticated;
grant select on public.v_member_summary to authenticated;
grant select on public.v_period_totals to authenticated;
grant select on public.v_member_arrears to authenticated;
grant select on public.v_payments_queue to authenticated;

revoke all on public.v_member_period_status from anon;
revoke all on public.v_member_summary from anon;
revoke all on public.v_period_totals from anon;
revoke all on public.v_member_arrears from anon;
revoke all on public.v_payments_queue from anon;

-- ---------------------------------------------------------------------------
-- 11. Fonctions métier : exécution réservée aux utilisateurs connectés
-- ---------------------------------------------------------------------------
revoke all on function public.expected_amount_for(uuid, uuid) from public, anon;
grant execute on function public.expected_amount_for(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Stockage des preuves de paiement
--     Bucket privé : aucun accès public, uniquement des URL signées.
--     Convention de chemin : {member_id}/{payment_id}.{extension}
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'payment-proofs',
  'payment-proofs',
  false,
  5242880, -- 5 Mo
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update
  set public = false,
      file_size_limit = 5242880,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

drop policy if exists proofs_select on storage.objects;
create policy proofs_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'payment-proofs'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.is_admin()
    )
  );

drop policy if exists proofs_insert on storage.objects;
create policy proofs_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists proofs_delete_admin on storage.objects;
create policy proofs_delete_admin
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'payment-proofs'
    and public.is_admin()
  );

-- ===========================================================================
-- Fin de policies.sql
-- ===========================================================================
