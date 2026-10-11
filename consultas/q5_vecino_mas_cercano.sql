-- Q5. Para cada paradero GTFS de UN recorrido, la farmacia / hospital / clínica / centro de salud más cercano.
-- Patrón: CROSS JOIN LATERAL + ORDER BY <-> + LIMIT 1 (KNN con el GIST de amenidades).
-- Ruta elegida: se define en la variable :ruta (por defecto la 210; ver README).
\if :{?ruta} \else \set ruta '210' \endif
\echo '== Q5: ruta' :ruta
WITH paraderos_ruta AS (        -- paraderos GTFS que están a <= 15 m de algún trazado canónico de la ruta
  SELECT DISTINCT p.stop_id, p.stop_name, p.geom
  FROM paraderos_gtfs p
  JOIN recorridos r ON r.route_short_name = :'ruta' AND ST_DWithin(p.geom, r.geom, 15))
SELECT p.stop_id, p.stop_name, a.amenity, a.name AS nombre_amenidad, round(a.dist::numeric) AS distancia_m
FROM paraderos_ruta p
CROSS JOIN LATERAL (
  SELECT am.amenity, am.name, am.geom <-> p.geom AS dist
  FROM amenidades am
  WHERE am.amenity IN ('pharmacy', 'hospital', 'clinic', 'doctors')
  ORDER BY am.geom <-> p.geom
  LIMIT 1) a
ORDER BY distancia_m DESC;
