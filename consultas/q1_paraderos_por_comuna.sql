-- Q1. Paraderos GTFS por comuna y densidad (paraderos por km² DE LA COMUNA DENTRO DE LA CAJA).
-- Patrón: join espacial punto-en-polígono. comunas_sub (trozos) + GIST → ST_Intersects sobre el punto.
-- (Un paradero justo sobre el borde entre dos trozos de la MISMA comuna se contaría dos veces: DISTINCT.)
\echo '== Q1: paraderos GTFS por comuna'
WITH p AS (
  SELECT DISTINCT p.stop_id, c.cut_com
  FROM paraderos_gtfs p JOIN comunas_sub c ON ST_Intersects(p.geom, c.geom))
SELECT z.comuna, count(*) AS paraderos_gtfs,
       round(z.area_km2_caja::numeric, 1) AS km2_en_caja,
       round((count(*) / z.area_km2_caja)::numeric, 1) AS paraderos_por_km2
FROM p JOIN comunas_zona z USING (cut_com)
GROUP BY z.comuna, z.area_km2_caja
ORDER BY paraderos_por_km2 DESC;
