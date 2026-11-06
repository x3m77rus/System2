"""Download and verify the locked HTTPS archives before the build extracts them."""
import hashlib
import json
import pathlib
import sys
import urllib.request

lock = json.loads(pathlib.Path(sys.argv[1]).read_text())
destination = pathlib.Path(sys.argv[2])
destination.mkdir(parents=True, exist_ok=True)
for name, source in lock['sources'].items():
    archive = destination / source['url'].rsplit('/', 1)[1]
    print('Downloading ' + name + ' ' + source['version'], flush=True)
    with urllib.request.urlopen(source['url'], timeout=180) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != source['sha256']:
        raise SystemExit('SHA-256 verification failed: ' + name)
    archive.write_bytes(data)
