"""Real local Docker smoke test. Uses only an isolated temporary library/fake DSM."""
from pathlib import Path
import argparse
import http.cookiejar
import hashlib
import json
import importlib.util
import os
import subprocess
import socket
import shutil
import tempfile
import time
import urllib.error
import urllib.request
from release_retention import inspect_docker_archive, digest

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--archive', type=Path)
parser.add_argument('--source-overlay', action='store_true',
                    help='Developer check: existing images with current source/config mounted; not a built-image acceptance')
arguments = parser.parse_args()
bundle = arguments.archive or ROOT / 'release/board-game-agent-linux-amd64-images.tar'
bundle = bundle.resolve()
details = inspect_docker_archive(bundle)
source_support = bundle.parent / 'reports' / f'docker-{details["platform"].replace("/", "-")}'
result = {'archive':bundle.name, 'archiveSha256':digest(bundle), 'environment':'Ubuntu WSL x86_64; existing local image cache', 'checks':[], 'seconds':{}}
result['mode']='current source/config mounted over existing images' if arguments.source_overlay else 'imported release images without source mounts'
project = f'bga-bundle-validation-{os.getpid()}'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
with socket.socket() as candidate:
    candidate.bind(('127.0.0.1', 0))
    port = candidate.getsockname()[1]
base = f'http://127.0.0.1:{port}'

def request(path, method='GET', payload=None, headers=None):
    values = {'X-Board-Game-Request':'1', 'Origin':base, **(headers or {})}
    data = None
    if payload is not None:
        data = json.dumps(payload).encode()
        values['Content-Type']='application/json'
    req = urllib.request.Request(base+path, data=data, headers=values, method=method)
    try:
        response = opener.open(req, timeout=10)
    except urllib.error.HTTPError as error:
        response = error
    return response.status, dict(response.headers), response.read()

def check(name, expression):
    assert expression, name
    result['checks'].append(name)
    print('PASS',name,flush=True)

def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, timeout=180, **kwargs)

started = time.perf_counter()
with tempfile.TemporaryDirectory(prefix='bga-bundle-validation-') as temporary:
    stage = Path(temporary)
    t = time.perf_counter()
    deploy = stage / 'release/reports' / source_support.name
    shutil.copytree(source_support, deploy, ignore=shutil.ignore_patterns('.env', 'validation.json'))
    shutil.copyfile(bundle, stage / 'release' / bundle.name)
    result['seconds']['archiveCopySeconds'] = time.perf_counter()-t
    release = json.loads((deploy/'release.json').read_text())
    if arguments.source_overlay:
        spec=importlib.util.spec_from_file_location('docker_release', ROOT/'scripts/build-docker-release.py')
        builder=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        (deploy/'docker-compose.yml').write_text(builder.synology_compose(ROOT, release))
    assert release['artifact']['fileName'] == bundle.name and release['artifact']['sha256'] == result['archiveSha256']
    env = dict(os.environ, COMPOSE_PROJECT_NAME=project)
    for name in ('IMAGE_TAG', 'BGA_IMAGE_PLATFORM', 'LIBRARY_PATH', 'SYNOLOGY_ORIGIN', 'WEB_PUBLIC_ORIGIN'):
        env.pop(name, None)
    # Check the actual delivered YAML first, in a folder without any .env.
    # This models the GUI upload configuration step; it does not contact DSM.
    compose=['docker','compose','-p',project,'-f',str(deploy/'docker-compose.yml')]
    configuration = json.loads(run(compose+['config','--format','json'],env=env,cwd=deploy,capture_output=True).stdout)
    check('delivered YAML resolves without .env or image-tag environment variables',not (deploy/'.env').exists() and '${' not in (deploy/'docker-compose.yml').read_text())
    check('delivered YAML references exactly the two imported images',
          {item['image'] for item in configuration['services'].values()} == {item['reference'] for item in release['images']})
    library = stage/'library'
    comments = stage/'comments'
    comments.mkdir()
    game = library/'assets/games/sample'
    (game/'docs').mkdir(parents=True)
    pdf = b'%PDF-' + bytes(range(256))*4096
    (game/'docs/rules.pdf').write_bytes(pdf)
    (game/'game.json').write_text('{}')
    (game/'manifest.json').write_text(json.dumps({'resources':[{'path':'docs/rules.pdf','enabled':True,'status':'available'}]}))
    (library/'assets/catalog.json').write_text('{"games":[{"slug":"sample","enabled":true}]}')
    # Non-root gateway and nginx workers must be able to traverse the test mount.
    stage.chmod(0o755)
    for directory in library.rglob('*'):
        directory.chmod(0o755 if directory.is_dir() else 0o644)
    # Match the NAS reader identity; world-readable fixtures would hide ACL/UID
    # mistakes. This helper receives ONLY isolated synthetic test directories.
    fixture_image=release['images'][1]['reference']
    def fixture_permissions(restricted):
        code='''import os,pathlib,sys
restricted=sys.argv[1]=='restricted'
for root in (pathlib.Path('/test/library'),pathlib.Path('/test/comments')):
 for path in [root,*root.rglob('*')]:
  if restricted: os.chown(path,1028,100)
  path.chmod((0o700 if path.is_dir() else 0o600) if restricted else (0o777 if path.is_dir() else 0o666))
'''
        run(['docker','run','--rm','--user','0:0','--mount',f'type=bind,source={stage},target=/test',
             fixture_image,'python','-B','-c',code,'restricted' if restricted else 'cleanup'],capture_output=True)
    # Only host-dependent settings are replaced for the isolated runtime test.
    # JSON is valid YAML; image refs and runtime service options stay unchanged.
    web = configuration['services']['board-game-agent']
    web['ports'] = [{'target':8080,'published':str(port),'host_ip':'127.0.0.1','protocol':'tcp'}]
    for service in configuration['services'].values():
        for mount in service.get('volumes',[]):
            if mount.get('target') == '/data/library':
                mount['source'] = str(library)
            elif mount.get('target') == '/data/comments':
                mount['source'] = str(comments)
    configuration['services']['web-account']['environment'].update({
        'SYNOLOGY_ORIGIN':'https://mock-dsm:5443',
        'SYNOLOGY_IDENTITY_ORIGIN':'https://mock-dsm:5443',
        'WEB_PUBLIC_ORIGIN':base, 'WEB_ALLOW_INSECURE_HTTP':'true',
    })
    if arguments.source_overlay:
        web['entrypoint']=['nginx']
        web['command']=['-g','daemon off;']
        web['volumes'].extend([
            {'type':'bind','source':str(ROOT/'packaging/docker/nginx-main.conf'),'target':'/etc/nginx/nginx.conf','read_only':True},
            {'type':'bind','source':str(ROOT/'packaging/docker/nginx.conf'),'target':'/etc/nginx/conf.d/default.conf','read_only':True},
        ])
        configuration['services']['web-account']['volumes'].append({
            'type':'bind','source':str(ROOT/'services/web_account'),'target':'/app','read_only':True})
    (deploy/'docker-compose.yml').write_text(json.dumps(configuration))
    try:
        fixture_permissions(True)
        t=time.perf_counter()
        run(['sh',str(deploy/'deploy.sh'),'../../'+bundle.name],cwd=deploy,env=env)
        result['seconds']['packageDeployScript']=time.perf_counter()-t
        t=time.perf_counter()
        for attempt in range(100):
            try:
                if request('/healthz')[0]==200 and request('/api/account/config')[0]==200:
                    break
            except OSError:
                pass
            time.sleep(.1)
        else:
            raise AssertionError('containers not ready')
        result['seconds']['waitForWebAndGateway']=time.perf_counter()-t
        result['seconds']['fromArchiveToReady']=time.perf_counter()-started
        check('production deploy.sh starts both containers without build/pull',True)
        check('both NAS readers use existing owner UID/GID', all(
            value.get('user') == '1028:100' for value in configuration['services'].values()))
        check('homepage HTML and compiled Flutter JS served',request('/')[0]==200 and request('/main.dart.js')[0]==200)
        check('anonymous published PDF readable',request('/library/assets/games/sample/docs/rules.pdf')[0]==200)
        check('anonymous comments list readable',request('/api/comments/entries')[0]==200)
        check('anonymous comment writes blocked',request('/api/comments/file?path=u1001/d'+'a'*32+'.json','POST',{'content':'{}'})[0]==401)
        check('anonymous personal sync blocked',request('/api/sync/private/entries?path=operations')[0]==401)
        check('internal file alias inaccessible',request('/_library_files/assets/catalog.json')[0]==404)
        check('PDF not bundled into public static assets',request('/assets/assets/games/sample/docs/rules.pdf')[0]==404)
        runtime=run(compose+['ps','-q','board-game-agent'],env=env,capture_output=True).stdout.strip()
        process=subprocess.run(['docker','exec',runtime,'find','/usr/share/nginx/html','-type','f'],capture_output=True,text=True,check=True)
        paths = process.stdout.splitlines()
        check('runtime Web image contains no PDF',not any(p.lower().endswith('.pdf') or ('/games/' in p and '/docs/' in p) for p in paths))
        mounts=json.loads(run(['docker','inspect',runtime],capture_output=True).stdout)[0]['Mounts']
        check('library bind mount is read-only',any(m['Destination']=='/data/library' and m['RW'] is False for m in mounts))
        check('restricted fixture really denies unrelated UID', subprocess.run(
            ['docker','run','--rm','--user','65532:65532','--mount',f'type=bind,source={library},target=/data/library,readonly',
             fixture_image,'python','-B','-c',"from pathlib import Path; Path('/data/library/assets/catalog.json').read_bytes()"],
            capture_output=True,text=True,timeout=10).returncode != 0)
        # Add a local HTTPS DSM test fixture; production images/config stay intact.
        cert=stage/'test-cert.pem'; key=stage/'test-key.pem'
        run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=mock-dsm','-addext','subjectAltName=DNS:mock-dsm'],capture_output=True)
        key.chmod(0o644)
        mock=stage/'mock_dsm.py'
        mock.write_text((ROOT/'scripts/docker-mock-dsm.py').read_text(encoding='utf-8'))
        override=stage/'test-override.json'
        override.write_text(json.dumps({'services':{
            'web-account':{'environment':{'DSM_CA_FILE':'/test/test-cert.pem'},'volumes':[f'{stage}:/test:ro']},
            'mock-dsm':{'image':release['images'][1]['reference'],'pull_policy':'never','command':['python','/test/mock_dsm.py'],'volumes':[f'{stage}:/test:ro']}}}))
        tested=compose+['-f',str(override)]
        run(tested+['up','-d','--no-build','--pull','never'],env=env)
        # The fixture recreates only the gateway; refresh Nginx's startup DNS
        # resolution to its new container IP before exercising authentication.
        run(tested+['restart','board-game-agent'],env=env)
        login = None
        for attempt in range(100):
            try:
                if request('/api/account/session')[0]==200:
                    login=request('/api/account/login','POST',{'account':'test-user','password':'test-only'})
                    if login[0]==200:
                        break
            except OSError:
                pass
            time.sleep(.1)
        else:
            raise AssertionError(('mock DSM login failed',login))
        check('HTTPS DSM login via real Nginx and gateway containers',json.loads(login[2])['user']['displayName']=='test-user')
        check('cookie session restores authenticated identity',json.loads(request('/api/account/session')[2])['user'] is not None)
        sync_headers={'X-BGA-Account-UID':'1001'}
        check('private operations initialize only through authenticated DSM',request('/api/sync/private/entries?path=operations',headers=sync_headers)[0]==200)
        environment=hashlib.sha256(b'synology-direct-v1|https://mock-dsm:5443').hexdigest()
        identity=hashlib.sha256(b'synology-direct-v1|https://mock-dsm:5443|1001').hexdigest()
        scope=hashlib.sha256(f'{environment}|{identity}'.encode()).hexdigest()
        device='d'+'a'*32
        operation={'protocolVersion':1,'datasetId':scope,'deviceId':device,'sequence':1,'logicalClock':1,
            'operationId':device+'_1','entityType':'favorite','entityId':'catan','operation':'upsert',
            'payload':{'gameSlug':'catan','createdAt':'2026-10-18T00:00:00Z'},'parents':[],
            'changedAt':'2026-10-18T00:00:00Z','payloadHash':'sha256:'+hashlib.sha256(
                json.dumps({'gameSlug':'catan','createdAt':'2026-10-18T00:00:00Z'},sort_keys=True,separators=(',',':')).encode()).hexdigest()}
        content=json.dumps(operation)
        private_uri=f'/api/sync/private/file?path=operations/{device}.0000000000000001.json'
        check('native-format private log roundtrip through Nginx and HTTPS DSM',
            request(private_uri,'POST',{'content':content},sync_headers)[0]==200 and
            json.loads(request(private_uri,headers=sync_headers)[2])['content']==content)
        check('private retry is idempotent and conflicting overwrite is rejected',
            request(private_uri,'POST',{'content':content},sync_headers)[0]==200 and
            request(private_uri,'POST',{'content':json.dumps({**operation,'entityId':'splendor'})},sync_headers)[0]==409)
        public_uri=f'/api/sync/public/file?path=u1001/{device}.json'
        snapshot=json.dumps({'version':1,'uid':1001,'device':device,'operations':[operation]})
        check('public favorites snapshot roundtrip without an additional data mount',
            request(public_uri,'POST',{'content':snapshot},sync_headers)[0]==200 and
            json.loads(request(public_uri,headers=sync_headers)[2])['content']==snapshot)
        check('stale browser account binding is rejected',request(private_uri,headers={'X-BGA-Account-UID':'2002'})[0]==401)
        uri='/library/assets/games/sample/docs/rules.pdf'
        code,headers,body=request(uri,headers={'Range':'bytes=100-199'})
        lower={k.lower():v for k,v in headers.items()}
        check('mounted PDF Range 206 returns exact bytes',code==206 and body==pdf[100:200])
        check('mounted PDF ETag 304 revalidation',request(uri,headers={'If-None-Match':lower['etag']})[0]==304)
        check('mounted PDF HEAD length',int(request(uri,'HEAD')[1]['Content-Length'])==len(pdf))
        check('authenticated mounted catalog readable',request('/library/assets/catalog.json')[0]==200)
        check('missing library file returns 404',request('/library/assets/missing.pdf')[0]==404)
        check('logout retains public PDF but revokes account',request('/api/account/logout','POST')[0]==200 and request(uri)[0]==200 and json.loads(request('/api/account/session')[2])['user'] is None)
        check('logout revokes private and public account sync',request(private_uri,headers=sync_headers)[0]==401 and request(public_uri,headers=sync_headers)[0]==401)
        check('full deployment completes without creating or reading .env',not (deploy/'.env').exists())
        result['passed']=True
    finally:
        cleanup=locals().get('tested',compose)
        subprocess.run(cleanup+['down','--remove-orphans'],env=env,text=True,timeout=90)
        fixture_permissions(False)
        result['seconds']['completeVerification']=time.perf_counter()-started
        report_path=ROOT/'build/diagnostics/docker-source-overlay-validation.json' if arguments.source_overlay else source_support/'validation.json'
        report_path.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2),flush=True)
