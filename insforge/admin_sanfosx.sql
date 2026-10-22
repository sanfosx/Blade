-- Gentleman's Blade — configuración final del administrador propietario.
-- Proyecto: InsForge existente. Ejecutar DESPUÉS de insforge/agenda_inteligente.sql.
-- Requisito: sanfosx@gmail.com debe existir en InsForge Authentication > Users.
-- Este script no crea usuarios ni habilita el registro público.
-- No usar BEGIN/COMMIT: el editor SQL de InsForge gestiona las transacciones.

-- Lista de usuarios autorizados a administrar la agenda.
create table if not exists public.barber_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.barber_admins enable row level security;
revoke all on public.barber_admins from public, anon, authenticated;
grant usage on schema public to authenticated;

-- Comprueba el usuario autenticado contra la lista privada de administradores.
create or replace function public.is_barber_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select exists (
    select 1
    from public.barber_admins ba
    where ba.user_id = auth.uid()
  );
$$;

revoke all on function public.is_barber_admin() from public, anon;
grant execute on function public.is_barber_admin() to authenticated;

-- Permisos limitados: los administradores pueden consultar reservas y modificar
-- únicamente la columna status, no los datos personales ni otros campos.
alter table public.barber_appointments enable row level security;

drop policy if exists "barber admins can read appointments"
  on public.barber_appointments;
create policy "barber admins can read appointments"
  on public.barber_appointments
  for select to authenticated
  using (public.is_barber_admin());

drop policy if exists "barber admins can update appointments"
  on public.barber_appointments;
create policy "barber admins can update appointments"
  on public.barber_appointments
  for update to authenticated
  using (public.is_barber_admin())
  with check (public.is_barber_admin());

grant select on public.barber_appointments to authenticated;
grant update (status) on public.barber_appointments to authenticated;

-- Promueve exactamente el usuario propietario indicado.
-- Si no existe en Auth, esta sección lanza un error y no lo crea.
do $$
declare
  v_user_id uuid;
begin
  select u.id
    into v_user_id
  from auth.users u
  where lower(u.email) = lower('sanfosx@gmail.com');

  if v_user_id is null then
    raise exception
      'No existe sanfosx@gmail.com en auth.users. Creá/verificá primero el usuario en InsForge Authentication y volvé a ejecutar este SQL.';
  end if;

  insert into public.barber_admins (user_id)
  values (v_user_id)
  on conflict (user_id) do nothing;
end;
$$;

-- Verificación: debe devolver una fila para sanfosx@gmail.com.
select u.email, ba.user_id, ba.created_at
from public.barber_admins ba
join auth.users u on u.id = ba.user_id
where lower(u.email) = lower('sanfosx@gmail.com');
