#!/usr/bin/env bash
# Corre las consultas de la Parte C y guarda cada salida en resultados/. Requiere haber corrido ./cargar.sh.
set -euo pipefail
cd "$(dirname "$0")"
PSQL="docker compose exec -T db psql -q -v ON_ERROR_STOP=1 -U postgres -d postgres"
for q in q1_paraderos_por_comuna q2_cobertura q3_dos_fuentes q4_km_por_comuna q4_tiempos q5_vecino_mas_cercano \
         q6_grilla q7_propia_salud_oferta planes; do
  echo ">> $q"
  $PSQL -f "/consultas/$q.sql" > "resultados/$q.txt"
done
# Índices que se usan de verdad (hallazgo de higiene, Parte D)
$PSQL -c "SELECT relname AS tabla, indexrelname AS indice, idx_scan AS lecturas,
                 pg_size_pretty(pg_relation_size(indexrelid)) AS tamano
          FROM pg_stat_user_indexes
          WHERE relname IN ('calles','edificios','paraderos_osm','amenidades','paraderos_gtfs','recorridos',
                            'comunas_zona','comunas_sub','mv_grilla')
          ORDER BY idx_scan, 1, 2" > resultados/indices_uso.txt
# Salida para QGIS: GeoPackage con las capas de resultado (va versionado: es chico)
rm -f resultados/resultados_santiago-centro.gpkg
PG="PG:host=localhost dbname=postgres user=postgres password=pmd2026"
exporta() { docker compose exec -T db ogr2ogr -f GPKG /resultados/resultados_santiago-centro.gpkg "$PG" "$@"; }
exporta -nln grilla -sql "SELECT i, j, edificios, recorridos, geom FROM mv_grilla WHERE edificios > 0"
exporta -update -nln paraderos_gtfs -sql "SELECT stop_id, stop_name, viajes_laboral, geom FROM paraderos_gtfs"
exporta -update -nln comunas -sql "SELECT cut_com, comuna, area_km2_caja, geom FROM comunas_zona"
exporta -update -nln recorridos_canonicos -sql "SELECT shape_id, route_short_name, direction_id, geom FROM recorridos WHERE canonico"
echo "Listo: resultados/"
