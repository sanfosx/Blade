-- Gentleman's Blade — agenda inteligente (migración incremental).
-- Ejecutar UNA VEZ en el editor SQL del proyecto InsForge existente.
-- No requiere ni crea un backend nuevo.

-- La fecha de negocio se interpreta en Argentina, independientemente de la zona horaria del servidor.
alter table public.barber_appointments
  drop constraint if exists barber_appointments_preferred_date_check;
alter table public.barber_appointments
  add constraint barber_appointments_preferred_date_check
  check (preferred_date >= (timezone('America/Argentina/Buenos_Aires', now()))::date);

-- Duración de cada servicio; los slots públicos se ofrecen cada 30 minutos.
create or replace function public.barber_service_duration_minutes(p_service text)
returns integer
language sql
immutable
strict
as $$
  select case p_service
    when 'Corte clásico' then 30
    when 'Corte & barba' then 60
    when 'Afeitada tradicional' then 30
    when 'Perfilado de barba' then 30
    when 'Corte junior' then 30
    else null
  end;
$$;

-- Devuelve solo horarios libres, nunca datos personales ni filas de reservas.
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
  v_open_minutes integer;
  v_close_minutes integer;
  v_now_local timestamp;
  v_start_minutes integer;
begin
  v_duration := public.barber_service_duration_minutes(p_service);
  if v_duration is null then
    raise exception 'Servicio no válido';
  end if;

  v_now_local := timezone('America/Argentina/Buenos_Aires', now());
  if p_preferred_date is null or p_preferred_date < v_now_local::date then
    return;
  end if;

  -- ISO weekday: 1=lunes ... 7=domingo. Lunes y domingo cerrado.
  if extract(isodow from p_preferred_date) in (1, 7) then
    return;
  elsif extract(isodow from p_preferred_date) = 6 then
    v_open_minutes := 9 * 60;
    v_close_minutes := 17 * 60;
  else
    v_open_minutes := 9 * 60;
    v_close_minutes := 19 * 60;
  end if;

  for v_start_minutes in
    select minute_offset
    from generate_series(v_open_minutes, v_close_minutes - v_duration, 30) as slots(minute_offset)
  loop
    if p_preferred_date > v_now_local::date
       or (time '00:00' + make_interval(mins => v_start_minutes)) > v_now_local::time then
      if not exists (
        select 1
        from public.barber_appointments a
        where a.preferred_date = p_preferred_date
          and a.status in ('pending', 'confirmed')
          and a.preferred_time < (time '00:00' + make_interval(mins => v_start_minutes + v_duration))
          and (a.preferred_time + make_interval(mins => public.barber_service_duration_minutes(a.service)))
                > (time '00:00' + make_interval(mins => v_start_minutes))
      ) then
        slot := time '00:00' + make_interval(mins => v_start_minutes);
        return next;
      end if;
    end if;
  end loop;
end;
$$;

-- Inserción transaccional: bloquea la fecha, vuelve a comprobar solapamientos
-- y guarda únicamente si el horario sigue libre. La política evita carreras
-- entre dos usuarios que intenten reservar al mismo tiempo.
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
  v_open_minutes integer;
  v_close_minutes integer;
  v_now_local timestamp;
  v_start_minutes integer;
begin
  v_duration := public.barber_service_duration_minutes(p_service);
  if v_duration is null then
    raise exception 'Servicio no válido';
  end if;
  if p_customer_name is null or char_length(trim(p_customer_name)) not between 2 and 100 then
    raise exception 'Revisá el nombre ingresado';
  end if;
  if p_phone is null or char_length(trim(p_phone)) not between 7 and 30 then
    raise exception 'Revisá el teléfono ingresado';
  end if;
  if p_notes is not null and char_length(p_notes) > 500 then
    raise exception 'Las observaciones superan el límite permitido';
  end if;
  if p_preferred_date is null or p_preferred_time is null then
    raise exception 'Seleccioná fecha y horario';
  end if;

  v_now_local := timezone('America/Argentina/Buenos_Aires', now());
  if p_preferred_date < v_now_local::date then
    raise exception 'La fecha elegida ya pasó';
  end if;
  if extract(isodow from p_preferred_date) in (1, 7) then
    raise exception 'La barbería está cerrada ese día';
  elsif extract(isodow from p_preferred_date) = 6 then
    v_open_minutes := 9 * 60;
    v_close_minutes := 17 * 60;
  else
    v_open_minutes := 9 * 60;
    v_close_minutes := 19 * 60;
  end if;

  v_start_minutes := extract(hour from p_preferred_time)::integer * 60
                   + extract(minute from p_preferred_time)::integer;
  if extract(second from p_preferred_time) <> 0
     or mod(v_start_minutes, 30) <> 0
     or v_start_minutes < v_open_minutes
     or v_start_minutes + v_duration > v_close_minutes then
    raise exception 'El horario elegido está fuera del horario de atención';
  end if;
  if p_preferred_date = v_now_local::date and p_preferred_time <= v_now_local::time then
    raise exception 'Ese horario ya pasó';
  end if;

  -- Serializa las reservas del mismo día para evitar dobles reservas concurrentes.
  perform pg_advisory_xact_lock(hashtext('barber-appointments'), hashtext(p_preferred_date::text));

  if exists (
    select 1
    from public.barber_appointments a
    where a.preferred_date = p_preferred_date
      and a.status in ('pending', 'confirmed')
      and a.preferred_time < (p_preferred_time + make_interval(mins => v_duration))
      and (a.preferred_time + make_interval(mins => public.barber_service_duration_minutes(a.service)))
            > p_preferred_time
  ) then
    raise exception 'Ese horario ya no está disponible. Elegí otro.';
  end if;

  insert into public.barber_appointments (
    customer_name, phone, service, preferred_date, preferred_time, notes, status
  ) values (
    trim(p_customer_name), trim(p_phone), p_service, p_preferred_date,
    p_preferred_time, nullif(trim(coalesce(p_notes, '')), ''), 'pending'
  );
  return true;
end;
$$;

-- El público no puede leer, actualizar ni insertar directamente en la tabla.
-- Las funciones controladas son la única puerta pública para consultar horarios
-- libres y crear solicitudes; ambas están limitadas a los datos necesarios.
drop policy if exists "public can submit pending barber appointments"
  on public.barber_appointments;
revoke all on table public.barber_appointments from anon, authenticated;
grant usage on schema public to anon;
revoke all on function public.barber_service_duration_minutes(text) from public, anon, authenticated;
revoke all on function public.get_available_barber_slots(date, text) from public, anon, authenticated;
revoke all on function public.create_barber_appointment(text, text, text, date, time, text) from public, anon, authenticated;
grant execute on function public.get_available_barber_slots(date, text) to anon;
grant execute on function public.create_barber_appointment(text, text, text, date, time, text) to anon;
