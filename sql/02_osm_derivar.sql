-- Capas derivadas de OSM, con esquema propio. SRID 5361 (metros) en todas.
DROP TABLE IF EXISTS calles, edificios, paraderos_osm, amenidades CASCADE;

CREATE TABLE calles AS
SELECT id, osm_id, name, highway,
       other_tags -> 'maxspeed' AS maxspeed, other_tags -> 'oneway' AS oneway,
       ST_Length(geom) AS largo_m, geom
FROM osm_lineas WHERE highway IS NOT NULL;

-- edificios: se guardan el polígono y un punto INTERIOR (ST_PointOnSurface, no centroide: el centroide
-- puede caer fuera de un polígono cóncavo). Las consultas de distancia usan el punto; las de área, el polígono.
CREATE TABLE edificios AS
SELECT id, coalesce(osm_id, osm_way_id) AS osm_id, name, building,
       other_tags -> 'building:levels' AS pisos,
       ST_Area(geom) AS area_m2, geom, ST_PointOnSurface(geom) AS punto,
       NULL::varchar(10) AS cut_com
FROM osm_poligonos WHERE building IS NOT NULL AND NOT ST_IsEmpty(geom);

CREATE TABLE paraderos_osm AS
SELECT id, osm_id, name, geom FROM osm_puntos WHERE highway = 'bus_stop';

-- amenity es columna en polígonos pero clave de other_tags en puntos: se unifican y todo queda como punto.
CREATE TABLE amenidades AS
SELECT id, osm_id, name, other_tags -> 'amenity' AS amenity, 'punto'::text AS origen, geom
FROM osm_puntos WHERE other_tags ? 'amenity'
UNION ALL
SELECT id, coalesce(osm_id, osm_way_id), name, amenity, 'poligono', ST_PointOnSurface(geom)
FROM osm_poligonos WHERE amenity IS NOT NULL AND NOT ST_IsEmpty(geom);

CREATE INDEX idx_calles_geom ON calles USING GIST (geom);
CREATE INDEX idx_edificios_geom ON edificios USING GIST (geom);
CREATE INDEX idx_edificios_punto ON edificios USING GIST (punto);
CREATE INDEX idx_paraderos_osm_geom ON paraderos_osm USING GIST (geom);
CREATE INDEX idx_amenidades_geom ON amenidades USING GIST (geom);
CREATE INDEX idx_amenidades_amenity ON amenidades (amenity);
