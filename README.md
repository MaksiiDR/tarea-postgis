# Tarea 1 — PostGIS de punta a punta: Santiago centro

Procesamiento Masivo de Datos (ELE051-B / EIN102B) · USM 2026-2 · Paralelo 701.
Integrantes: Maximiliano Del Rio · Patricio Aylwin.
Repositorio: https://github.com/MaksiiDR/tarea-postgis
Pipeline: **OpenStreetMap + GTFS (DTPM) + DPA 2023 → PostGIS (SRID 5361) → 7 consultas → mapas e informe.**

Pregunta que ordena todo: *¿cómo se relaciona la ciudad construida (OSM) con la red de transporte público (GTFS)?*

## Reproducir desde cero

Requisitos: Docker con `docker compose`, red para el primer `build` (apt dentro de la imagen) y varios GB libres (fuentes ≈ 0,6 GB + volumen de la base).

1. **Dejar las 3 fuentes en `./datos/`** (no se versionan; ver «Datos»):
   - un `*.osm.pbf` (usado: `chile-260910.osm.pbf`),
   - un `GTFS_AAAAMMDD.zip` (usado: `GTFS_20261003.zip`),
   - `comunas_cl.sql` (Lab 03).
2. `docker compose up -d --wait`  (construye y levanta PostGIS 16 + GDAL; puerto host 5435)
3. `./cargar.sh`  — recorta OSM, carga, transforma, indexa y hace `ANALYZE` (≈ 90 s tras la primera vez; el recorte del PBF son ~25 s).
4. `./consultas.sh`  — corre las 7 preguntas + planes y deja todo en `resultados/` (≈ 15 s).
5. *(opcional, mapas)* `python3 -m venv .venv && .venv/bin/pip install matplotlib && .venv/bin/python scripts/mapas.py`

`cargar.sh` busca las fuentes **por patrón** en `./datos` (no hay rutas que editar) y es idempotente. Probado en limpio: `docker compose down -v`, borrar el GPKG intermedio, y repetir los pasos 2–4 → todo OK.

Limpieza: `docker compose down` apaga; `docker compose down -v` además borra el volumen `tarea-pgdata`.

## Datos (no versionados: ver `.gitignore`)

| Fuente | Versión / fecha usada | Cómo se obtuvo |
|---|---|---|
| OpenStreetMap, extracto de Chile (Geofabrik, ODbL) | **`chile-260910.osm.pbf`**, extracto del **10-sep-2026** (347 MB) | https://download.geofabrik.de/south-america/chile.html — es el PBF que ya estaba descargado del Lab 05, **no** un `chile-latest` bajado hoy; la zona se recorta con la misma caja del enunciado |
| GTFS vigente DTPM (Red Movilidad) | **`GTFS_20261003.zip`**, descargado el **11-oct-2026**; `feed_version V168.20261003`, vigencia 03-oct → 31-dic-2026 (12,8 MB) | https://www.dtpm.cl/index.php/noticias/gtfs-vigente (el vigente al día de descarga) |
| División Político Administrativa 2023 | `comunas_cl.sql` del Lab 03 (345 comunas, SRID 5361) | Lab 03 |

**Único `.gpkg` versionado:** `resultados/resultados_santiago-centro.gpkg` (6,6 MB, capas de resultado para QGIS: grilla, paraderos, comunas y recorridos canónicos). Lo pide el enunciado (los mapas exportados deben estar en el repositorio); los datos fuente y el GeoPackage intermedio de OSM (`datos/osm_*.gpkg`) siguen excluidos.

Caja `santiago-centro`: lon −70,75 … −70,52 · lat −33,52 … −33,36 (`fuentes.env`). OSM se recorta con `ogr2ogr -spat`; los paraderos GTFS se filtran por la misma caja en lon/lat en la base.

## Qué hace cada etapa

| Archivo | Qué hace |
|---|---|
| `docker-compose.yml`, `docker/Dockerfile` | PostGIS + `ogr2ogr` + `unzip`; volumen con nombre `tarea-pgdata`; montajes `./datos`, `./sql`, `./consultas`, `./resultados` |
| `cargar.sh` | recorte PBF→GeoPackage (SRID 5361) → `ogr2ogr` a tablas crudas → `comunas_cl` → descomprime GTFS → `sql/0*.sql` en orden |
| `sql/01_osm_reparar.sql` | cuenta y repara geometrías inválidas de OSM |
| `sql/02_osm_derivar.sql` | `calles`, `edificios`, `paraderos_osm`, `amenidades` |
| `sql/03_comunas.sql` | caja, `comunas_zona` (recortada a la caja), `comunas_sub` (`ST_Subdivide`), comuna de cada edificio |
| `sql/04_gtfs_raw.sql` | CSV del GTFS → tablas crudas con `\copy` |
| `sql/05_gtfs.sql` | `paraderos_gtfs`, `recorridos` (LineStrings), oferta de viajes |
| `consultas/` | `q1`…`q7`, `q4_tiempos`, `planes`, `00_conteos` |
| `resultados/` | salida de cada consulta, planes `EXPLAIN ANALYZE`, uso de índices, `00_pipeline_log.txt`, GeoPackage para QGIS |
| `scripts/mapas.py`, `mapas/` | mapas PNG del informe |
| `informe/` | informe PDF (≤ 6 pág.) y su fuente |

## Tablas, conteos e índices

Conteos de esta carga (`resultados/00_conteos.txt`; la bitácora completa está en `resultados/00_pipeline_log.txt`). Todas las geometrías están en **SRID 5361**; todas las tablas con `ANALYZE` al final (`sql/06_final.sql`).

| Tabla | Filas | Geometría | Índices |
|---|---:|---|---|
| `osm_puntos` / `osm_lineas` / `osm_poligonos` (crudas) | 254.538 / 169.578 / 146.619 | Point / LineString / MultiPolygon | GIST (los crea `ogr2ogr`) |
| `calles` | 100.686 | LineString | GIST `geom` |
| `edificios` | 118.700 | MultiPolygon + `punto` Point | GIST `geom`, GIST `punto`, btree `cut_com` |
| `paraderos_osm` (`highway='bus_stop'`) | 6.567 | Point | GIST |
| `amenidades` (puntos + polígonos→punto) | 20.770 | Point | GIST `geom`, btree `amenity` |
| `paraderos_gtfs` | 6.569 | Point | GIST, PK `stop_id` |
| `recorridos` (1 LineString por `shape_id`) | 690 (586 canónicos, 338 rutas) | LineString | GIST, PK `shape_id`, btree `route_short_name` |
| `comunas_zona` (comunas de la caja, recortadas) | 30 | MultiPolygon | GIST, btree `cut_com` |
| `comunas_sub` (`ST_Subdivide` 256 vértices) | 34 | Polygon | GIST, btree `cut_com` |
| `comunas_cl` (país, Lab 03) | 345 | MultiPolygon | GIST (del `.sql`) |
| `gtfs_*` crudas (`stops`, `routes`, `trips`, `shapes`, `stop_times`, `calendar`, `frequencies`) | 18.455 · 428 · 26.159 · 456.573 · **1.098.529** · · 14.542 | — | btree de apoyo en `trip_id`, `stop_id`, `shape_id` |
| `viajes_por_trip` | 26.159 | — | btree `trip_id` |
| `mv_grilla` (vista materializada, Q6) | 682 celdas | Polygon | GIST |

`stop_times.txt` (1,1 M filas) se cargó con **`\copy` (un solo COPY por archivo)**; no hay `INSERT` fila a fila.

## Decisiones tomadas

- **SRID 5361** (SIRGAS-Chile / UTM 19S): metros para `ST_DWithin`, `ST_Length`, `ST_Area` y la grilla. OSM se reproyecta al recortar (`-t_srs`); los puntos del GTFS (4326) se transforman con `ST_Transform`.
- **Punto interior, no centroide ni polígono** para edificios en las consultas de distancia: `ST_PointOnSurface` siempre cae dentro del edificio (el centroide puede caer fuera de un polígono cóncavo) y las anti-joins `ST_DWithin` contra un punto usan el índice mucho mejor que contra polígonos. El polígono se conserva para áreas. Efecto: un edificio muy grande se mide desde un solo punto.
- **Reparación de OSM**: 368 polígonos inválidos de 146.619 (0,25 %, 8,9 km² de «área declarada» antes). Motivos: *Too few points* 232, *Invalid number of points in LinearRing* 77, *Self-intersection* 58, *Ring Self-intersection* 1. Se reparan con `ST_MakeValid` + `ST_CollectionExtract(…,3)` + `ST_Multi`: quedan **0 inválidos**, pero **309 quedan vacíos** (eran anillos de <4 puntos: no hay qué reparar) y se excluyen al derivar. Había además **1 línea inválida** (no se tocó; no afecta a ninguna consulta).
- **Alcance = solo buses.** El GTFS trae también Metro (7 líneas, `route_type` 1) y EFE (`route_type` 0). Sus andenes no son comparables con un `bus_stop` de OSM (inflarían Q3) y el enunciado habla de paraderos, así que `paraderos_gtfs` y `recorridos` contienen solo servicios de bus (`route_type = 3`): 419 rutas de bus incluidas, 9 de Metro/tren excluidas; **243 stops de la caja (andenes de Metro/Tren o sin servicio) quedan fuera**. También se excluyen estaciones, accesos y nodos (`location_type` 1–4): 5.989 stops. *Consecuencia: la «cobertura» de Q2 y Q6 ignora el Metro.*
- **Shapes → recorridos.** Una `LineString` por `shape_id` con `ST_MakeLine(punto ORDER BY shape_pt_sequence)` (la secuencia se castea a entero: como texto, «10» < «2»). Cada shape pertenece a una sola ruta en este feed (0 shapes con 2 rutas) y no hubo shapes con <2 puntos. 981 shapes en el feed, 690 de bus tocan la caja.
- **Ida/vuelta/variantes.** Cada sentido y cada variante es su propio `shape_id`. Para no contar la misma calle varias veces en «km de red» (Q4) se marca `canonico` el shape con más viajes por (ruta, sentido) (empate: el más largo): 586 canónicos. Las preguntas que cuentan rutas usan todos los shapes y cuentan `DISTINCT route_id`. Efecto en Q4: contar todas las variantes infla los km un 17 % (Santiago) a un 45 % (Peñalolén).
- **Viajes por paradero.** Los buses de la DTPM se publican con `frequencies.txt`: un trip es un patrón que se repite cada *headway*. Contar solo `stop_times` subestima la oferta; `viajes_por_trip` expande cada trip como `floor((fin − inicio)/headway)` y se suma por paradero en día laboral (servicios con `wednesday = 1`).
- **Comunas recortadas a la caja** (`comunas_zona`): OSM y GTFS solo existen dentro de la caja, así que la densidad por km² con la comuna entera (Las Condes, La Florida…) estaría subestimada. `ST_Subdivide` (256 vértices) → `comunas_sub` para los joins. Comunas con muy poca superficie en la caja (San Ramón 0,2 km², Lo Barnechea 2,8 km²) dan cifras poco fiables.
- **Grilla.** `ST_HexagonGrid(500, …)`: **500 m es el lado** del hexágono (área 649.519 m²), no el ancho. Se genera sobre la caja de los edificios; `ST_HexagonGrid` devuelve SRID 0 y se fija a 5361.
- **Distancias en línea recta**, no por la red peatonal.

## Índices: cuáles se usan y cuál es inútil

`resultados/indices_uso.txt` (`pg_stat_user_indexes.idx_scan`, tras cargar y correr todas las consultas):

- Muy usados: `idx_paraderos_gtfs_geom` (383.070 lecturas) y `idx_paraderos_osm_geom` (263.676) — el lado interno de las anti-joins `ST_DWithin`.
- **`idx_edificios_geom`: 0 lecturas** (9,8 MB, el más pesado sin uso). Ninguna consulta usa el polígono del edificio con un predicado espacial: todo va por `punto` (716 lecturas). Hallazgo, no error: es el índice «inútil» de este diseño; se dejó porque el polígono sirve para mapas/áreas futuras, pero en producción se borraría.
- `idx_calles_geom` (4,2 MB): 0 lecturas — `calles` se derivó (el enunciado lo pide) pero ninguna de las 7 preguntas la consulta.
- `comunas_sub`/`comunas_zona` GIST: 0 lecturas; son tablas de 34 y 30 filas y el planificador prefiere un `Seq Scan` del lado exterior (el índice que importa es el del lado grande: `recorridos`, `paraderos_gtfs`). `mv_grilla` GIST y las PK tampoco se leen.

## Qué no funcionó / problemas encontrados

- **Docker estaba apagado** (servicio inactivo) al empezar; hubo que arrancarlo con `sudo systemctl start docker`.
- El primer `docker compose` avisa *«configured to build using Bake, but buildx isn't installed»*: es solo un warning, el `build` funciona.
- Q6, primer intento: `ST_Intersects: Operation on mixed SRID geometries` — `ST_HexagonGrid` devuelve SRID 0. Se arregló con `ST_SetSRID(…, 5361)`.
- `consultas.sh`: la cadena de conexión `PG:…` quedó partida en palabras por el shell y `ogr2ogr` intentó conectarse como `root`; se corrigió citándola.
- Primera versión de `paraderos_gtfs` mezclaba **andenes de Metro** con paraderos de bus (6.812 en vez de 6.569): Q3 mostraba 453 paraderos GTFS «sin bus_stop en OSM» a 50 m; con solo buses son 381 (72 menos, atribuibles a esos andenes). Detectado al ver que el feed trae `route_type = 1`; ahora el análisis es solo de buses (ver Decisiones).
- Q7 (propia): una primera versión sumaba viajes tras un `JOIN` doble y los duplicaba; se rehízo con `CROSS JOIN LATERAL` independientes.
- `ST_Subdivide` **no ayuda** si la comuna ya viene recortada a la caja (440 ms ≈ 426 ms); sí ayuda con comunas enteras (1.208 → 547 ms, ×2,2; los tiempos varían ~±15 % entre corridas). Ver `resultados/q4_tiempos.txt`.

## Limitaciones («honestidad con el dato»)

- Los `bus_stop` de OSM son los que alguien dibujó (81 de 6.567 sin nombre); el GTFS es lo que el operador declara y vale **a su fecha** (V168, 03-oct-2026). Que ambos coincidan a 50 m no prueba que el paradero exista en terreno.
- Metro y trenes están fuera (ver arriba); las celdas «mal servidas» del Q6 pueden tener estación de Metro cerca.
- OSM puede estar incompleto en la periferia (menos edificios dibujados ⇒ cobertura aparentemente mejor).
- La oferta de viajes expande frecuencias en el día laboral de referencia; no considera feriados (`calendar_dates.txt`) ni cambios operacionales.
