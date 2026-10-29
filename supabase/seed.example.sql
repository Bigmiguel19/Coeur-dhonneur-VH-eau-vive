-- ===========================================================================
-- Cœur d'Honneur — seed.example.sql
-- Données de départ INDISPENSABLES au fonctionnement de l'application.
--
-- À exécuter APRÈS schema.sql et policies.sql.
-- Ce fichier contient des valeurs d'exemple : adaptez-les à la communauté
-- avant de l'exécuter en production (montant par défaut, lien Wave, contacts).
--
-- Aucun compte utilisateur n'est créé ici : les membres et le premier
-- administrateur se créent via le tableau de bord Supabase
-- (voir bootstrap-admin.sql).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Paramètres généraux (ligne unique)
-- ---------------------------------------------------------------------------
insert into public.app_settings (
  church_name,
  wave_payment_url,
  wave_instructions,
  default_monthly_amount,
  min_payment_amount,
  currency,
  active_year,
  due_day,
  grace_days,
  contact_information,
  reminder_settings
)
select
  'Cœur d''Honneur — Centre Eau Vive Williamsville, Vases d''Honneur',
  'https://pay.wave.com/m/REMPLACER-PAR-VOTRE-LIEN/m/ci/',
  'Ouvrez le lien Wave, indiquez le montant, puis écrivez dans le libellé : '
    || 'COTISATION — votre nom — le mois concerné. Revenez ensuite sur la '
    || 'plateforme pour déclarer votre paiement avec la référence de transaction.',
  2000,   -- montant mensuel par défaut (FCFA)
  500,    -- montant minimum accepté pour un versement
  'XOF',
  extract(year from now())::smallint,
  10,     -- jour d'échéance du mois
  5,      -- jours de grâce avant de considérer un retard
  jsonb_build_object(
    'phone', '+225 00 00 00 00 00',
    'email', 'secretariat@exemple.ci',
    'address', 'Williamsville, Abidjan'
  ),
  jsonb_build_object(
    'enabled', true,
    'day_of_month', 5,
    'channel', 'manual'
  )
where not exists (select 1 from public.app_settings);

-- ---------------------------------------------------------------------------
-- 2. Les cinq tranches de cotisation
-- ---------------------------------------------------------------------------
insert into public.contribution_tiers (label, monthly_amount, is_active)
values
  ('Tranche 1', 500,  true),
  ('Tranche 2', 1000, true),
  ('Tranche 3', 2000, true),
  ('Tranche 4', 3000, true),
  ('Tranche 5', 5000, true)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. Périodes de l'année de cotisation active (12 mois)
--    Juillet à décembre sont créés « fermés » si vous préférez n'ouvrir que
--    les mois à venir. Par défaut tout est ouvert : un membre peut payer
--    d'avance.
-- ---------------------------------------------------------------------------
do $$
declare
  v_year smallint;
begin
  select active_year into v_year from public.app_settings limit 1;

  if v_year is null then
    v_year := extract(year from now())::smallint;
  end if;

  insert into public.contribution_periods (label, year, month, due_date, expected_amount, is_open)
  select
    initcap(
      (array['janvier','février','mars','avril','mai','juin','juillet',
             'août','septembre','octobre','novembre','décembre'])[m]
    ) || ' ' || v_year::text,
    v_year,
    m,
    make_date(v_year, m, (select due_day from public.app_settings limit 1)),
    (select default_monthly_amount from public.app_settings limit 1),
    true
  from generate_series(1, 12) as m
  on conflict (year, month) do nothing;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Vérification rapide
-- ---------------------------------------------------------------------------
select 'paramètres'   as objet, count(*)::text as valeur from public.app_settings
union all
select 'tranches',    count(*)::text from public.contribution_tiers
union all
select 'périodes',    count(*)::text from public.contribution_periods
union all
select 'membres',     count(*)::text from public.profiles;
