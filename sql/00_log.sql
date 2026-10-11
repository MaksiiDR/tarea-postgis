-- Bitácora del pipeline: cada reparación / filtro / decisión cuantificada queda aquí (y en el README).
CREATE TABLE IF NOT EXISTS pipeline_log (
    id serial PRIMARY KEY,
    etapa text NOT NULL,
    detalle text NOT NULL,
    n bigint,
    ts timestamptz DEFAULT now()
);
TRUNCATE pipeline_log;
