-- GTFS crudo: todo como texto (los CSV se cargan tal cual con COPY, un solo viaje por tabla, no INSERT por fila).
-- Los archivos ya fueron descomprimidos por cargar.sh en /datos/gtfs/.
DROP TABLE IF EXISTS gtfs_stops, gtfs_routes, gtfs_trips, gtfs_shapes, gtfs_stop_times, gtfs_calendar, gtfs_frequencies CASCADE;

CREATE TABLE gtfs_stops (stop_id text, stop_code text, stop_name text, stop_lat text, stop_lon text, stop_url text,
                         wheelchair_boarding text, location_type text, parent_station text, level_id text);
CREATE TABLE gtfs_routes (route_id text, agency_id text, route_short_name text, route_long_name text, route_desc text,
                          route_type text, route_url text, route_color text, route_text_color text);
CREATE TABLE gtfs_trips (route_id text, service_id text, trip_id text, trip_headsign text, direction_id text, shape_id text,
                         trip_short_name text, wheelchair_accessible text, bikes_allowed text);
CREATE TABLE gtfs_shapes (shape_id text, shape_pt_lat text, shape_pt_lon text, shape_pt_sequence text);
CREATE TABLE gtfs_stop_times (trip_id text, arrival_time text, departure_time text, stop_id text, stop_sequence text,
                              pickup_type text, drop_off_type text, timepoint text);
CREATE TABLE gtfs_calendar (service_id text, monday text, tuesday text, wednesday text, thursday text, friday text,
                            saturday text, sunday text, start_date text, end_date text);
CREATE TABLE gtfs_frequencies (trip_id text, start_time text, end_time text, headway_secs text, exact_times text);

\copy gtfs_stops FROM '/datos/gtfs/stops.txt' WITH (FORMAT csv, HEADER true)
\copy gtfs_routes FROM '/datos/gtfs/routes.txt' WITH (FORMAT csv, HEADER true)
\copy gtfs_trips FROM '/datos/gtfs/trips.txt' WITH (FORMAT csv, HEADER true)
\copy gtfs_shapes FROM '/datos/gtfs/shapes.txt' WITH (FORMAT csv, HEADER true)
\copy gtfs_stop_times FROM '/datos/gtfs/stop_times.txt' WITH (FORMAT csv, HEADER true)
\copy gtfs_calendar FROM '/datos/gtfs/calendar.txt' WITH (FORMAT csv, HEADER true)
\copy gtfs_frequencies FROM '/datos/gtfs/frequencies.txt' WITH (FORMAT csv, HEADER true)

INSERT INTO pipeline_log(etapa, detalle, n)
SELECT 'gtfs_raw', t, n FROM (
  SELECT 'stops' t, count(*) n FROM gtfs_stops UNION ALL SELECT 'routes', count(*) FROM gtfs_routes
  UNION ALL SELECT 'trips', count(*) FROM gtfs_trips UNION ALL SELECT 'shapes (puntos)', count(*) FROM gtfs_shapes
  UNION ALL SELECT 'stop_times', count(*) FROM gtfs_stop_times UNION ALL SELECT 'frequencies', count(*) FROM gtfs_frequencies) x;

-- Índices de apoyo para las agregaciones de 05_gtfs.sql
CREATE INDEX ON gtfs_trips (trip_id);
CREATE INDEX ON gtfs_trips (shape_id);
CREATE INDEX ON gtfs_stop_times (stop_id);
CREATE INDEX ON gtfs_stop_times (trip_id);
CREATE INDEX ON gtfs_frequencies (trip_id);
