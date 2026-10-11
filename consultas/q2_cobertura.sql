-- Q2. % de edificios a más de 500 m de cualquier paradero, por comuna: con GTFS y con OSM.
-- Patrón: anti-join con NOT EXISTS + ST_DWithin. Se mide desde el punto interior del edificio.
-- ST_DWithin usa el GIST del paradero (lado interno del nested loop): para cada edificio busca en la
-- caja ampliada 500 m. Con ST_Distance(...) > 500 no habría índice: sería un producto cruzado.
\echo '== Q2: cobertura a 500 m (edificios SIN paradero a <= 500 m)'
SELECT z.comuna, count(*) AS edificios,
       round(100.0 * count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs p WHERE ST_DWithin(e.punto, p.geom, 500))) / count(*), 1) AS pct_lejos_gtfs,
       round(100.0 * count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM paraderos_osm   p WHERE ST_DWithin(e.punto, p.geom, 500))) / count(*), 1) AS pct_lejos_osm
FROM edificios e JOIN comunas_zona z USING (cut_com)
GROUP BY z.comuna
HAVING count(*) >= 100
ORDER BY pct_lejos_gtfs DESC;

\echo
\echo '== Q2 (total de la caja)'
SELECT count(*) AS edificios,
       round(100.0 * count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs p WHERE ST_DWithin(e.punto, p.geom, 500))) / count(*), 2) AS pct_lejos_gtfs,
       round(100.0 * count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM paraderos_osm   p WHERE ST_DWithin(e.punto, p.geom, 500))) / count(*), 2) AS pct_lejos_osm
FROM edificios e;
