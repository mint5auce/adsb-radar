#!/usr/bin/env python3
"""Generate bundled linework from Natural Earth's public-domain vector data."""
import json
from pathlib import Path
from urllib.request import urlopen

BASE = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/'
DATASETS = {
    'coastlines': 'ne_50m_coastline.geojson',
    'borders': 'ne_110m_admin_0_boundary_lines_land.geojson',
}
result = {}
for kind, name in DATASETS.items():
    with urlopen(BASE + name, timeout=30) as response:
        source = json.load(response)
    lines = []
    for feature in source['features']:
        geometry = feature['geometry']
        parts = [geometry['coordinates']] if geometry['type'] == 'LineString' else geometry['coordinates']
        lines.extend([[[round(lon, 5), round(lat, 5)] for lon, lat, *_ in part] for part in parts])
    result[kind] = lines
output = Path(__file__).resolve().parents[1] / 'Sources' / 'Phosphor' / 'Resources' / 'Geography.json'
output.write_text(json.dumps(result, separators=(',', ':')) + '\n')
print(f'Generated {output.name}: {output.stat().st_size:,} bytes')
