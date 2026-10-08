-- A read-only login for the WholeFlow app API on control_db: it only looks
-- businesses up (internal/appapi fromControl) and may read settings. Use it in
-- api.env as CONTROL_DB_URL instead of postgres.
-- Idempotent: creates the role or resets its password, then (re)grants.
-- The password comes from a psql variable, never from this file:
--
--   PW=$(openssl rand -hex 24)
--   docker compose exec -T db psql -U postgres -d control_db -v ON_ERROR_STOP=1 \
--     -v pw="$PW" < db/api_ro_role.sql
--   # CONTROL_DB_URL=postgres://wholeflow_api_ro:$PW@127.0.0.1:5432/control_db
--
-- Must run in control_db (the grants below are on its tables).

select current_database() = 'control_db' as in_control_db \gset
\if :in_control_db
\else
  do $$ begin raise exception 'api_ro_role.sql: run it with -d control_db'; end $$;
\endif

select format('create role wholeflow_api_ro login noinherit password %L', :'pw')
where not exists (select 1 from pg_roles where rolname = 'wholeflow_api_ro')
\gexec
select format('alter role wholeflow_api_ro password %L', :'pw')
\gexec
alter role wholeflow_api_ro set default_transaction_read_only = on;
alter role wholeflow_api_ro connection limit 20;

grant connect on database control_db to wholeflow_api_ro;
grant usage on schema public to wholeflow_api_ro;
revoke all on all tables in schema public from wholeflow_api_ro;
grant select on public.businesses, public.settings to wholeflow_api_ro;
