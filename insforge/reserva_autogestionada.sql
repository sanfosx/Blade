-- Gentleman's Blade — gestión privada de la reserva desde el navegador.
-- Ejecutar UNA VEZ en el editor SQL de InsForge, después de agenda_configurable.sql.
-- No usar BEGIN/COMMIT. El token de gestión funciona como una clave secreta de la reserva.
create extension if not exists pgcrypto;

alter table public.barber_appointments
  add column if not exists management_token_hash text;

create or replace function public.create_managed_barber_appointment(
  p_customer_name text,
  p_phone text,
  p_service text,
  p_preferred_date date,
  p_preferred_time time,
  p_notes text,
  p_management_token text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_duration integer;
  v_open time;
  v_close time;
  v_closed boolean;
  v_open_minutes integer;
  v_close_minutes integer;
  v_start_minutes integer;
  v_now_local timestamp;
begin
  if p_management_token is null or length(p_management_token) < 32 then
    raise exception 'No se pudo generar la clave de gestión de la reserva';
  end if;
  if p_customer_name is null or char_length(trim(p_customer_name)) not between 2 and 100 then raise exception 'Revisá el nombre ingresado'; end if;
  if p_phone is null or char_length(trim(p_phone)) not between 7 and 30 then raise exception 'Revisá el teléfono ingresado'; end if;
  if p_notes is not null and char_length(p_notes) > 500 then raise exception 'Las observaciones superan el límite permitido'; end if;
  if not exists(select 1 from public.barber_services s where s.service_name=p_service and s.is_active=true) then raise exception 'Servicio no válido o inactivo'; end if;
  v_duration := public.barber_service_duration_minutes(p_service);
  if v_duration is null then raise exception 'Servicio no válido o inactivo'; end if;
  if p_preferred_date is null or p_preferred_time is null then raise exception 'Seleccioná fecha y horario'; end if;

  v_now_local := timezone('America/Argentina/Buenos_Aires', now());
  if p_preferred_date < v_now_local::date then raise exception 'La fecha elegida ya pasó'; end if;
  select h.opens_at,h.closes_at,h.is_closed into v_open,v_close,v_closed
    from public.barber_business_hours h
    where h.iso_weekday=extract(isodow from p_preferred_date)::smallint;
  if not found or v_closed then raise exception 'La barbería está cerrada ese día'; end if;

  v_open_minutes := extract(hour from v_open)::integer*60+extract(minute from v_open)::integer;
  v_close_minutes := extract(hour from v_close)::integer*60+extract(minute from v_close)::integer;
  v_start_minutes := extract(hour from p_preferred_time)::integer*60+extract(minute from p_preferred_time)::integer;
  if extract(second from p_preferred_time)<>0 or mod(v_start_minutes,30)<>0
    or v_start_minutes<v_open_minutes or v_start_minutes+v_duration>v_close_minutes then
    raise exception 'El horario no respeta la apertura, el cierre o la duración del servicio';
  end if;
  if p_preferred_date=v_now_local::date and p_preferred_time<=v_now_local::time then raise exception 'Ese horario ya pasó'; end if;

  perform pg_advisory_xact_lock(hashtext('barber-appointments'),hashtext(p_preferred_date::text));
  if exists(
    select 1 from public.barber_appointments a
    where a.preferred_date=p_preferred_date and a.status in ('pending','confirmed')
      and a.preferred_time < (p_preferred_time + make_interval(mins=>v_duration))
      and (a.preferred_time + make_interval(mins=>coalesce(public.barber_service_duration_minutes(a.service),30))) > p_preferred_time
  ) then raise exception 'Ese horario ya no está disponible. Elegí otro.'; end if;

  insert into public.barber_appointments(customer_name,phone,service,preferred_date,preferred_time,notes,status,management_token_hash)
  values(trim(p_customer_name),trim(p_phone),p_service,p_preferred_date,p_preferred_time,nullif(trim(coalesce(p_notes,'')),''),'pending',
    encode(digest(convert_to(p_management_token,'UTF8'),'sha256'),'hex'))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.update_managed_barber_appointment(
  p_appointment_id uuid,
  p_management_token text,
  p_service text,
  p_preferred_date date,
  p_preferred_time time
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status text;
  v_duration integer;
  v_open time;
  v_close time;
  v_closed boolean;
  v_open_minutes integer;
  v_close_minutes integer;
  v_start_minutes integer;
  v_now_local timestamp;
begin
  if p_management_token is null then raise exception 'Clave de gestión inválida'; end if;
  select a.status into v_status from public.barber_appointments a
    where a.id=p_appointment_id
      and a.management_token_hash=encode(digest(convert_to(p_management_token,'UTF8'),'sha256'),'hex')
    for update;
  if not found then raise exception 'No se encontró la reserva o la clave de gestión no es válida'; end if;
  if v_status not in ('pending','confirmed') then raise exception 'Solo se puede modificar una reserva pendiente o confirmada'; end if;
  if not exists(select 1 from public.barber_services s where s.service_name=p_service and s.is_active=true) then raise exception 'Servicio no válido o inactivo'; end if;
  v_duration:=public.barber_service_duration_minutes(p_service);
  if v_duration is null then raise exception 'Servicio no válido o inactivo'; end if;
  if p_preferred_date is null or p_preferred_time is null then raise exception 'Seleccioná fecha y horario'; end if;
  v_now_local:=timezone('America/Argentina/Buenos_Aires',now());
  if p_preferred_date<v_now_local::date then raise exception 'La fecha elegida ya pasó'; end if;
  select h.opens_at,h.closes_at,h.is_closed into v_open,v_close,v_closed
    from public.barber_business_hours h where h.iso_weekday=extract(isodow from p_preferred_date)::smallint;
  if not found or v_closed then raise exception 'La barbería está cerrada ese día'; end if;
  v_open_minutes:=extract(hour from v_open)::integer*60+extract(minute from v_open)::integer;
  v_close_minutes:=extract(hour from v_close)::integer*60+extract(minute from v_close)::integer;
  v_start_minutes:=extract(hour from p_preferred_time)::integer*60+extract(minute from p_preferred_time)::integer;
  if extract(second from p_preferred_time)<>0 or mod(v_start_minutes,30)<>0 or v_start_minutes<v_open_minutes or v_start_minutes+v_duration>v_close_minutes then
    raise exception 'El horario no respeta la apertura, el cierre o la duración del servicio';
  end if;
  if p_preferred_date=v_now_local::date and p_preferred_time<=v_now_local::time then raise exception 'Ese horario ya pasó'; end if;
  perform pg_advisory_xact_lock(hashtext('barber-appointments'),hashtext(p_preferred_date::text));
  if exists(
    select 1 from public.barber_appointments a
    where a.id<>p_appointment_id and a.preferred_date=p_preferred_date and a.status in ('pending','confirmed')
      and a.preferred_time < (p_preferred_time + make_interval(mins=>v_duration))
      and (a.preferred_time + make_interval(mins=>coalesce(public.barber_service_duration_minutes(a.service),30))) > p_preferred_time
  ) then raise exception 'Ese horario ya está ocupado. Elegí otro.'; end if;
  update public.barber_appointments set service=p_service,preferred_date=p_preferred_date,preferred_time=p_preferred_time
    where id=p_appointment_id;
  return true;
end;
$$;

create or replace function public.cancel_managed_barber_appointment(
  p_appointment_id uuid,
  p_management_token text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_status text;
begin
  if p_management_token is null then raise exception 'Clave de gestión inválida'; end if;
  select a.status into v_status from public.barber_appointments a
    where a.id=p_appointment_id
      and a.management_token_hash=encode(digest(convert_to(p_management_token,'UTF8'),'sha256'),'hex')
    for update;
  if not found then raise exception 'No se encontró la reserva o la clave de gestión no es válida'; end if;
  if v_status='cancelled' then return true; end if;
  update public.barber_appointments set status='cancelled' where id=p_appointment_id;
  return true;
end;
$$;

revoke all on function public.create_managed_barber_appointment(text,text,text,date,time,text,text) from public, anon, authenticated;
revoke all on function public.update_managed_barber_appointment(uuid,text,text,date,time) from public, anon, authenticated;
revoke all on function public.cancel_managed_barber_appointment(uuid,text) from public, anon, authenticated;
grant execute on function public.create_managed_barber_appointment(text,text,text,date,time,text,text) to anon;
grant execute on function public.update_managed_barber_appointment(uuid,text,text,date,time) to anon;
grant execute on function public.cancel_managed_barber_appointment(uuid,text) to anon;

-- El token nunca se devuelve desde una consulta pública: solo se conoce en la sesión
-- del navegador que creó la reserva. El hash queda almacenado en la tabla.
