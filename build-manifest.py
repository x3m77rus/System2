"""Record the binary, SDK, CA trust snapshot and embedded dependency versions."""
import hashlib
import json
import pathlib
import re
import subprocess
import sys

out, sdk = map(pathlib.Path, sys.argv[1:3])
binary = out / 'system2.ext.so'
ca = out / 'package/addons/sourcemod/data/system2/ca-bundle.crt'
lock = json.loads((out / 'dependencies.lock.json').read_text())
revision = subprocess.run(['git', '-C', str(sdk), 'rev-parse', 'HEAD'],
                          capture_output=True, text=True)
versions = subprocess.check_output(['readelf', '-wN', '--version-info', str(binary)], text=True)
glibc = sorted(set(re.findall(r'GLIBC_(\d+\.\d+(?:\.\d+)?)', versions)),
               key=lambda value: tuple(map(int, value.split('.'))))
dynamic = subprocess.check_output(['readelf', '-wN', '-d', str(binary)], text=True)
manifest = {
    'target': 'linux-x86', 'configuration': sys.argv[3],
    'sourcemod_version': (sdk / 'product.version').read_text().strip(),
    'sourcemod_revision': revision.stdout.strip() if revision.returncode == 0 else None,
    'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
    'ca_bundle_sha256': hashlib.sha256(ca.read_bytes()).hexdigest(),
    'minimum_glibc': glibc[-1] if glibc else None,
    'needed': re.findall(r'Shared library: \[(.*?)\]', dynamic),
    'dependencies': lock['sources'], 'dependency_review_date': lock['reviewed'],
}
(out / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Minimum glibc:', manifest['minimum_glibc'])
print('Dynamic dependencies:', ', '.join(manifest['needed']))
