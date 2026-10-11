-- Q4. Km de recorrido por comuna, recortando cada trazado en el límite comunal (ST_Intersection).
-- Patrón: líneas contra polígonos. Se usan los recorridos CANÓNICOS (un shape por ruta y sentido), para no
-- contar varias veces la misma calle; se reporta también el total con todas las variantes.
-- Se compara contra comunas_zona (1 polígono por comuna) y comunas_sub (trozos): ver q4_tiempos.sql.
\echo '== Q4: km de recorrido por comuna (comunas_sub)'
SELECT c.comuna,
       round((sum(ST_Length(ST_Intersection(r.geom, c.geom))) FILTER (WHERE r.canonico) / 1000)::numeric, 1) AS km_canonicos,
       round((sum(ST_Length(ST_Intersection(r.geom, c.geom))) / 1000)::numeric, 1) AS km_todas_variantes,
       count(DISTINCT r.route_id) AS rutas
FROM recorridos r JOIN comunas_sub c ON ST_Intersects(r.geom, c.geom)
GROUP BY c.comuna
ORDER BY km_canonicos DESC NULLS LAST;
