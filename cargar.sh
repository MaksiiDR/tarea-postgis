#!/usr/bin/env bash
# Carga de punta a punta: fuentes en ./datos → PostGIS (todo en SRID 5361), con índices y ANALYZE.
#   uso:  docker compose up -d --wait && ./cargar.sh        (idempotente: se puede repetir)
set -euo pipefail
cd "$(dirname "$0")"
source fuentes.env
read -r XMIN YMIN XMAX YMAX <<< "$BBOX"

DC="docker compose"
PSQL="$DC exec -T db psql -q -v ON_ERROR_STOP=1 -U postgres -d postgres"
PSQLV="$PSQL -v xmin=$XMIN -v ymin=$YMIN -v xmax=$XMAX -v ymax=$YMAX"
PG="PG:host=localhost dbname=postgres user=postgres password=pmd2026"
T0=$(date +%s)
paso() { printf '\n\033[1m[%4ss] %s\033[0m\n' "$(( $(date +%s) - T0 ))" "$*"; }

# ---- 0. Fuentes: se buscan por patrón en ./datos (no hay rutas que editar) --------------------------
elegir() { ls -1 datos/$1 2>/dev/null | sort | tail -1 | xargs -r basename; }
PBF=$(elegir "$PBF_GLOB"); GTFS=$(elegir "$GTFS_GLOB"); COMUNAS=$(elegir "$COMUNAS_SQL")
for par in "OSM (.osm.pbf):$PBF" "GTFS (.zip):$GTFS" "DPA (comunas_cl.sql):$COMUNAS"; do
  [[ -n "${par#*:}" ]] || { echo "⛔ Falta la fuente ${par%%:*} en ./datos — ver README, sección «Datos»." >&2; exit 1; }
done
echo "Fuentes: $PBF · $GTFS · $COMUNAS"

paso "Levantando PostGIS"
$DC up -d --wait

# ---- 1. OSM: recorte de la caja a GeoPackage (SRID 5361) ---------------------------------------------
GPKG="/datos/osm_${ZONA}.gpkg"
if $DC exec -T db test -s "$GPKG"; then
  paso "OSM: $GPKG ya existe, se reutiliza (borrarlo para rehacer el recorte)"
else
  paso "OSM: recortando la caja de $PBF (lee Chile completo; varios minutos)"
  $DC exec -T db ogr2ogr -f GPKG "$GPKG.tmp" "/datos/$PBF" points lines multipolygons \
      -spat "$XMIN" "$YMIN" "$XMAX" "$YMAX" -t_srs EPSG:5361 --config OSM_MAX_TMPFILE_SIZE 4000
  $DC exec -T db mv "$GPKG.tmp" "$GPKG"
fi

paso "OSM: GeoPackage → tablas crudas osm_puntos / osm_lineas / osm_poligonos (índice GIST incluido)"
$PSQL -c "CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS hstore;"
for par in points:osm_puntos lines:osm_lineas multipolygons:osm_poligonos; do
  $DC exec -T db ogr2ogr -f PostgreSQL "$PG" "$GPKG" "${par%%:*}" -nln "${par##*:}" -overwrite \
      -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST -lco COLUMN_TYPES=other_tags=hstore -lco FID=id
done

# ---- 2. DPA ------------------------------------------------------------------------------------------
paso "DPA: comunas_cl"
if [[ "$($PSQL -tAc "SELECT to_regclass('public.comunas_cl') IS NOT NULL")" == "t" ]]; then
  echo "   ya cargada"
else
  $PSQL -f "/datos/$COMUNAS"
fi

# ---- 3. GTFS: descomprimir dentro del contenedor -----------------------------------------------------
paso "GTFS: descomprimiendo $GTFS"
$DC exec -T db sh -c "rm -rf /datos/gtfs && mkdir -p /datos/gtfs && unzip -o -q /datos/$GTFS -d /datos/gtfs"

# ---- 4. Transformaciones (sql/NN_*.sql, en orden) ----------------------------------------------------
for f in sql/0*.sql; do
  paso "SQL: $f"
  $PSQLV -f "/$f"
done

paso "Listo. Resumen:"
$PSQL -c "SELECT etapa, detalle, n FROM pipeline_log ORDER BY id" | tee resultados/00_pipeline_log.txt
$PSQL -f /consultas/00_conteos.sql | tee resultados/00_conteos.txt
