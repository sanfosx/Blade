-- Gentleman's Blade — reprogramación segura desde el panel de administración.
-- Requiere agenda_inteligente.sql, admin_sanfosx.sql y agenda_configurable.sql.
-- Ejecutar una sola vez en el editor SQL de InsForge. No usar BEGIN/COMMIT.

create or replace function public.admin_reschedule_barber_appointment(
  p_appointment_id uuid,
  p_preferred_date date,
  p_preferred_time time
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_service text;
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
  if auth.uid() is null or not public.is_barber_admin() then
    raise exception 'No autorizado para reprogramar turnos';
  end if;
  if p_appointment_id is null or p_preferred_date is null or p_preferred_time is null then
    raise exception 'Seleccioná el turno, la fecha y el horario';
  end if;

  select a.service, a.status
    into v_service, v_status
  from public.barber_appointments a
  where a.id = p_appointment_id
  for update;

  if not found then raise exception 'No se encontró el turno'; end if;
  if v_status not in ('pending','confirmed') then
    raise exception 'Solo se pueden reprogramar turnos pendientes o confirmados';
  end if;

  v_duration := public.barber_service_duration_minutes(v_service);
  if v_duration is null then raise exception 'No se pudo determinar la duración del servicio'; end if;

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

  if extract(second from p_preferred_time) <> 0
     or mod(v_start_minutes, 30) <> 0
     or v_start_minutes < v_open_minutes
     or v_start_minutes + v_duration > v_close_minutes then
    raise exception 'El horario no respeta la apertura, el cierre o la duración del servicio';
  end if;
  if p_preferred_date = v_now_local::date and p_preferred_time <= v_now_local::time then
    raise exception 'Ese horario ya pasó';
  end if;

  perform pg_advisory_xact_lock(hashtext('barber-appointments'), hashtext(p_preferred_date::text));

  if exists (
    select 1
    from public.barber_appointments a
    where a.id <> p_appointment_id
      and a.preferred_date = p_preferred_date
      and a.status in ('pending','confirmed')
      and a.preferred_time < (p_preferred_time + make_interval(mins => v_duration))
      and (a.preferred_time + make_interval(mins => coalesce(public.barber_service_duration_minutes(a.service),30))) > p_preferred_time
  ) then
    raise exception 'Ese horario ya está ocupado. Elegí otro';
  end if;

  update public.barber_appointments
  set preferred_date = p_preferred_date,
      preferred_time = p_preferred_time
  where id = p_appointment_id;
  return true;
end;
$$;

revoke all on function public.admin_reschedule_barber_appointment(uuid, date, time) from public, anon;
grant execute on function public.admin_reschedule_barber_appointment(uuid, date, time) to authenticated;
