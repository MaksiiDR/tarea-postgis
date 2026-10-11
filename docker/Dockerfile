# PostgreSQL 16 + PostGIS 3 + herramientas de línea de comandos (ogr2ogr, ogrinfo, unzip).
# Misma base que el Lab 05; se agrega `unzip` para abrir el ZIP del GTFS dentro del contenedor.
FROM postgres:16-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends gdal-bin postgis postgresql-16-postgis-3 unzip \
 && rm -rf /var/lib/apt/lists/* \
 && echo "CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS hstore;" \
      > /docker-entrypoint-initdb.d/10_postgis.sql
