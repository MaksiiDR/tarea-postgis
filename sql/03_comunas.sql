-- DPA 2023 (comunas_cl, SRID 5361) recortada a la caja de la tarea.
DROP TABLE IF EXISTS caja, comunas_zona, comunas_sub CASCADE;

-- La caja del enunciado (lon/lat) como polígono en 5361. ST_Segmentize antes de transformar, para que los
-- lados sigan la curvatura de la proyección en vez de unirse con una recta entre las esquinas.
-- Parámetros: xmin ymin xmax ymax como variables de psql (:xmin, ...)
CREATE TABLE caja AS
SELECT ST_Transform(ST_Segmentize(ST_MakeEnvelope(:xmin, :ymin, :xmax, :ymax, 4326), 0.005), 5361) AS geom;

-- Comunas que tocan la caja, RECORTADAS a ella: el OSM y el GTFS solo existen dentro de la caja, así que
-- calcular áreas/densidades con la comuna entera (p. ej. Las Condes, La Florida) subestimaría todo.
CREATE TABLE comunas_zona AS
SELECT c.cut_com, c.comuna,
       ST_Area(c.geom) / 1e6 AS area_km2_total,
       ST_Area(ST_Intersection(c.geom, k.geom)) / 1e6 AS area_km2_caja,
       ST_Multi(ST_CollectionExtract(ST_Intersection(c.geom, k.geom), 3)) AS geom
FROM comunas_cl c, caja k
WHERE c.geom && k.geom AND ST_Intersects(c.geom, k.geom);

-- La misma geometría partida en trozos de <= 256 vértices: el índice GIST pasa a filtrar por trozo,
-- y los joins pesados (líneas contra polígonos) dejan de arrastrar un polígono de miles de vértices.
CREATE TABLE comunas_sub AS
SELECT cut_com, comuna, ST_Subdivide(geom, 256) AS geom FROM comunas_zona;

CREATE INDEX idx_caja_geom ON caja USING GIST (geom);
CREATE INDEX idx_comunas_zona_geom ON comunas_zona USING GIST (geom);
CREATE INDEX idx_comunas_sub_geom ON comunas_sub USING GIST (geom);
CREATE INDEX idx_comunas_zona_cut ON comunas_zona (cut_com);
CREATE INDEX idx_comunas_sub_cut ON comunas_sub (cut_com);

INSERT INTO pipeline_log(etapa, detalle, n) VALUES
  ('dpa', 'comunas en la caja', (SELECT count(*) FROM comunas_zona)),
  ('dpa', 'trozos de comunas_sub', (SELECT count(*) FROM comunas_sub)),
  ('dpa', 'vertices comunas_zona', (SELECT sum(ST_NPoints(geom)) FROM comunas_zona)),
  ('dpa', 'vertices comunas_cl (pais) de esas comunas', (SELECT sum(ST_NPoints(c.geom)) FROM comunas_cl c WHERE c.cut_com IN (SELECT cut_com FROM comunas_zona)));

-- Comuna de cada edificio (por su punto interior) una sola vez, para no repetir el join pesado.
UPDATE edificios e SET cut_com = c.cut_com
FROM comunas_sub c WHERE ST_Intersects(e.punto, c.geom);
CREATE INDEX idx_edificios_cut ON edificios (cut_com);
INSERT INTO pipeline_log(etapa, detalle, n) VALUES
  ('dpa', 'edificios sin comuna (fuera de la caja curva)', (SELECT count(*) FROM edificios WHERE cut_com IS NULL));
