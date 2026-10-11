-- Q4 (efecto de ST_Subdivide): la misma consulta contra comunas_cl (país, polígonos enteros), comunas_zona
-- (recortada a la caja) y comunas_sub (trozos). Se imprime el Execution Time de cada EXPLAIN ANALYZE.
\echo '== A. comunas_zona (1 polígono por comuna, recortada)'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT c.comuna, sum(ST_Length(ST_Intersection(r.geom, c.geom)))
FROM recorridos r JOIN comunas_zona c ON ST_Intersects(r.geom, c.geom) WHERE r.canonico GROUP BY c.comuna;

\echo '== B. comunas_sub (trozos de <=256 vértices)'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT c.comuna, sum(ST_Length(ST_Intersection(r.geom, c.geom)))
FROM recorridos r JOIN comunas_sub c ON ST_Intersects(r.geom, c.geom) WHERE r.canonico GROUP BY c.comuna;

\echo '== C. comunas_cl (país: polígono entero de cada comuna, sin recortar a la caja)'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT c.comuna, sum(ST_Length(ST_Intersection(r.geom, c.geom)))
FROM recorridos r JOIN comunas_cl c ON ST_Intersects(r.geom, c.geom) WHERE r.canonico GROUP BY c.comuna;

\echo '== D. comunas enteras (como C) pero subdivididas en trozos de <=256 vértices'
CREATE TEMP TABLE comunas_cl_sub AS
SELECT cut_com, comuna, ST_Subdivide(geom, 256) AS geom FROM comunas_cl
WHERE cut_com IN (SELECT cut_com FROM comunas_zona);
CREATE INDEX ON comunas_cl_sub USING GIST (geom);
ANALYZE comunas_cl_sub;
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT c.comuna, sum(ST_Length(ST_Intersection(r.geom, c.geom)))
FROM recorridos r JOIN comunas_cl_sub c ON ST_Intersects(r.geom, c.geom) WHERE r.canonico GROUP BY c.comuna;
