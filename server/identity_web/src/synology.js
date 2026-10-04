// DSM Login Web API Guide (2023-04-19), API discovery and recommended Auth v6.
// File Station API Info.get supplies a NAS-authenticated numeric user ID.
export class IdentityError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const failure = (status, code) => { throw new IdentityError(status, code); };
export async function responseBytes(response, signal, limit = 1048576) {
  const chunks = [];
  let size = 0;
  if (!response.body) failure(502, 'identity_unavailable');
  for await (const chunk of response.body) {
    signal.throwIfAborted();
    size += chunk.length;
    if (size > limit) failure(502, 'identity_unavailable');
    chunks.push(Buffer.from(chunk));
  }
  signal.throwIfAborted();
  return Buffer.concat(chunks);
}
function upstreamError(code, login) {
  if (login) {
    if (code === 400) failure(401, 'invalid_credentials');
    if ([403, 406].includes(code)) failure(401, 'otp_required');
    if (code === 404) failure(401, 'invalid_otp');
    if ([401, 402].includes(code)) failure(403, 'account_denied');
    if (code === 407) failure(429, 'rate_limited');
    if ([408, 409, 410].includes(code)) failure(403, 'password_change_required');
  } else if ([105, 106, 107, 119, 150, 400].includes(code)) {
    failure(401, 'session_invalid');
  }
  failure(502, 'identity_unavailable');
}
export class SynologyClient {
  constructor(config, fetchImpl = fetch) { this.config = config; this.fetch = fetchImpl; this.metadata = null; }
  async request(path, fields, signal, { login = false, get = false } = {}) {
    if (!/^[A-Za-z0-9_/-]+\.cgi$/.test(path) || path.includes('..')) failure(502, 'identity_unavailable');
    const url = new URL(`/webapi/${path}`, this.config.nasOrigin);
    const params = new URLSearchParams(Object.entries(fields).map(([k, v]) => [k, String(v)]));
    if (get) url.search = params.toString();
    try {
      const response = await this.fetch(url, {
        method: get ? 'GET' : 'POST', redirect: 'error', signal,
        headers: { Accept: 'application/json', ...(get ? {} : { 'Content-Type': 'application/x-www-form-urlencoded' }) },
        ...(get ? {} : { body: params.toString() }),
      });
      if (response.status === 429) failure(429, 'rate_limited');
      if (!response.ok) failure(502, 'identity_unavailable');
      const data = JSON.parse((await responseBytes(response, signal)).toString('utf8'));
      if (data?.success !== true) upstreamError(data?.error?.code, login);
      return data.data ?? {};
    } catch (error) {
      if (error instanceof IdentityError) throw error;
      failure(signal.aborted ? 504 : 502, signal.aborted ? 'upstream_timeout' : 'identity_unavailable');
    }
  }
  async discover(signal) {
    if (this.metadata) return this.metadata;
    const data = await this.request('entry.cgi', { api: 'SYNO.API.Info', version: 1, method: 'query',
      query: 'SYNO.API.Auth,SYNO.FileStation.Info' }, signal);
    const auth = data['SYNO.API.Auth'];
    const profile = data['SYNO.FileStation.Info'];
    if (!auth || auth.minVersion > 6 || auth.maxVersion < 6 || !profile || profile.maxVersion < 2) failure(502, 'identity_unavailable');
    for (const item of [auth, profile]) if (!/^[A-Za-z0-9_/-]+\.cgi$/.test(item.path) || item.path.includes('..')) failure(502, 'identity_unavailable');
    this.metadata = { authPath: auth.path, profilePath: profile.path };
    return this.metadata;
  }
  async login(account, password, otp, signal) {
    const metadata = await this.discover(signal);
    const data = await this.request(metadata.authPath, { api: 'SYNO.API.Auth', version: 6, method: 'login',
      session: 'FileStation', format: 'sid', enable_syno_token: 'yes', account, passwd: password,
      ...(otp ? { otp_code: otp } : {}),
    }, signal, { login: true });
    if (typeof data.sid !== 'string' || !data.sid || data.sid.length > 4096 || /[\x00-\x20\x7f]/.test(data.sid)) failure(502, 'identity_unavailable');
    return { sid: data.sid, synoToken: typeof data.synotoken === 'string' ? data.synotoken : null, ...metadata };
  }
  async profile(nas, signal) {
    // Actual NAS requires GET _sid here. Outbound URLs are never logged or
    // exposed to clients. Login credentials are only sent in a POST body.
    const data = await this.request(nas.profilePath, { api: 'SYNO.FileStation.Info', version: 2, method: 'get',
      _sid: nas.sid, ...(nas.synoToken ? { SynoToken: nas.synoToken } : {}),
    }, signal, { get: true });
    if (!Number.isSafeInteger(data.uid) || data.uid < 1) failure(401, 'session_invalid');
    return data.uid;
  }
  async logout(nas, signal) {
    try {
      await this.request(nas.authPath, { api: 'SYNO.API.Auth', version: 6, method: 'logout',
        session: 'FileStation', _sid: nas.sid, ...(nas.synoToken ? { SynoToken: nas.synoToken } : {}),
      }, signal, { get: true });
    } catch (error) { if (error.code !== 'session_invalid') throw error; }
  }
}
