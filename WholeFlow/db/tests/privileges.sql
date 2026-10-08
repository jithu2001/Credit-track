-- Catalog checks for migration 0009 (who may do what), as `postgres`.
-- Reads the catalog only; safe on a real business database.
-- A failed check aborts with "assertion failed: <label>".
--
-- When a migration adds a table, give it RLS and grant SELECT to
-- authenticated explicitly; when it adds a write the app API makes as a
-- signed-in person, add it to `expected_writes` below.

begin;

create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'assertion failed: %', label; end if;
end $$;

-- table, privilege, columns (null = table-level) that authenticated may use for writes.
create temp table expected_writes (tbl text, priv text, cols text[]);
insert into expected_writes values
  ('sites',       'INSERT', array['id', 'business_id', 'company_id', 'name']),
  ('sites',       'UPDATE', array['name']),
  ('sites',       'DELETE', null),
  ('visit_plans', 'INSERT', array['id', 'business_id', 'site_id', 'staff_id', 'plan_date', 'weekday', 'starts_on', 'ends_on']),
  ('visit_plans', 'UPDATE', array['active']),
  ('visit_plans', 'DELETE', null),
  ('users',       'UPDATE', array['name', 'is_active', 'requires_check_in']);

-- Tables only postgres uses.
create temp table internal_tables (tbl text);
insert into internal_tables values ('schema_migrations'), ('revoked_devices');

do $$
declare
  t record;
  p text;
  col record;
  want boolean;
begin
  for t in
    select c.oid, c.relname, c.relkind, c.relrowsecurity
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm')
  loop
    if t.relkind in ('r', 'p') then
      perform pg_temp.check(t.relrowsecurity, format('%s has row level security', t.relname));
    end if;

    -- anon: nothing at all.
    foreach p in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      perform pg_temp.check(not has_table_privilege('anon', t.oid, p), format('anon has no %s on %s', p, t.relname));
    end loop;
    perform pg_temp.check(not has_any_column_privilege('anon', t.oid, 'SELECT, INSERT, UPDATE, REFERENCES'),
                          format('anon has no column rights on %s', t.relname));

    -- Nobody but postgres may truncate, add triggers or reference.
    foreach p in array array['TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      perform pg_temp.check(not has_table_privilege('authenticated', t.oid, p), format('authenticated has no %s on %s', p, t.relname));
      perform pg_temp.check(not has_table_privilege('service_role', t.oid, p), format('service_role has no %s on %s', p, t.relname));
    end loop;

    -- authenticated: SELECT on everything clients read (RLS picks the rows).
    perform pg_temp.check(has_table_privilege('authenticated', t.oid, 'SELECT')
                            = not exists (select 1 from internal_tables i where i.tbl = t.relname),
                          format('authenticated SELECT on %s as expected', t.relname));

    -- authenticated: only the expected writes.
    foreach p in array array['INSERT', 'UPDATE', 'DELETE'] loop
      want := exists (select 1 from expected_writes e where e.tbl = t.relname and e.priv = p and e.cols is null);
      perform pg_temp.check(has_table_privilege('authenticated', t.oid, p) = want,
                            format('authenticated table-level %s on %s is %s', p, t.relname, want));
    end loop;
    foreach p in array array['INSERT', 'UPDATE'] loop
      for col in
        select a.attname from pg_attribute a where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
      loop
        want := exists (select 1 from expected_writes e
                        where e.tbl = t.relname and e.priv = p and (e.cols is null or col.attname = any (e.cols)));
        perform pg_temp.check(has_column_privilege('authenticated', t.oid, col.attname, p) = want,
                              format('authenticated %s on %s.%s is %s', p, t.relname, col.attname, want));
      end loop;
    end loop;
  end loop;
end $$;

-- No temporary tables and no direct connections for the API roles.
select pg_temp.check(not has_database_privilege('authenticated', current_database(), 'TEMPORARY'), 'authenticated: no TEMP');
select pg_temp.check(not has_database_privilege('anon', current_database(), 'TEMPORARY'), 'anon: no TEMP');
select pg_temp.check(not has_database_privilege('anon', current_database(), 'CONNECT'), 'PUBLIC/anon: no CONNECT');

-- Functions: WholeFlow's own are never callable by anon (or PUBLIC);
-- SECURITY DEFINER ones pin search_path to public, pg_temp.
select pg_temp.check(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind in ('f', 'p')
    and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
    and has_function_privilege('anon', p.oid, 'EXECUTE')), 'anon cannot execute any WholeFlow function');
select pg_temp.check(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef
    and not coalesce('search_path=public, pg_temp' = any (p.proconfig), false)), 'every SECURITY DEFINER function: search_path = public, pg_temp');
select pg_temp.check(not has_function_privilege('authenticated', 'public.purge_old_data()', 'EXECUTE'), 'purge_old_data: not for clients');
select pg_temp.check(has_function_privilege('service_role', 'public.purge_old_data()', 'EXECUTE'), 'purge_old_data: service_role may run it');
select pg_temp.check(not has_function_privilege('authenticated', 'public.admin_insert_staff(uuid, uuid, text, text, uuid, jsonb)', 'EXECUTE'),
                     'admin_insert_staff: service_role only');
select pg_temp.check(has_function_privilege('authenticated', 'public.check_in(uuid, double precision, double precision, double precision, boolean, boolean, text)', 'EXECUTE'),
                     'check_in: still callable when signed in');
select pg_temp.check(has_function_privilege('authenticated', 'public.check_request()', 'EXECUTE')
                     and has_function_privilege('service_role', 'public.check_request()', 'EXECUTE'), 'check_request: app and PC');

-- RLS policies call the no-argument helpers once per query.
select pg_temp.check(not exists (
  select 1 from pg_policies
  where schemaname = 'public'
    and (coalesce(qual, '') || ' ' || coalesce(with_check, ''))
        ~ '(?<!SELECT )(?<!SELECT public\.)(public\.)?(current_business_id|is_owner|auth\.uid)\(\)'),
  'policies wrap current_business_id(), is_owner() and auth.uid() in (select …)');

-- The login tables (auth.*, password hashes) are for the login role only.
select pg_temp.check(not exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'auth' and c.relkind in ('r', 'p', 'v', 'm')
    and (has_any_column_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
         or has_any_column_privilege('authenticated', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
         or has_any_column_privilege('service_role', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
         or has_table_privilege('authenticated', c.oid, 'DELETE, TRUNCATE')
         or has_table_privilege('service_role', c.oid, 'DELETE, TRUNCATE'))),
  'API roles have no rights on auth tables');
select pg_temp.check(not exists (select 1 from pg_namespace where nspname = 'auth')
                     or not has_schema_privilege('anon', 'auth', 'USAGE'), 'anon cannot use schema auth');

select 'privileges: all checks passed' as result;

rollback;
