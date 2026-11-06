"""Exercise the x86 loader and pinned network stack against local test servers."""
import gzip
import http.server
import os
import pathlib
import socket
import socketserver
import ssl
import subprocess
import sys
import tempfile
import threading

binary, sdk, deps, build = map(pathlib.Path, sys.argv[1:5])
source = pathlib.Path(__file__).resolve().parent.parent
test = build / 'system2-smoke'
includes = [sdk / path for path in ('public', 'public/amtl', 'public/amtl/amtl', 'sourcepawn/include')]
includes += [source / path for path in ('.', 'sdk', 'handler', 'threads', 'threads/callbacks', 'legacy/threads', 'natives')]
includes += [deps / 'include']
subprocess.run([os.environ.get('CXX', 'clang++-14'), '-m32', '-std=c++17', '-DPOSIX', '-D_LINUX', '-DLINUX',
                '-static-libstdc++', '-static-libgcc', '-Wl,--exclude-libs,ALL',
                *['-I' + str(path) for path in includes], str(source / 'tests/smoke.cpp'),
                str(source / '3rdparty/crc/crc32.cpp'),
                *[str(deps / 'lib' / ('lib' + name + '.a')) for name in
                  ('curl', 'ssl', 'crypto', 'z', 'idn2', 'unistring')],
                '-ldl', '-pthread', '-o', str(test)], check=True)

class HTTP(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/gzip')
            self.end_headers()
            return
        data = gzip.compress(b'System2 smoke test\n' * 64)
        self.send_response(200)
        self.send_header('Content-Encoding', 'gzip')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        data = self.rfile.read(int(self.headers['Content-Length']))
        self.send_response(200)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass

class FTP(socketserver.StreamRequestHandler):
    def handle(self):
        passive = None
        def reply(message):
            self.wfile.write((message + '\r\n').encode())
        reply('220 System2 test server')
        try:
            for line in self.rfile:
                command = line.decode().strip().split(' ', 1)[0].upper()
                if command == 'USER': reply('331 Password required')
                elif command == 'PASS': reply('230 Logged in')
                elif command == 'PWD': reply('257 "/"')
                elif command == 'SYST': reply('215 UNIX Type: L8')
                elif command in ('TYPE', 'CWD'): reply('200 OK')
                elif command == 'SIZE': reply('213 ' + str(len(b'System2 FTP smoke test\n')))
                elif command in ('EPSV', 'PASV'):
                    passive = socket.socket()
                    passive.settimeout(15)
                    passive.bind(('127.0.0.1', 0))
                    passive.listen(1)
                    port = passive.getsockname()[1]
                    if command == 'EPSV': reply(f'229 Entering Extended Passive Mode (|||{port}|)')
                    else: reply(f'227 Entering Passive Mode (127,0,0,1,{port // 256},{port % 256})')
                elif command == 'RETR':
                    reply('150 Opening data connection')
                    connection, _ = passive.accept()
                    with connection:
                        connection.sendall(b'System2 FTP smoke test\n')
                    reply('226 Transfer complete')
                elif command == 'QUIT':
                    reply('221 Goodbye')
                    break
                else: reply('502 Not implemented')
        finally:
            if passive:
                passive.close()

with tempfile.TemporaryDirectory(prefix='system2-smoke-') as temp:
    temp = pathlib.Path(temp)
    cert, key = temp / 'cert.pem', temp / 'key.pem'
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(key), '-out', str(cert), '-days', '1',
                    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    plain = http.server.ThreadingHTTPServer(('127.0.0.1', 0), HTTP)
    https = http.server.ThreadingHTTPServer(('127.0.0.1', 0), HTTP)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    https.socket = context.wrap_socket(https.socket, server_side=True)
    ftp = socketserver.ThreadingTCPServer(('127.0.0.1', 0), FTP)
    servers = (plain, https, ftp)
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        subprocess.run([str(test), str(binary), f'http://127.0.0.1:{plain.server_port}',
                        f'https://localhost:{https.server_port}/gzip',
                        f'ftp://127.0.0.1:{ftp.server_address[1]}/test.txt', str(cert),
                        f'https://127.0.0.1:{https.server_port}/gzip'], check=True)
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()

# Confirm both archive helpers work and preserve content through a round trip.
for arch in ('x86', 'x64'):
    helper = deps / 'tools' / arch / '7z'
    with tempfile.TemporaryDirectory(prefix='system2-archive-') as temp:
        temp = pathlib.Path(temp)
        (temp / 'input.txt').write_text('System2 archive smoke test\n')
        for args in (['a', '-t7z', 'test.7z', 'input.txt'], ['t', 'test.7z'],
                     ['x', '-oextracted', 'test.7z']):
            subprocess.run([str(helper), *args], cwd=temp, check=True, stdout=subprocess.DEVNULL)
        assert (temp / 'extracted/input.txt').read_bytes() == (temp / 'input.txt').read_bytes()
print('x86 and x64 7-Zip archive round trips passed.')
