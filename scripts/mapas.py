#!/usr/bin/env python3
"""Mapas del informe a partir de la base (requiere ./cargar.sh y ./consultas.sh ya corridos).

    python3 -m venv .venv && .venv/bin/pip install matplotlib && .venv/bin/python scripts/mapas.py

Las geometrías se piden a PostGIS como GeoJSON en SRID 5361 (metros) y se dibujan con ejes en km.
"""
import json
import os
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PatchCollection
from matplotlib.patches import Polygon

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, "mapas")
PIE = ("Fuentes: OpenStreetMap vía Geofabrik (chile-260910, 10-sep-2026) · GTFS DTPM GTFS_20261003 (V168, 03-oct-2026) · "
       "DPA 2023 · SRID 5361")


def consulta(sql):
    """Una fila, una columna de texto JSON, con el psql del contenedor."""
    r = subprocess.run(["docker", "compose", "exec", "-T", "db", "psql", "-U", "postgres", "-d", "postgres", "-tA", "-c", sql],
                       cwd=RAIZ, capture_output=True, text=True, check=True)
    return json.loads(r.stdout.strip())


def fc(sql):
    """sql devuelve columnas (geom, ...otras): FeatureCollection con coordenadas en metros."""
    return consulta(f"""SELECT json_build_object('type','FeatureCollection','features',coalesce(json_agg(
        json_build_object('type','Feature','geometry',ST_AsGeoJSON(q.geom, 0)::json,'properties',to_jsonb(q)-'geom')),'[]'::json))
        FROM ({sql}) q""")["features"]


def anillos(geom):
    t, c = geom["type"], geom["coordinates"]
    polys = c if t == "MultiPolygon" else [c]
    return [p[0] for p in polys]


def poligonos(features, valor=None, cmap=None, norm=None, **kw):
    patches, vals = [], []
    for f in features:
        for a in anillos(f["geometry"]):
            patches.append(Polygon([(x / 1000, y / 1000) for x, y in a], closed=True))
            vals.append(f["properties"].get(valor) if valor else 0)
    pc = PatchCollection(patches, **kw)
    if valor:
        pc.set_array(vals)
        pc.set_cmap(cmap)
        pc.set_norm(norm)
    return pc


def puntos(features):
    return [f["geometry"]["coordinates"][0] / 1000 for f in features], [f["geometry"]["coordinates"][1] / 1000 for f in features]


def preparar(ax, titulo):
    ax.set_aspect("equal")
    ax.set_title(titulo, fontsize=10, loc="left")
    ax.set_xlabel("Este UTM 19S (km)", fontsize=7)
    ax.set_ylabel("Norte UTM 19S (km)", fontsize=7)
    ax.tick_params(labelsize=6)


def cierre(fig, nombre):
    fig.text(0.01, 0.005, PIE, fontsize=6, color="#555")
    fig.savefig(os.path.join(SALIDA, nombre), dpi=170, bbox_inches="tight")
    plt.close(fig)
    print("→", nombre)


comunas = fc("SELECT geom, comuna FROM comunas_zona")

# ---- Mapa 1 (principal, Q6): grilla hexagonal de 500 m --------------------------------------
celdas = fc("SELECT geom, i, j, edificios, recorridos FROM mv_grilla WHERE edificios > 0")
top = fc("""SELECT geom, i, j FROM mv_grilla
            WHERE edificios >= (SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY edificios) FROM mv_grilla WHERE edificios > 0)
            ORDER BY recorridos ASC, edificios DESC LIMIT 10""")
fig, axs = plt.subplots(1, 2, figsize=(12, 5.0))
for ax, col, cmap, etiqueta in ((axs[0], "edificios", "YlOrRd", "Edificios por hexágono (OSM)"),
                                (axs[1], "recorridos", "Blues", "Recorridos distintos que cruzan (GTFS)")):
    vmax = max(c["properties"][col] for c in celdas)
    norm = matplotlib.colors.Normalize(0, vmax)
    ax.add_collection(poligonos(comunas, facecolor="#f2f2f2", edgecolor="#bbb", linewidth=0.3))
    pc = poligonos(celdas, valor=col, cmap=cmap, norm=norm, edgecolor="white", linewidth=0.1)
    ax.add_collection(pc)
    ax.add_collection(poligonos(top, facecolor="none", edgecolor="black", linewidth=1.2))
    xs = [x for f in celdas for a in anillos(f["geometry"]) for x, _ in a]
    ys = [y for f in celdas for a in anillos(f["geometry"]) for _, y in a]
    ax.set_xlim(min(xs) / 1000, max(xs) / 1000)
    ax.set_ylim(min(ys) / 1000, max(ys) / 1000)
    preparar(ax, etiqueta)
    fig.colorbar(pc, ax=ax, shrink=0.7, pad=0.02).set_label(etiqueta.split(" (")[0], fontsize=7)
fig.suptitle("Santiago centro — ciudad construida vs. oferta de transporte, hexágonos de 500 m de lado\n"
             "Contorno negro: las 10 celdas con más edificios (percentil 90) y menos recorridos", fontsize=11, y=0.98)
cierre(fig, "01_grilla_edificios_vs_recorridos.png")

# ---- Mapa 2 (Q1): densidad de paraderos GTFS por comuna -------------------------------------
dens = fc("""SELECT z.geom, z.comuna, count(p.*)/z.area_km2_caja AS dens
             FROM comunas_zona z LEFT JOIN comunas_sub s USING (cut_com)
             LEFT JOIN paraderos_gtfs p ON ST_Intersects(p.geom, s.geom)
             GROUP BY z.cut_com, z.geom, z.comuna, z.area_km2_caja""")
par = fc("SELECT geom FROM paraderos_gtfs")
fig, ax = plt.subplots(figsize=(7.5, 7))
norm = matplotlib.colors.Normalize(0, max(d["properties"]["dens"] for d in dens))
pc = poligonos(dens, valor="dens", cmap="viridis_r", norm=norm, edgecolor="white", linewidth=0.6)
ax.add_collection(pc)
x, y = puntos(par)
ax.scatter(x, y, s=0.6, color="black", alpha=0.45, linewidths=0)
ax.autoscale_view()
ax.set_xlim(min(f for f in [a[0] for d in dens for r in anillos(d["geometry"]) for a in r]) / 1000,
            max(a[0] for d in dens for r in anillos(d["geometry"]) for a in r) / 1000)
ax.set_ylim(min(a[1] for d in dens for r in anillos(d["geometry"]) for a in r) / 1000,
            max(a[1] for d in dens for r in anillos(d["geometry"]) for a in r) / 1000)
preparar(ax, "Densidad de paraderos GTFS por comuna (paraderos/km² dentro de la caja)\nPuntos: paraderos GTFS (03-oct-2026)")
fig.colorbar(pc, ax=ax, shrink=0.7, pad=0.02).set_label("paraderos por km²", fontsize=7)
cierre(fig, "02_densidad_paraderos_comuna.png")

# ---- Mapa 3 (Q2): edificios a más de 500 m de un paradero GTFS ------------------------------
lejos = fc("""SELECT punto AS geom FROM edificios e
              WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs p WHERE ST_DWithin(e.punto, p.geom, 500))""")
fig, ax = plt.subplots(figsize=(7.5, 7))
ax.add_collection(poligonos(comunas, facecolor="#f2f2f2", edgecolor="#999", linewidth=0.4))
x, y = puntos(par)
ax.scatter(x, y, s=0.5, color="#1f77b4", alpha=0.35, linewidths=0, label=f"paraderos GTFS ({len(x):,})".replace(",", "."))
x, y = puntos(lejos)
ax.scatter(x, y, s=1.2, color="#d62728", linewidths=0, label=f"edificios a >500 m de un paradero GTFS ({len(x):,})".replace(",", "."))
ax.autoscale_view()
ax.legend(fontsize=7, loc="lower left", markerscale=4)
preparar(ax, "Edificios (OSM) sin paradero GTFS a 500 m — Santiago centro")
cierre(fig, "03_edificios_lejos_de_paraderos.png")
