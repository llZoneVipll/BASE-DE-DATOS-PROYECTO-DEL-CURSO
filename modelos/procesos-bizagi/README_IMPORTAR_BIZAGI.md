# Procesos de negocio — Castro

## Archivos incluidos

Se incluyen cuatro diagramas BPMN 2.0 importables en Bizagi Modeler y sus imágenes PNG:

1. Gestión de productores, parcelas y certificaciones.
2. Control fitosanitario, inspección y liberación.
3. Acopio, pesaje, descarte y liquidación.
4. Empaque, trazabilidad y embarque.

## Cómo obtener el .bpm nativo de Bizagi

Bizagi usa `.bpm` como formato nativo, pero ese archivo lo genera Bizagi Modeler al guardar.
Los `.bpmn` incluidos cumplen BPMN 2.0 y están pensados para importarse:

1. Abrir Bizagi Modeler.
2. **Exportar/Importar → Importar → BPMN** y seleccionar cada `.bpmn`.
3. Revisar el layout, guardar el modelo con **Archivo → Guardar como**. Bizagi creará el `.bpm`.

No se entrega un `.bpm` artificial porque su estructura es propia de Bizagi; el camino correcto es importar BPMN y guardar.

## Criterios de modelado usados

- Pools/líneas de responsabilidad separadas por actor o área.
- Eventos de inicio y fin.
- Actividades como tareas.
- Decisiones como gateways exclusivos.
- Los procesos siguen las reglas de negocio del proyecto y el orden de trazabilidad:
  parcela/lote → fitosanitario → acopio/calidad → empaque/pallet → contenedor/embarque.

## Nota de integración

Los nombres de datos y reglas se alinean con `01_esquema.sql`.
Si Matias cambia nombres o relaciones del esquema, primero actualizar el SQL y después ajustar los textos de estos procesos.
