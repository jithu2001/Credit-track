-- Checks for migration 0007 (subscription status and per-PC keys).
-- Runs in one transaction that is ROLLED BACK. Run as `postgres` after 0007.
-- A failed check aborts with "assertion failed: <label>".

begin;

create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'assertion failed: %', label; end if;
end $$;

-- Expects the statement to fail with the given SQLSTATE.
create function pg_temp.fails(stmt text, state text, label text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlstate = state then return; end if;
    raise exception 'assertion failed: % (got % %)', label, sqlstate, sqlerrm;
  end;
  raise exception 'assertion failed: % (no error)', label;
end $$;

create function pg_temp.claims(c jsonb) returns void language sql as $$
  select set_config('request.jwt.claims', c::text, true)
$$;

-- No row: everything is open.
delete from public.service_status;
select pg_temp.check(public.access_state() = 'active', 'no row: active');
select public.check_request();

-- Paid well ahead.
insert into public.service_status (paid_until, grace_until, remind_from, message, contact)
values (public.business_today() + 10, public.business_today() + 17, public.business_today() + 3,
        'Pay ₹800 to keep WholeFlow running', 'UPI wholeflow@upi · 98470 00000');
select pg_temp.check(public.access_state() = 'active', 'paid: active');
select public.check_request();

update public.service_status set remind_from = public.business_today();
select pg_temp.check(public.access_state() = 'renewal_due', 'reminder day: renewal due');
select public.check_request();

update public.service_status set paid_until = public.business_today() - 1, grace_until = public.business_today() + 6;
select pg_temp.check(public.access_state() = 'grace', 'after paid_until: grace');
select public.check_request();

update public.service_status set grace_until = public.business_today();
select pg_temp.check(public.access_state() = 'grace', 'last grace day still works');

update public.service_status set grace_until = public.business_today() - 1;
select pg_temp.check(public.access_state() = 'ended', 'after grace: ended');
select pg_temp.fails('select public.check_request()', 'PT402', 'ended: every request refused with 402');
do $$
begin
  perform public.check_request();
exception when others then
  perform pg_temp.check(sqlerrm = 'subscription_ended', 'message is the code the apps look for');
  perform pg_temp.check(position('₹800' in coalesce((select message from public.service_status), '')) > 0, 'owner message kept');
end $$;

-- Suspended by the admin, even though paid.
update public.service_status set paid_until = public.business_today() + 30, grace_until = public.business_today() + 37,
                                 remind_from = public.business_today() + 23, status = 'suspended';
select pg_temp.check(public.access_state() = 'ended', 'suspended: ended');
select pg_temp.fails('select public.check_request()', 'PT402', 'suspended: refused');
update public.service_status set status = 'active';
select public.check_request();

-- A revoked PC's key is refused; another PC's key and user logins are not.
insert into public.revoked_devices (device_id) values ('11111111-1111-1111-1111-111111111111');
select pg_temp.claims('{"role":"service_role","device_id":"11111111-1111-1111-1111-111111111111"}');
select pg_temp.fails('select public.check_request()', 'PT403', 'revoked PC refused');
select pg_temp.claims('{"role":"service_role","device_id":"22222222-2222-2222-2222-222222222222"}');
select public.check_request();
select pg_temp.claims('{"role":"authenticated","sub":"33333333-3333-3333-3333-333333333333"}');
select public.check_request();

-- Who may read and change the status.
set local role authenticated;
select pg_temp.check((select count(*) from public.service_status) = 1, 'signed-in users read the status');
select pg_temp.fails('update public.service_status set status = ''active''', '42501', 'signed-in users cannot change it');
select pg_temp.fails('select count(*) from public.revoked_devices', '42501', 'signed-in users cannot read revoked PCs');
reset role;
set local role anon;
select pg_temp.fails('select count(*) from public.service_status', '42501', 'anonymous callers cannot read it');
reset role;

select 'service_control: all checks passed' as result;

rollback;
