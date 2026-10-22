-- Gentleman's Blade: solicitudes de turno.
-- Aplicar en el proyecto InsForge existente.
create table if not exists public.barber_appointments (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null check (char_length(trim(customer_name)) between 2 and 100),
  phone text not null check (char_length(trim(phone)) between 7 and 30),
  service text not null check (service in (
    'Corte clásico', 'Corte & barba', 'Afeitada tradicional',
    'Perfilado de barba', 'Corte junior'
  )),
  preferred_date date not null check (preferred_date >= current_date),
  preferred_time time not null,
  notes text null check (notes is null or char_length(notes) <= 500),
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'cancelled')),
  created_at timestamptz not null default now()
);

alter table public.barber_appointments enable row level security;

-- El público solo puede crear solicitudes pendientes; no puede leerlas,
-- modificarlas ni borrarlas. La gestión interna requiere un rol autenticado
-- y políticas administrativas separadas.
drop policy if exists "public can submit pending barber appointments"
  on public.barber_appointments;
create policy "public can submit pending barber appointments"
  on public.barber_appointments
  for insert to anon
  with check (status = 'pending');

revoke all on table public.barber_appointments from anon, authenticated;
grant insert (
  customer_name, phone, service, preferred_date, preferred_time, notes
) on table public.barber_appointments to anon;
