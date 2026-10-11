-- Q6. Grilla hexagonal de 500 m: edificios y recorridos DISTINTOS (por ruta, no por shape) que cruzan cada celda.
-- Vista materializada: se calcula una vez; `REFRESH MATERIALIZED VIEW mv_grilla` la actualiza.
-- La grilla se genera sobre la caja de los edificios (no la de comunas_cl, que incluye Isla de Pascua).
DROP MATERIALIZED VIEW IF EXISTS mv_grilla;
CREATE MATERIALIZED VIEW mv_grilla AS
WITH g AS (
  SELECT h.i, h.j, ST_SetSRID(h.geom, 5361) AS geom   -- ST_HexagonGrid devuelve SRID 0: se fija explícitamente
  FROM ST_HexagonGrid(500, (SELECT ST_SetSRID(ST_Extent(punto)::geometry, 5361) FROM edificios)) h)
SELECT g.i, g.j, g.geom,
       (SELECT count(*) FROM edificios e WHERE ST_Intersects(e.punto, g.geom)) AS edificios,
       (SELECT count(DISTINCT r.route_id) FROM recorridos r WHERE ST_Intersects(r.geom, g.geom)) AS recorridos
FROM g;
CREATE INDEX idx_mv_grilla_geom ON mv_grilla USING GIST (geom);
ANALYZE mv_grilla;

\echo '== Q6: celdas con edificios y celdas totales'
SELECT count(*) AS celdas, count(*) FILTER (WHERE edificios > 0) AS con_edificios,
       count(*) FILTER (WHERE edificios > 0 AND recorridos = 0) AS con_edificios_sin_recorridos
FROM mv_grilla;

\echo
\echo '== Q6: top 10 celdas con más edificios y menos recorridos (orden: menos recorridos, luego más edificios)'
SELECT i, j, edificios, recorridos,
       round(ST_X(ST_Transform(ST_Centroid(geom), 4326))::numeric, 4) AS lon,
       round(ST_Y(ST_Transform(ST_Centroid(geom), 4326))::numeric, 4) AS lat
FROM mv_grilla
WHERE edificios >= (SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY edificios) FROM mv_grilla WHERE edificios > 0)
ORDER BY recorridos ASC, edificios DESC
LIMIT 10;
