-- GTFS → capas con geometría (SRID 5361). Parámetros psql: :xmin :ymin :xmax :ymax (lon/lat de la caja).
DROP TABLE IF EXISTS paraderos_gtfs, recorridos, viajes_por_trip CASCADE;

-- ---- Viajes por trip -------------------------------------------------------------------------
-- Un trip con filas en frequencies.txt es un PATRÓN que se repite cada `headway_secs` entre start_time y
-- end_time (así publica la DTPM los buses): cuenta como floor((fin - inicio)/headway) viajes, no como 1.
-- Sin frecuencias, 1. Día laboral = servicios que operan los miércoles según calendar.txt.
CREATE TABLE viajes_por_trip AS
WITH f AS (
  SELECT trip_id,
         sum(floor((  split_part(end_time,   ':', 1)::int * 3600 + split_part(end_time,   ':', 2)::int * 60
                    - split_part(start_time, ':', 1)::int * 3600 - split_part(start_time, ':', 2)::int * 60)
                   / nullif(headway_secs::numeric, 0)))::int AS n
  FROM gtfs_frequencies GROUP BY trip_id)
SELECT t.trip_id, t.route_id, r.route_type, t.service_id, coalesce(f.n, 1) AS viajes,
       (c.wednesday = '1') AS laboral
FROM gtfs_trips t
JOIN gtfs_routes r USING (route_id)
LEFT JOIN f USING (trip_id)
LEFT JOIN gtfs_calendar c ON c.service_id = t.service_id;
CREATE INDEX ON viajes_por_trip (trip_id);

-- ---- Alcance: solo BUSES (route_type 3, Red Movilidad) ------------------------------------------------------
-- El feed también trae Metro (route_type 1, 7 líneas) y trenes EFE (route_type 0). Sus andenes (location_type 0)
-- no son comparables con un `bus_stop` de OSM (Q3) ni con la pregunta de "paraderos", así que TODO el análisis
-- es de buses: paraderos y recorridos con servicio de bus. Lo que se deja fuera queda contado en pipeline_log.

-- ---- Paraderos -------------------------------------------------------------------------------
-- location_type '' o '0' = parada/andén donde se sube; se excluyen estaciones (1), accesos (2), nodos (3) y
-- áreas de embarque (4), que no son paraderos. Solo los de la caja (en lon/lat, como el recorte de OSM).
CREATE TABLE paraderos_gtfs AS
WITH oferta AS (        -- viajes por paradero en día laboral (stop_times × viajes del trip) y rutas distintas, solo buses
  SELECT st.stop_id, coalesce(sum(v.viajes) FILTER (WHERE v.laboral), 0)::int AS viajes_laboral,
         count(DISTINCT v.route_id) AS n_rutas
  FROM gtfs_stop_times st JOIN viajes_por_trip v USING (trip_id)
  WHERE v.route_type = '3'
  GROUP BY st.stop_id)
SELECT s.stop_id, s.stop_code, s.stop_name, o.viajes_laboral, o.n_rutas,
       ST_Transform(ST_SetSRID(ST_MakePoint(nullif(s.stop_lon,'')::float8, nullif(s.stop_lat,'')::float8), 4326), 5361) AS geom
FROM gtfs_stops s JOIN oferta o USING (stop_id)
WHERE coalesce(nullif(s.location_type, ''), '0') = '0'
  AND nullif(s.stop_lon,'')::float8 BETWEEN :xmin AND :xmax
  AND nullif(s.stop_lat,'')::float8 BETWEEN :ymin AND :ymax;
ALTER TABLE paraderos_gtfs ADD PRIMARY KEY (stop_id);

INSERT INTO pipeline_log(etapa, detalle, n) VALUES
  ('gtfs', 'stops totales en stops.txt', (SELECT count(*) FROM gtfs_stops)),
  ('gtfs', 'stops excluidos por location_type (estaciones/accesos/nodos)',
      (SELECT count(*) FROM gtfs_stops WHERE coalesce(nullif(location_type, ''), '0') <> '0')),
  ('gtfs', 'paraderos dentro de la caja (paraderos_gtfs)', (SELECT count(*) FROM paraderos_gtfs)),
  ('gtfs', 'stops de la caja (type 0) SIN servicio de bus: andenes Metro/Tren o sin stop_times (excluidos)',
      (SELECT count(*) FROM gtfs_stops s WHERE coalesce(nullif(location_type,''),'0') = '0'
         AND nullif(stop_lon,'')::float8 BETWEEN :xmin AND :xmax AND nullif(stop_lat,'')::float8 BETWEEN :ymin AND :ymax
         AND stop_id NOT IN (SELECT stop_id FROM paraderos_gtfs))),
  ('gtfs', 'rutas del feed por tipo: buses (3)', (SELECT count(*) FROM gtfs_routes WHERE route_type = '3')),
  ('gtfs', 'rutas del feed por tipo: metro (1) y tren (0/2), excluidas', (SELECT count(*) FROM gtfs_routes WHERE route_type <> '3'));

-- ---- Recorridos ------------------------------------------------------------------------------
-- UNA LineString por shape_id: los puntos se ordenan por shape_pt_sequence (como entero: ordenarlos como
-- texto pondría el 10 antes del 2) dentro del ST_MakeLine. Se descartan shapes con < 2 puntos.
-- Se quedan solo los shapes que tocan la caja (el recorrido completo, no recortado: recortar es trabajo de Q4).
CREATE TABLE recorridos AS
WITH puntos AS (
  SELECT shape_id, shape_pt_sequence::int AS seq,
         ST_Transform(ST_SetSRID(ST_MakePoint(shape_pt_lon::float8, shape_pt_lat::float8), 4326), 5361) AS g
  FROM gtfs_shapes),
lineas AS (
  SELECT shape_id, count(*) AS n_puntos, ST_MakeLine(g ORDER BY seq) AS geom
  FROM puntos GROUP BY shape_id HAVING count(*) >= 2),
por_shape AS (            -- shape → ruta (cada shape pertenece a una sola ruta en este feed; se verifica abajo)
  SELECT t.shape_id, min(t.route_id) AS route_id, count(DISTINCT t.route_id) AS n_rutas,
         mode() WITHIN GROUP (ORDER BY t.direction_id) AS direction_id, count(*) AS n_trips
  FROM gtfs_trips t WHERE t.shape_id <> '' GROUP BY t.shape_id)
SELECT l.shape_id, p.route_id, r.route_short_name, r.route_long_name, p.direction_id::int AS direction_id,
       p.n_trips, l.n_puntos, ST_Length(l.geom) AS largo_m, l.geom
FROM lineas l JOIN por_shape p USING (shape_id) JOIN gtfs_routes r ON r.route_id = p.route_id
WHERE r.route_type = '3' AND ST_Intersects(l.geom, (SELECT geom FROM caja));
ALTER TABLE recorridos ADD PRIMARY KEY (shape_id);

-- Variantes: una ruta tiene varios shapes (ida, vuelta, y variantes de horario o trazado). Se marca como
-- `canonico` el shape con más trips por (ruta, sentido) — empate: el más largo — para medir "km de red"
-- sin contar tres veces la misma calle. Las consultas que cuentan rutas distintas usan todos los shapes.
ALTER TABLE recorridos ADD COLUMN canonico boolean DEFAULT false;
UPDATE recorridos r SET canonico = true
FROM (SELECT DISTINCT ON (route_id, direction_id) shape_id
      FROM recorridos ORDER BY route_id, direction_id, n_trips DESC, largo_m DESC) c
WHERE c.shape_id = r.shape_id;

INSERT INTO pipeline_log(etapa, detalle, n) VALUES
  ('gtfs', 'shape_id distintos en shapes.txt', (SELECT count(DISTINCT shape_id) FROM gtfs_shapes)),
  ('gtfs', 'shapes con <2 puntos (descartados)', (SELECT count(*) FROM (SELECT shape_id FROM gtfs_shapes GROUP BY 1 HAVING count(*) < 2) z)),
  ('gtfs', 'shapes asociados a mas de una ruta', (SELECT count(*) FROM (SELECT shape_id FROM gtfs_trips WHERE shape_id <> '' GROUP BY 1 HAVING count(DISTINCT route_id) > 1) z)),
  ('gtfs', 'recorridos (shapes que tocan la caja)', (SELECT count(*) FROM recorridos)),
  ('gtfs', 'recorridos canonicos (ruta x sentido)', (SELECT count(*) FROM recorridos WHERE canonico)),
  ('gtfs', 'rutas distintas en la caja', (SELECT count(DISTINCT route_id) FROM recorridos)),
  ('gtfs', 'recorridos no LineString', (SELECT count(*) FROM recorridos WHERE GeometryType(geom) <> 'LINESTRING'));

CREATE INDEX idx_paraderos_gtfs_geom ON paraderos_gtfs USING GIST (geom);
CREATE INDEX idx_recorridos_geom ON recorridos USING GIST (geom);
CREATE INDEX idx_recorridos_ruta ON recorridos (route_short_name);
