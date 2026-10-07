-- Roles every business database uses (PostgreSQL roles are server-wide).
-- They cannot log in: each business has its own login roles, made by
-- scripts/new-business.sh, that switch into these per request.
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

-- New databases are private by default.
revoke connect on database template1 from public;
