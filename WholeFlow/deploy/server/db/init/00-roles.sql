-- Roles every business database uses (PostgreSQL roles are server-wide).
-- They cannot log in: each business has its own login roles, made by
-- scripts/new-business.sh, that switch into these per request.
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

-- PostgreSQL lets every role (PUBLIC) connect to a new database unless told
-- otherwise. Nothing but postgres needs these; new-business.sh revokes PUBLIC
-- on each business database itself. control_db does not exist yet when this
-- runs: after creating it, run db/lock-databases.sql (also for servers set up
-- before this line existed).
revoke connect on database template1 from public;
revoke connect, temporary on database postgres from public;
