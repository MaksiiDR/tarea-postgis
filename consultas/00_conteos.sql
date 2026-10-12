\pset footer off
\echo '== Tablas del esquema propio: filas, SRID, tipo de geometría'
SELECT t AS tabla, n AS filas, srid, tipo FROM (
  SELECT 'calles' t, count(*) n, max(ST_SRID(geom)) srid, max(GeometryType(geom)) tipo FROM calles
  UNION ALL SELECT 'edificios (geom)', count(*), max(ST_SRID(geom)), max(GeometryType(geom)) FROM edificios
  UNION ALL SELECT 'edificios (punto)', count(*), max(ST_SRID(punto)), max(GeometryType(punto)) FROM edificios
  UNION ALL SELECT 'paraderos_osm', count(*), max(ST_SRID(geom)), max(GeometryType(geom)) FROM paraderos_osm
  UNION ALL SELECT 'amenidades', count(*), max(ST_SRID(geom)), max(GeometryType(geom)) FROM amenidades
  UNION ALL SELECT 'paraderos_gtfs', count(*), max(ST_SRID(geom)), max(GeometryType(geom)) FROM paraderos_gtfs
  UNION ALL SELECT 'recorridos', count(*), max(ST_SRID(geom)), max(GeometryType(geom)) FROM recorridos
  UNION ALL SELECT 'caja', count(*), max(ST_SRID(geom)), max(GeometryType(geom)) FROM caja
  UNION ALL SELECT 'comunas_zona', count(*), max(ST_SRID(geom)), max(GeometryType(geom)) FROM comunas_zona
  UNION ALL SELECT 'comunas_sub', count(*), max(ST_SRID(geom)), max(GeometryType(geom)) FROM comunas_sub
  UNION ALL SELECT 'comunas_cl (pais)', count(*), max(ST_SRID(geom)), max(GeometryType(geom)) FROM comunas_cl
) x;

\echo
\echo '== Índices de cada tabla y su tamaño'
SELECT tablename AS tabla, indexname AS indice,
       CASE WHEN indexdef LIKE '%gist%' THEN 'GIST' WHEN indexdef LIKE '%UNIQUE%' THEN 'btree unico' ELSE 'btree' END AS tipo,
       pg_size_pretty(pg_relation_size(quote_ident(indexname)::regclass)) AS tamano
FROM pg_indexes
WHERE schemaname = 'public' AND tablename IN ('calles','edificios','paraderos_osm','amenidades','paraderos_gtfs',
                                               'recorridos','comunas_zona','comunas_sub','caja')
ORDER BY 1, 2;

\echo
\echo '== Tamaño de las tablas (datos + índices)'
SELECT relname AS tabla, pg_size_pretty(pg_total_relation_size(oid)) AS total
FROM pg_class WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace
ORDER BY pg_total_relation_size(oid) DESC LIMIT 15;
