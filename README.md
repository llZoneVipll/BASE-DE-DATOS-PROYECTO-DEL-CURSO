# Sistema de Trazabilidad Agroexportadora, Control de Pequeños Productores y Auditoría de Acopio

Proyecto del curso **Base de Datos I** · UNMSM · Semestre 2026-2
Docente: Chávez Soto, Jorge Luis

Base de datos relacional en **MySQL 8.x** que garantiza la trazabilidad de punta a punta, desde la parcela hasta el contenedor marítimo.

## Equipo y responsabilidades (Entrega Parcial 2)

| Integrante | Responsabilidad | Archivos |
|---|---|---|
| Laurente | Documentación, seguridad y catálogos | `docs/`, `02_seguridad.sql`, `03_catalogos.sql`, `08_pruebas.sql` |
| Bujaico | Objetos de BD: Acopio, Calidad y Embarque | `05_objetos_acopio_embarque.sql`, `pruebas/pruebas_acopio.sql` |
| Pacara | Objetos de BD: Campo y Control Fitosanitario | `04_objetos_campo_fitosanitario.sql`, `pruebas/pruebas_campo.sql` |
| Matias | Modelo Lógico, esquema físico y carga de Acopio y Embarque | `modelos/logico/`, `docs/convenciones.md`, `01_esquema.sql`, `07_carga_acopio_embarque.sql` |
| Castro | Procesos de negocio y carga de Campo | `modelos/procesos-bizagi/`, `06_carga_campo.sql` |

## Cómo ejecutar

Requisitos: MySQL 8.x. Todos los archivos están en UTF-8 y la base usa `utf8mb4`.

Los scripts se ejecutan sobre una instancia limpia, en este orden:

1. `01_esquema.sql`
2. `02_seguridad.sql`
3. `03_catalogos.sql`
4. `04_objetos_campo_fitosanitario.sql`
5. `05_objetos_acopio_embarque.sql`
6. `06_carga_campo.sql`
7. `07_carga_acopio_embarque.sql`
8. `08_pruebas.sql`

Para correrlos todos de una vez, desde la carpeta `scripts/`:

```
# PowerShell
mysql -u root -p --default-character-set=utf8mb4 --local-infile=1 -e "source ejecutar_todo.sql"

# CMD o Linux
mysql -u root -p --default-character-set=utf8mb4 --local-infile=1 < ejecutar_todo.sql
```

Las cargas corren con los triggers activos, de modo que quede comprobado que las reglas de negocio funcionan con los datos de prueba.

**Resultado esperado** (sobre MySQL 8.0 limpio, sin errores):

| Dato cargado | Cantidad |
|---|---|
| Productores / parcelas / lotes | 100 / 200 / 300 |
| Certificaciones / tratamientos / inspecciones | 230 / 500 / 300 |
| Tickets de acopio (con control de calidad y liquidación) | 800 (≈180 t recibidas, ≈158 t netas) |
| Pallets / líneas ticket–pallet / cajas en pallets | 140 / 850 / 13 977 |
| Consolidaciones / contenedores / embarques | 140 / 8 / 4 |

`08_pruebas.sql` ejecuta 40 pruebas de las reglas de negocio (12 de Campo y 28 de Acopio y Embarque). Cada una termina en PASS o FAIL y al final muestra el resumen. Las pruebas usan datos con prefijo `TST-` y los borran al terminar: la base queda tal como la dejaron las cargas.

Los scripts `04` a `08` empiezan con `USE agro_trazabilidad;`, así que también pueden correrse de forma individual (siempre después de `01`).

## Relación con el modelo conceptual (Entrega 1)

| Elemento del diagrama | Tabla |
|---|---|
| Productor (generalización: cooperativa / independiente / proveedor directo) | `productor` + `tipo_asociacion` |
| Parcela · Lote agrícola (entidad débil) | `parcela` · `lote_agricola` |
| Certificación · Tratamiento fitosanitario (fecha de liberación derivada) | `certificacion` · `tratamiento_fitosanitario` |
| Inspección pre-cosecha (número de acta) | `inspeccion_pre_cosecha` |
| Ticket de acopio · Control de calidad | `ticket_acopio` · `control_calidad` (+ `tarifa`, `liquidacion`) |
| Pallet · relación "conforma" (Ticket N:M Pallet) | `pallet` · `ticket_pallet` |
| Consolidación (entidad asociativa Pallet N:M Contenedor) | `consolidacion` |
| Contenedor marítimo · Embarque marítimo (1:N, "se despacha en") | `contenedor_maritimo` (`id_embarque`) · `embarque_maritimo` |

## Convenciones de nomenclatura

Ver [`docs/convenciones.md`](docs/convenciones.md).

## Estructura del repositorio

```
docs/                  Documentos de cada entrega y convenciones
modelos/conceptual/    Modelo de Datos Conceptual (Chen extendido)
modelos/logico/        Modelo de Datos Lógico
modelos/procesos-bizagi/  Modelo de Procesos de Negocio
scripts/               Scripts SQL numerados en orden de ejecución
scripts/pruebas/       Casos de prueba por área
```

## Flujo de trabajo

- `main`: solo lo que ya pasó la integración. `dev`: rama de integración.
- Cada integrante trabaja en su propia rama (`apellido/tema`) y la une a `dev` con un pull request revisado por otro compañero.
- Los cambios al esquema (`01_esquema.sql`) se piden a Matias mediante un issue.
- No se suben contraseñas reales.
