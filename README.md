# Gentleman's Blade — sitio web vintage

Landing page responsive en español, construida con HTML, CSS y JavaScript sin dependencias de compilación.

## Uso
Abrí `index.html` en un navegador o habilitá GitHub Pages para publicarlo.

## Antes de publicar
- Reemplazar los precios ilustrativos por precios reales.
- Cambiar nombres, retratos, horarios y dirección por datos autorizados del negocio.
- Configurar el CTA de reserva con un email real, WhatsApp o sistema de turnos.
- Las fuentes y fotografías se cargan desde servicios externos.

## InsForge
Este frontend todavía no está conectado a InsForge. Para persistir reservas, crear una tabla `appointments` con políticas RLS apropiadas y conectar el formulario mediante `@insforge/sdk` usando URL y clave pública/anon. Nunca incluir una clave administrativa en el navegador.


## Reservas con InsForge

El formulario envía solicitudes persistentes a la tabla `public.barber_appointments` del proyecto InsForge existente. La agenda inteligente consulta slots disponibles y crea reservas mediante funciones SQL transaccionales.

1. Aplicá el SQL de `insforge/barber_appointments.sql` en el editor SQL de ese proyecto.
2. `insforge-config.js` contiene la URL y la **clave pública ANON_KEY** necesaria para el frontend estático. No pongas una API key administrativa en este archivo.
3. Probá una solicitud desde la web y comprobá que aparezca con estado `pending` en la tabla.
4. El formulario no confirma disponibilidad: la barbería debe confirmar cada solicitud manualmente.

### Seguridad

La migración activa RLS y permite al rol anónimo únicamente insertar solicitudes pendientes; no concede lectura, actualización ni eliminación. La validación del navegador mejora la experiencia, pero las restricciones de la base de datos son la validación de seguridad. Antes de producción, agregá protección contra spam/rate limiting y una vista o panel administrativo con autenticación para gestionar solicitudes.

### Mensajes de WhatsApp desde el panel

- Cada reserva incluye un enlace para abrir WhatsApp con un mensaje preparado según su estado: solicitud recibida, turno confirmado o turno cancelado.
- El mensaje **no se envía automáticamente**: el administrador lo revisa y lo envía desde WhatsApp.
- Para números locales argentinos de 10 dígitos, el enlace agrega el prefijo móvil internacional `549`. También acepta números que ya comienzan con `54` o `549`.
- Si el teléfono no tiene un formato reconocible, revisá el número y guardalo con el código de país. No se integra la API de WhatsApp ni se almacenan tokens de WhatsApp.

### Publicación

Subí `index.html`, `insforge-config.js` y la migración SQL al mismo despliegue estático. No se debe publicar ninguna clave administrativa o secreta.


### Agenda inteligente — migración adicional

La migración `insforge/agenda_inteligente.sql` añade:
- Disponibilidad calculada por servicio, duración y horario de atención (martes a viernes 09:00–19:00; sábado 09:00–17:00; lunes y domingo cerrado).
- Horarios cada 30 minutos y exclusión de turnos pasados según hora de Argentina.
- Prevención transaccional de solapamientos entre solicitudes pendientes y turnos confirmados, incluso ante solicitudes simultáneas.
- Funciones públicas limitadas a devolver horarios libres y crear solicitudes. No habilita lectura pública de nombres, teléfonos ni notas.
- Validación de fecha, hora, servicio, nombre, teléfono y observaciones en la base de datos.

**Activación necesaria:** ejecutar `insforge/agenda_inteligente.sql` una vez en el editor SQL del mismo proyecto InsForge. Después esperar el despliegue de GitHub Pages y probar con dos solicitudes al mismo horario: la primera debe guardarse y la segunda debe rechazarse. El código web por sí solo no activa funciones en la base de datos.


### Panel privado de administración

- Abrí `/admin.html` para iniciar sesión con InsForge.
- Ejecutá `insforge/admin_panel.sql` una vez en el mismo backend para habilitar la tabla de administradores y las políticas RLS del panel.
- Creá/verificá la cuenta del propietario en InsForge Authentication. Después, en el SQL comentado al final de la migración, reemplazá el correo por el correo exacto del propietario y ejecutá solo esa sentencia de promoción.
- El panel permite consultar reservas y cambiar su estado. Las políticas de base de datos limitan estas operaciones a usuarios promovidos explícitamente.
- No habilites registro público para administrar el negocio y nunca incluyas credenciales administrativas en archivos del frontend.
