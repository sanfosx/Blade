-- Gentleman's Blade — panel privado de gestión (migración incremental).
-- Ejecutar una vez en el editor SQL del proyecto InsForge EXISTENTE.
-- Después crear un usuario desde Authentication > Users o mediante el flujo
-- autorizado de registro. Promover solo al propietario mediante el SQL comentado
-- al final. No habilitar registro público desde el panel de administración.

create table if not exists public.barber_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.barber_admins enable row level security;
revoke all on public.barber_admins from anon, authenticated;
grant usage on schema public to authenticated;

create or replace function public.is_barber_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select exists (
    select 1 from public.barber_admins ba
    where ba.user_id = auth.uid()
  );
$$;

revoke all on function public.is_barber_admin() from public, anon;
grant execute on function public.is_barber_admin() to authenticated;

-- Admins can read appointments and change only status. Personal data remains
-- visible only to an authenticated user explicitly promoted in barber_admins.
drop policy if exists "barber admins can read appointments" on public.barber_appointments;
create policy "barber admins can read appointments"
  on public.barber_appointments for select to authenticated
  using (public.is_barber_admin());

drop policy if exists "barber admins can update appointments" on public.barber_appointments;
create policy "barber admins can update appointments"
  on public.barber_appointments for update to authenticated
  using (public.is_barber_admin())
  with check (public.is_barber_admin());

grant select on public.barber_appointments to authenticated;
grant update (status) on public.barber_appointments to authenticated;

-- PROMOCIÓN DEL PROPIETARIO (ejecutar por separado, reemplazando el email):
-- insert into public.barber_admins (user_id)
-- select id from auth.users where lower(email) = lower('TU_EMAIL_DE_PROPIETARIO')
-- on conflict (user_id) do nothing;
-- Comprobar que la consulta devuelve exactamente un usuario antes de confiar
-- en el panel. Nunca promover usuarios no verificados/no autorizados.
