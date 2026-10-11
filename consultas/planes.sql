-- EXPLAIN ANALYZE comentados (ver README / informe). Se corren con ./consultas.sh y quedan en resultados/planes.txt
\echo '=== Plan 1 (Q2): anti-join ST_DWithin edificios → paraderos_gtfs'
EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF)
SELECT count(*) FROM edificios e
WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs p WHERE ST_DWithin(e.punto, p.geom, 500));

\echo '=== Plan 1b (Q2): lo mismo con el índice GIST de paraderos_gtfs deshabilitado (enable_indexscan/bitmap off)'
SET enable_indexscan = off; SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF)
SELECT count(*) FROM edificios e
WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs p WHERE ST_DWithin(e.punto, p.geom, 500));
RESET enable_indexscan; RESET enable_bitmapscan;

\echo '=== Plan 2 (Q1): punto-en-polígono paraderos_gtfs ↔ comunas_sub'
EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF)
SELECT count(*) FROM paraderos_gtfs p JOIN comunas_sub c ON ST_Intersects(p.geom, c.geom);

\echo '=== Plan 3 (Q5): KNN LATERAL, un paradero → amenidad de salud más cercana'
EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF)
SELECT p.stop_id, a.dist FROM (SELECT * FROM paraderos_gtfs LIMIT 200) p
CROSS JOIN LATERAL (SELECT am.geom <-> p.geom AS dist FROM amenidades am
                    WHERE am.amenity IN ('pharmacy','hospital','clinic','doctors')
                    ORDER BY am.geom <-> p.geom LIMIT 1) a;

\echo '=== Plan 4 (Q4): líneas contra trozos de comunas_sub'
EXPLAIN (ANALYZE, BUFFERS OFF, COSTS OFF)
SELECT c.comuna, sum(ST_Length(ST_Intersection(r.geom, c.geom)))
FROM recorridos r JOIN comunas_sub c ON ST_Intersects(r.geom, c.geom) WHERE r.canonico GROUP BY c.comuna;
