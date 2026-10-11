-- Reparación de geometrías inválidas de OSM (antes de derivar nada).
-- Se cuentan, se reparan con ST_MakeValid (quedándose solo con la parte polígono) y se registra qué pasó.
INSERT INTO pipeline_log(etapa, detalle, n) VALUES
  ('osm_raw', 'osm_puntos',    (SELECT count(*) FROM osm_puntos)),
  ('osm_raw', 'osm_lineas',    (SELECT count(*) FROM osm_lineas)),
  ('osm_raw', 'osm_poligonos', (SELECT count(*) FROM osm_poligonos)),
  ('osm_invalidos', 'lineas invalidas (no se reparan)',  (SELECT count(*) FROM osm_lineas WHERE NOT ST_IsValid(geom))),
  ('osm_invalidos', 'poligonos invalidos antes de reparar', (SELECT count(*) FROM osm_poligonos WHERE NOT ST_IsValid(geom)));

-- motivos de invalidez (para el informe)
INSERT INTO pipeline_log(etapa, detalle, n)
SELECT 'osm_invalidez_motivo', left(split_part(ST_IsValidReason(geom), '[', 1), 60), count(*)
FROM osm_poligonos WHERE NOT ST_IsValid(geom) GROUP BY 2;

INSERT INTO pipeline_log(etapa, detalle, n)
SELECT 'osm_invalidos', 'area declarada de los invalidos antes (m2)', round(sum(ST_Area(geom)))
FROM osm_poligonos WHERE NOT ST_IsValid(geom);

UPDATE osm_poligonos
SET geom = ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))
WHERE NOT ST_IsValid(geom);

INSERT INTO pipeline_log(etapa, detalle, n) VALUES
  ('osm_invalidos', 'poligonos invalidos despues de reparar', (SELECT count(*) FROM osm_poligonos WHERE NOT ST_IsValid(geom))),
  ('osm_invalidos', 'poligonos vacios despues de reparar (se excluyen)', (SELECT count(*) FROM osm_poligonos WHERE ST_IsEmpty(geom)));
