-- Takes CONNECT and TEMPORARY away from PUBLIC on every WholeFlow database,
-- so a login role can only reach the databases granted to it by name
-- (business roles: their own biz_<slug>; wholeflow_api_ro: control_db).
-- Idempotent. Run as postgres on an existing server, and again after
-- creating control_db:
--   docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1 < db/lock-databases.sql
-- Before running it, make sure every role that connects to control_db
-- directly is either postgres or has its own `grant connect` (see api_ro_role.sql).
select format('revoke connect, temporary on database %I from public', datname)
from pg_database
where datname in ('postgres', 'template1', 'control_db') or datname like 'biz\_%'
\gexec

-- Business login roles keep their own database (new-business.sh grants these;
-- repeated here for businesses made before it did).
select format('grant connect on database %I to %I', d.datname, r.rolname)
from pg_database d
join pg_roles r on r.rolname in (substr(d.datname, 5) || '_api', substr(d.datname, 5) || '_auth')
where d.datname like 'biz\_%'
\gexec
