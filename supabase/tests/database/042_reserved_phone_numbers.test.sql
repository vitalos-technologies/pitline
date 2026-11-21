begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(6);

-- SOB Autofix's lines are never Pitline's (20261121000000_reserved_phone_numbers.sql,
-- DECISIONS D29): garage_phone_numbers refuses them on insert and update, in any
-- purpose, while ordinary numbers still route.

insert into public.garages (id, slug, name, booking_prefix, mot_enabled, status) values
  ('a1720000-0000-4000-8000-000000000001', 'pgtap-reserved-numbers', 'Reserved Numbers Garage', 'RSV', false, 'active');

select ok(
  exists (select 1 from pg_constraint where conname = 'garage_phone_numbers_not_reserved_check' and conrelid = 'public.garage_phone_numbers'::regclass),
  'garage_phone_numbers has the reserved-number check'
);

select throws_ok(
  $$insert into public.garage_phone_numbers (garage_id, number, purpose, provider_sid) values ('a1720000-0000-4000-8000-000000000001', '+447469273483', 'messaging', 'PNpgtapreserved01')$$,
  '23514', null, 'SOB Autofix''s phone number is refused'
);
select throws_ok(
  $$insert into public.garage_phone_numbers (garage_id, number, purpose) values ('a1720000-0000-4000-8000-000000000001', '+447468273483', 'forwarding')$$,
  '23514', null, 'SOB Autofix''s WhatsApp number is refused too'
);

select lives_ok(
  $$insert into public.garage_phone_numbers (id, garage_id, number, purpose, provider_sid) values ('a1720000-0000-4000-8000-000000000101', 'a1720000-0000-4000-8000-000000000001', '+447700917101', 'messaging', 'PNpgtapreserved02')$$,
  'an ordinary number still routes'
);
select throws_ok(
  $$update public.garage_phone_numbers set number = '+447469273483' where id = 'a1720000-0000-4000-8000-000000000101'$$,
  '23514', null, 'a row cannot be changed to SOB Autofix''s number'
);
select is(
  (select number from public.garage_phone_numbers where id = 'a1720000-0000-4000-8000-000000000101'),
  '+447700917101',
  'the ordinary row is unchanged'
);

select * from finish();
rollback;
