-- Gentleman's Blade — configuración editable de agenda.
-- Ejecutar UNA VEZ en el editor SQL del mismo proyecto InsForge.
-- No usar BEGIN/COMMIT en el editor de InsForge.
-- Aplicar después de agenda_inteligente.sql y admin_sanfosx.sql.

create table if not exists public.barber_business_hours (
  iso_weekday smallint primary key check (iso_weekday between 1 and 7),
  day_name text not null,
  opens_at time,
  closes_at time,
  is_closed boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint barber_hours_valid_range check (
    (is_closed = true and opens_at is null and closes_at is null)
    or
    (is_closed = false and opens_at is not null and closes_at is not null
      and opens_at < closes_at)
  )
);

insert into public.barber_business_hours
  (iso_weekday, day_name, opens_at, closes_at, is_closed)
values
  (1, 'Lunes', null, null, true),
  (2, 'Martes', '09:00', '19:00', false),
  (3, 'Miércoles', '09:00', '19:00', false),
  (4, 'Jueves', '09:00', '19:00', false),
  (5, 'Viernes', '09:00', '19:00', false),
  (6, 'Sábado', '09:00', '17:00', false),
  (7, 'Domingo', null, null, true)
on conflict (iso_weekday) do nothing;

create table if not exists public.barber_services (
  service_name text primary key,
  duration_minutes integer not null check (duration_minutes between 15 and 240 and mod(duration_minutes, 15) = 0),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.barber_services (service_name, duration_minutes, is_active)
values
  ('Corte clásico', 30, true),
  ('Corte & barba', 60, true),
  ('Afeitada tradicional', 30, true),
  ('Perfilado de barba', 30, true),
  ('Corte junior', 30, true)
on conflict (service_name) do nothing;

alter table public.barber_business_hours enable row level security;
alter table public.barber_services enable row level security;
revoke all on public.barber_business_hours, public.barber_services from public, anon, authenticated;
grant select, update on public.barber_business_hours, public.barber_services to authenticated;

drop policy if exists "barber admins can read business hours" on public.barber_business_hours;
create policy "barber admins can read business hours"
  on public.barber_business_hours for select to authenticated
  using (public.is_barber_admin());
drop policy if exists "barber admins can update business hours" on public.barber_business_hours;
create policy "barber admins can update business hours"
  on public.barber_business_hours for update to authenticated
  using (public.is_barber_admin()) with check (public.is_barber_admin());

drop policy if exists "barber admins can read services" on public.barber_services;
create policy "barber admins can read services"
  on public.barber_services for select to authenticated
  using (public.is_barber_admin());
drop policy if exists "barber admins can update services" on public.barber_services;
create policy "barber admins can update services"
  on public.barber_services for update to authenticated
  using (public.is_barber_admin()) with check (public.is_barber_admin());

-- El cliente público puede consultar horarios comerciales, pero no editar nada.
create or replace function public.get_public_barber_business_hours()
returns table(iso_weekday smallint, day_name text, opens_at time, closes_at time, is_closed boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select h.iso_weekday, h.day_name, h.opens_at, h.closes_at, h.is_closed
  from public.barber_business_hours h
  order by h.iso_weekday;
$$;
revoke all on function public.get_public_barber_business_hours() from public, authenticated;
grant execute on function public.get_public_barber_business_hours() to anon;

create or replace function public.barber_service_duration_minutes(p_service text)
returns integer
language sql
stable
strict
security definer
set search_path = public, pg_temp
as $$
  select s.duration_minutes
  from public.barber_services s
  where s.service_name = p_service and s.is_active = true;
$$;
revoke all on function public.barber_service_duration_minutes(text) from public, anon, authenticated;

create or replace function public.get_available_barber_slots(
  p_preferred_date date,
  p_service text
)
returns table(slot time)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_duration integer;
  v_open time;
  v_close time;
  v_closed boolean;
  v_open_minutes integer;
  v_close_minutes integer;
  v_now_local timestamp;
  v_start_minutes integer;
begin
  v_duration := public.barber_service_duration_minutes(p_service);
  if v_duration is null then raise exception 'Servicio no válido o inactivo'; end if;
  v_now_local := timezone('America/Argentina/Buenos_Aires', now());
  if p_preferred_date is null or p_preferred_date < v_now_local::date then return; end if;

  select h.opens_at, h.closes_at, h.is_closed
    into v_open, v_close, v_closed
  from public.barber_business_hours h
  where h.iso_weekday = extract(isodow from p_preferred_date)::smallint;
  if not found or v_closed then return; end if;

  v_open_minutes := extract(hour from v_open)::integer * 60 + extract(minute from v_open)::integer;
  v_close_minutes := extract(hour from v_close)::integer * 60 + extract(minute from v_close)::integer;
  for v_start_minutes in
    select minute_offset from generate_series(v_open_minutes, v_close_minutes - v_duration, 30) as slots(minute_offset)
  loop
    if p_preferred_date > v_now_local::date
       or (time '00:00' + make_interval(mins => v_start_minutes)) > v_now_local::time then
      if not exists (
        select 1 from public.barber_appointments a
        where a.preferred_date = p_preferred_date
          and a.status in ('pending', 'confirmed')
          and a.preferred_time < (time '00:00' + make_interval(mins => v_start_minutes + v_duration))
          and (a.preferred_time + make_interval(mins => coalesce(public.barber_service_duration_minutes(a.service), 30)))
                > (time '00:00' + make_interval(mins => v_start_minutes))
      ) then
        slot := time '00:00' + make_interval(mins => v_start_minutes);
        return next;
      end if;
    end if;
  end loop;
end;
$$;

create or replace function public.create_barber_appointment(
  p_customer_name text,
  p_phone text,
  p_service text,
  p_preferred_date date,
  p_preferred_time time,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_duration integer;
  v_open time;
  v_close time;
  v_closed boolean;
  v_open_minutes integer;
  v_close_minutes integer;
  v_now_local timestamp;
  v_start_minutes integer;
begin
  v_duration := public.barber_service_duration_minutes(p_service);
  if v_duration is null then raise exception 'Servicio no válido o inactivo'; end if;
  if p_customer_name is null or char_length(trim(p_customer_name)) not between 2 and 100 then raise exception 'Revisá el nombre ingresado'; end if;
  if p_phone is null or char_length(trim(p_phone)) not between 7 and 30 then raise exception 'Revisá el teléfono ingresado'; end if;
  if p_notes is not null and char_length(p_notes) > 500 then raise exception 'Las observaciones superan el límite permitido'; end if;
  if p_preferred_date is null or p_preferred_time is null then raise exception 'Seleccioná fecha y horario'; end if;

  v_now_local := timezone('America/Argentina/Buenos_Aires', now());
  if p_preferred_date < v_now_local::date then raise exception 'La fecha elegida ya pasó'; end if;

  select h.opens_at, h.closes_at, h.is_closed
    into v_open, v_close, v_closed
  from public.barber_business_hours h
  where h.iso_weekday = extract(isodow from p_preferred_date)::smallint;
  if not found or v_closed then raise exception 'La barbería está cerrada ese día'; end if;

  v_open_minutes := extract(hour from v_open)::integer * 60 + extract(minute from v_open)::integer;
  v_close_minutes := extract(hour from v_close)::integer * 60 + extract(minute from v_close)::integer;
  v_start_minutes := extract(hour from p_preferred_time)::integer * 60 + extract(minute from p_preferred_time)::integer;
  if extract(second from p_preferred_time) <> 0 or mod(v_start_minutes, 30) <> 0
     or v_start_minutes < v_open_minutes or v_start_minutes + v_duration > v_close_minutes then
    raise exception 'El horario elegido está fuera del horario de atención';
  end if;
  if p_preferred_date = v_now_local::date and p_preferred_time <= v_now_local::time then raise exception 'Ese horario ya pasó'; end if;

  perform pg_advisory_xact_lock(hashtext('barber-appointments'), hashtext(p_preferred_date::text));
  if exists (
    select 1 from public.barber_appointments a
    where a.preferred_date = p_preferred_date
      and a.status in ('pending', 'confirmed')
      and a.preferred_time < (p_preferred_time + make_interval(mins => v_duration))
      and (a.preferred_time + make_interval(mins => coalesce(public.barber_service_duration_minutes(a.service), 30))) > p_preferred_time
  ) then raise exception 'Ese horario ya no está disponible. Elegí otro.'; end if;

  insert into public.barber_appointments (customer_name, phone, service, preferred_date, preferred_time, notes, status)
  values (trim(p_customer_name), trim(p_phone), p_service, p_preferred_date, p_preferred_time, nullif(trim(coalesce(p_notes, '')), ''), 'pending');
  return true;
end;
$$;

revoke all on function public.get_available_barber_slots(date, text) from public, anon, authenticated;
revoke all on function public.create_barber_appointment(text, text, text, date, time, text) from public, anon, authenticated;
grant execute on function public.get_available_barber_slots(date, text) to anon;
grant execute on function public.create_barber_appointment(text, text, text, date, time, text) to anon;

-- Servicios activos para que el formulario público refleje la configuración del propietario.
create or replace function public.get_public_barber_services()
returns table(service_name text, duration_minutes integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select s.service_name, s.duration_minutes
  from public.barber_services s
  where s.is_active = true
  order by s.service_name;
$$;
revoke all on function public.get_public_barber_services() from public, authenticated;
grant execute on function public.get_public_barber_services() to anon;
