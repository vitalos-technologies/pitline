-- SOB Autofix's lines are never Pitline's (DECISIONS D29, Temitope, 21 Nov 2026).
--
-- garage_phone_numbers holds the Twilio numbers Pitline routes to a garage. Neither
-- of SOB Autofix's numbers (phone 07469 273483, the 07468 273483 its spec gave
-- for WhatsApp) may ever be one, whoever writes the row. The same list is in
-- src/lib/calls/reserved-numbers.json; src/__tests__/reserved-numbers.test.ts
-- checks they agree. To add a number: a new migration that drops and re-adds
-- this constraint with the whole list.

alter table public.garage_phone_numbers
  add constraint garage_phone_numbers_not_reserved_check
  check (number not in ('+447469273483', '+447468273483'));

comment on constraint garage_phone_numbers_not_reserved_check on public.garage_phone_numbers is
  'SOB Autofix''s numbers are never Pitline''s (DECISIONS D29). List shared with src/lib/calls/reserved-numbers.json.';
