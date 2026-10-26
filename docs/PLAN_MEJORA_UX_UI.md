# Plan de mejora UX/UI — Gentleman's Blade

## Objetivo
Mejorar la claridad, confianza y seguridad de la experiencia de reservas y del panel privado, manteniendo la estética vintage (azul marino, bordó, crema, Roboto Slab y Special Elite) y preservando las validaciones existentes de InsForge.

## Criterios de diseño
- Mensajes breves, en español rioplatense y con una acción siguiente clara.
- Confirmaciones explícitas antes de operaciones sensibles; cancelar debe ser seguro por defecto.
- Estados de carga visibles y botones bloqueados mientras se procesa una operación.
- Errores comprensibles; detalles técnicos solo cuando ayuden a diagnosticar.
- Teclado, foco visible, etiquetas y anuncios de estado accesibles.
- Diseño responsive y respeto por `prefers-reduced-motion`.

## Fase 1 — Confirmaciones y feedback (implementación inicial)
- Diálogos vintage para reprogramar turnos, cambiar estado, guardar configuración y cerrar sesión.
- Revisión de datos antes de enviar una solicitud pública.
- Mantener la distinción entre solicitud recibida y turno confirmado.
- Mensajes de éxito/error y estados de procesamiento sin duplicar acciones.

## Fase 2 — Flujo público de reservas
- Mostrar disponibilidad solo después de elegir servicio y fecha.
- Mantener los horarios de InsForge como fuente de verdad; no ofrecer horarios estáticos.
- Mejorar estados vacíos, errores de conexión y conflictos de disponibilidad.
- Presentar servicio, fecha y hora de forma clara en la revisión final.

## Fase 3 — Agenda administrativa
- Jerarquía más clara para filtros, estados y acciones por turno.
- Diferenciar pendiente, confirmado y cancelado visualmente.
- Agrupar acciones y mejorar la disposición en pantallas pequeñas.
- Aclarar que WhatsApp se abre para revisión y envío manual, no automático.
- Conservar los datos ingresados cuando una operación falla.

## Fase 4 — Configuración y calidad
- Validar apertura/cierre y duración antes de guardar.
- Confirmar cambios que afecten la disponibilidad.
- Uniformar estados de carga, vacío y error.
- Revisar teclado, lector de pantalla, contraste, zoom y ancho móvil.

## Fase 5 — Verificación antes de producción
- Crear una reserva de prueba y comprobar que aparezca en el panel.
- Confirmar, cancelar y reprogramar una reserva de prueba.
- Intentar reservar dos veces el mismo espacio y comprobar que InsForge rechace el conflicto.
- Cambiar temporalmente horario/duración, comprobar disponibilidad y restaurar valores reales.
- Probar sesión vencida, permisos insuficientes, error de red y recarga.
- Confirmar precios, dirección, nombres, fotos y horarios reales antes de publicar.

## Criterio de aceptación
La interfaz no afirma que una operación se completó hasta recibir una respuesta satisfactoria del backend. Las pruebas de código y las pruebas reales de InsForge se registran por separado.

## Estado
- Implementado en esta entrega: confirmaciones administrativas y diálogo de revisión previa a la reserva.
- Pendiente: prueba manual en navegador y validación de los flujos contra el entorno real de InsForge.
