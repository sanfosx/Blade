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

El formulario envía solicitudes persistentes a la tabla `public.barber_appointments` del proyecto InsForge existente.

1. Aplicá el SQL de `insforge/barber_appointments.sql` en el editor SQL de ese proyecto.
2. `insforge-config.js` contiene la URL y la **clave pública ANON_KEY** necesaria para el frontend estático. No pongas una API key administrativa en este archivo.
3. Probá una solicitud desde la web y comprobá que aparezca con estado `pending` en la tabla.
4. El formulario no confirma disponibilidad: la barbería debe confirmar cada solicitud manualmente.

### Seguridad

La migración activa RLS y permite al rol anónimo únicamente insertar solicitudes pendientes; no concede lectura, actualización ni eliminación. La validación del navegador mejora la experiencia, pero las restricciones de la base de datos son la validación de seguridad. Antes de producción, agregá protección contra spam/rate limiting y una vista o panel administrativo con autenticación para gestionar solicitudes.

### Publicación

Subí `index.html`, `insforge-config.js` y la migración SQL al mismo despliegue estático. No se debe publicar ninguna clave administrativa o secreta.
