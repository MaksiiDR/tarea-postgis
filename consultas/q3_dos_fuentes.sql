-- Q3. Dos fuentes, un objeto: anti-join en los dos sentidos con ST_DWithin a 50 m (y sensibilidad a 25/100 m).
\echo '== Q3: umbral 50 m'
SELECT
  (SELECT count(*) FROM paraderos_gtfs) AS gtfs_total,
  (SELECT count(*) FROM paraderos_gtfs g WHERE NOT EXISTS (SELECT 1 FROM paraderos_osm o WHERE ST_DWithin(g.geom, o.geom, 50))) AS gtfs_sin_osm_50m,
  (SELECT count(*) FROM paraderos_osm) AS osm_total,
  (SELECT count(*) FROM paraderos_osm o WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs g WHERE ST_DWithin(g.geom, o.geom, 50))) AS osm_sin_gtfs_50m;

\echo
\echo '== Q3: sensibilidad al umbral'
SELECT d AS umbral_m,
  (SELECT count(*) FROM paraderos_gtfs g WHERE NOT EXISTS (SELECT 1 FROM paraderos_osm o WHERE ST_DWithin(g.geom, o.geom, d))) AS gtfs_sin_osm,
  (SELECT count(*) FROM paraderos_osm o WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs g WHERE ST_DWithin(g.geom, o.geom, d))) AS osm_sin_gtfs
FROM (VALUES (25), (50), (100)) v(d);
