import { loadConfig } from './config.js';
import { createIdentityService } from './server.js';

try {
  const [major, minor] = process.versions.node.split('.').map(Number);
  if (major !== 24 || minor < 19) throw new Error('Unsupported Node runtime');
  process.umask(0o077);
  const config = loadConfig();
  const service = createIdentityService(config, { log: record => console.error(JSON.stringify(record)) });
  service.server.listen(config.port, config.host, () => console.log('Identity service ready on loopback'));
  let stopping = false;
  const stop = () => {
    if (stopping) return;
    stopping = true;
    const deadline = setTimeout(() => process.exit(1), 40000);
    deadline.unref();
    service.close().then(() => { clearTimeout(deadline); process.exit(0); }, () => process.exit(1));
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  service.server.on('error', () => { console.error('Identity listener failed'); stop(); });
} catch {
  // Configuration errors must not accidentally print a malformed URL/key.
  console.error('Identity service configuration or private storage is invalid');
  process.exitCode = 1;
}
