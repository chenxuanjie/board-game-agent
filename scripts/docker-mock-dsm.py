"""Isolated HTTPS FileStation fixture for verify-docker-release.py. Never a NAS."""
from email.parser import BytesParser
from email.policy import default
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs
import json
import ssl

objects = {'/home': (True, None), '/friend/apps/board_game_agent/public/v1': (True, None)}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def answer(self, data, error=None):
        raw = json.dumps({'success': False, 'error': {'code': error}} if error else {'success': True, 'data': data}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        raw = self.rfile.read(int(self.headers['Content-Length']))
        upload = None
        if self.headers['Content-Type'].startswith('multipart/'):
            message = BytesParser(policy=default).parsebytes(b'Content-Type: ' + self.headers['Content-Type'].encode() + b'\r\n\r\n' + raw)
            fields = {}
            for part in message.iter_parts():
                name = part.get_param('name', header='content-disposition')
                if name == 'file':
                    upload = part.get_filename(), part.get_payload(decode=True)
                else:
                    fields[name] = part.get_payload(decode=True).decode()
        else:
            fields = {k: v[0] for k, v in parse_qs(raw.decode()).items()}
        api, method = fields['api'], fields['method']
        if api != 'SYNO.API.Info' and method != 'login':
            if self.headers.get('Cookie') != 'id=fake-private-sid' or self.headers.get('X-SYNO-TOKEN') != 'fake-token':
                return self.answer({}, 119)
        if api == 'SYNO.API.Info':
            data = {name: {'path': 'entry.cgi', 'minVersion': 1, 'maxVersion': 7} for name in fields['query'].split(',')}
        elif method == 'login':
            data = {'sid': 'fake-private-sid', 'synotoken': 'fake-token'}
        elif api == 'SYNO.FileStation.Info':
            data = {'uid': 1001}
        elif method == 'list':
            path = fields['folder_path']
            if path not in objects:
                return self.answer({}, 408)
            entries = [self.entry(name) for name in sorted(objects) if name.rsplit('/', 1)[0] == path]
            offset, limit = int(fields['offset']), int(fields['limit'])
            data = {'files': entries[offset:offset + limit], 'total': len(entries)}
        elif method == 'getinfo':
            path = json.loads(fields['path'])[0]
            data = {'files': [self.entry(path) if path in objects else {'path': path, 'code': 408}]}
        elif method == 'create':
            if fields.get('force_parent') != 'false':
                return self.answer({}, 407)
            parent, name = json.loads(fields['folder_path'])[0], json.loads(fields['name'])[0]
            if parent not in objects:
                return self.answer({}, 408)
            objects[parent + '/' + name] = True, None
            data = {}
        elif method == 'upload':
            if fields.get('create_parents') != 'false' or fields['path'] not in objects:
                return self.answer({}, 407)
            path = fields['path'] + '/' + upload[0]
            if fields['overwrite'] == 'true' or path not in objects:
                objects[path] = False, upload[1]
            data = {}
        elif method == 'download':
            path = json.loads(fields['path'])[0]
            if path not in objects or objects[path][0]:
                return self.answer({}, 408)
            content = objects[path][1]
            self.send_response(200)
            self.send_header('Content-Disposition', 'attachment; filename=record.json')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
            return
        else:
            data = {}
        self.answer(data)

    @staticmethod
    def entry(path):
        return {'path': path, 'name': path.rsplit('/', 1)[-1], 'isdir': objects[path][0], 'additional': {'owner': {'uid': 1001}}}


if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 5443), Handler)
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain('/test/test-cert.pem', '/test/test-key.pem')
    server.socket = tls.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
