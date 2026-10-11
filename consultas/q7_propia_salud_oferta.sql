-- Q7 (propia). ¿Qué oferta de transporte público tienen los hospitales y clínicas de Santiago centro?
-- Cruza OSM (amenidades de salud) con GTFS (viajes por paradero en día laboral, ya expandidos por
-- frequencies.txt): para cada establecimiento, paraderos y rutas distintas a <= 300 m y viajes por día.
-- No es una variante de Q2 (cobertura de edificios por distancia): acá el objeto es la amenidad y la medida
-- es OFERTA (viajes y rutas), no presencia de un paradero.
\echo '== Q7: resumen por tipo de establecimiento (radio 300 m)'
WITH s AS (
  SELECT a.id, a.amenity, a.name, p.paraderos, p.viajes_laboral, r.rutas
  FROM amenidades a
  CROSS JOIN LATERAL (SELECT count(*) AS paraderos, coalesce(sum(viajes_laboral), 0) AS viajes_laboral
                      FROM paraderos_gtfs g WHERE ST_DWithin(a.geom, g.geom, 300)) p
  CROSS JOIN LATERAL (SELECT count(DISTINCT route_id) AS rutas
                      FROM recorridos x WHERE ST_DWithin(a.geom, x.geom, 300)) r
  WHERE a.amenity IN ('hospital', 'clinic'))
SELECT amenity, count(*) AS establecimientos,
       count(*) FILTER (WHERE paraderos = 0) AS sin_paradero_300m,
       round(avg(rutas), 1) AS rutas_promedio,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY viajes_laboral) AS mediana_viajes_dia
FROM s GROUP BY amenity;

\echo
\echo '== Q7: los 10 con menos viajes por día'
WITH s AS (
  SELECT a.id, a.amenity, a.name, p.paraderos, p.viajes_laboral
  FROM amenidades a
  CROSS JOIN LATERAL (SELECT count(*) AS paraderos, coalesce(sum(viajes_laboral), 0) AS viajes_laboral
                      FROM paraderos_gtfs g WHERE ST_DWithin(a.geom, g.geom, 300)) p
  WHERE a.amenity IN ('hospital', 'clinic'))
SELECT amenity, coalesce(name, '(sin nombre)') AS nombre, paraderos, viajes_laboral
FROM s ORDER BY viajes_laboral ASC, name LIMIT 10;
