-- Gentleman's Blade — habilitar alta de servicios desde el panel de administración.
-- Ejecutar UNA VEZ en el editor SQL de InsForge después de agenda_configurable.sql.
-- No usar BEGIN/COMMIT en el editor de InsForge.

alter table public.barber_services enable row level security;

grant select, update, insert on public.barber_services to authenticated;
revoke all on public.barber_services from public, anon;

drop policy if exists "barber admins can insert services" on public.barber_services;
create policy "barber admins can insert services"
  on public.barber_services
  for insert
  to authenticated
  with check (public.is_barber_admin());

-- Reafirma que solo administradores autenticados pueden leer o modificar servicios.
drop policy if exists "barber admins can read services" on public.barber_services;
create policy "barber admins can read services"
  on public.barber_services
  for select
  to authenticated
  using (public.is_barber_admin());

drop policy if exists "barber admins can update services" on public.barber_services;
create policy "barber admins can update services"
  on public.barber_services
  for update
  to authenticated
  using (public.is_barber_admin())
  with check (public.is_barber_admin());

-- No se concede DELETE: los servicios se retiran desmarcando is_active,
-- para conservar referencias legibles en el historial de turnos.
