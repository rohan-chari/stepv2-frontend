import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {createInterface} from 'node:readline';

const MONTHS = new Map(['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'].map((name, i) => [name, i]));

function structuredLine(line) {
  if (!line.trimStart().startsWith('{')) return null;
  try {
    const value = JSON.parse(line);
    return value && typeof value === 'object' && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
}

function nginxTime(line) {
  const match = /\[(\d{2})\/([A-Z][a-z]{2})\/(\d{4}):(\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})\]/.exec(line);
  if (match && MONTHS.has(match[2])) {
    const utc = Date.UTC(Number(match[3]), MONTHS.get(match[2]), Number(match[1]), Number(match[4]), Number(match[5]), Number(match[6]));
    const offset = (Number(match[8]) * 60 + Number(match[9])) * 60_000 * (match[7] === '+' ? 1 : -1);
    return utc - offset;
  }
  const structured = structuredLine(line);
  const candidate = structured?.time_iso8601 ?? structured?.timestamp ?? structured?.time ?? structured?.['@timestamp'];
  if (typeof candidate === 'string') {
    const parsed = Date.parse(candidate);
    if (Number.isFinite(parsed)) return parsed;
  }
  const iso = /\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})\b/.exec(line)?.[0];
  if (!iso) return null;
  const parsed = Date.parse(iso);
  return Number.isFinite(parsed) ? parsed : null;
}

function requestFromLine(line) {
  const match = /"([A-Z]+)\s+([^\s"]+)\s+HTTP\/[0-9.]+"/.exec(line);
  let method = match?.[1];
  let target = match?.[2];
  if (!match) {
    const structured = structuredLine(line);
    const request = structured?.request;
    const requestMatch = typeof request === 'string' ? /^([A-Z]+)\s+([^\s]+)(?:\s+HTTP\/[0-9.]+)?$/.exec(request) : null;
    method = requestMatch?.[1] ?? structured?.request_method ?? structured?.method;
    target = requestMatch?.[2] ?? structured?.request_uri ?? structured?.uri ?? structured?.path;
  }
  if (typeof method !== 'string' || typeof target !== 'string' || !/^[A-Z]+$/.test(method)) return null;
  try {
    const parsed = new URL(target, 'http://capacity.invalid');
    return {method, pathname: parsed.pathname};
  } catch {
    return null;
  }
}

function genericTemplate(pathname, routeLiteralSegments) {
  const literals = routeLiteralSegments instanceof Set ? routeLiteralSegments : new Set(routeLiteralSegments || []);
  const segments = pathname.split('/').filter(Boolean).map(segment => {
    try { return decodeURIComponent(segment); } catch { return segment; }
  });
  if (!segments.length) return '/';
  return `/${segments.map(segment => literals.has(segment) ? segment : ':param').join('/')}`;
}

function compileRegistry(registry) {
  return registry.routes.map(route => ({...route, matcher: new RegExp(route.pathRegex)}));
}

export function loadRegistry(path) {
  const registry = JSON.parse(readFileSync(path, 'utf8'));
  if (registry.schemaVersion !== 'stepv2-capacity-route-registry-v1') throw new Error('unsupported route registry');
  return registry;
}

function sshLines(target, remoteCommand, onLine, timeoutMs=30*60*1000) {
  return new Promise((resolve, reject) => {
    const child = spawn('ssh', ['-o', 'BatchMode=yes', target, remoteCommand], {stdio: ['ignore', 'pipe', 'pipe']});
    let stderr = '';
    child.stderr.on('data', chunk => { stderr += chunk; if (stderr.length > 8000) stderr = stderr.slice(-8000); });
    const lines = createInterface({input: child.stdout, crlfDelay: Infinity});
    const watchdog = setTimeout(() => { child.kill('SIGTERM'); setTimeout(()=>child.kill('SIGKILL'),10_000).unref(); reject(new Error('production log read exceeded its absolute watchdog')); }, Math.max(1,timeoutMs));
    lines.on('line', onLine);
    child.on('error', reject);
    child.on('close', code => { clearTimeout(watchdog); code === 0 ? resolve() : reject(new Error(`production log read failed (${code}): ${stderr.trim()}`)); });
  });
}

export async function deriveRollingMix({sshTarget, registryPath, logPaths, routeLiteralSegments = [], endMs = Date.now(),deadlineMs=null}) {
  if(!Number.isFinite(endMs))throw new Error('rolling production interval requires a finite run start');
  const startMs = endMs - 7 * 24 * 60 * 60 * 1000;
  const registry = loadRegistry(registryPath);
  const routes = compileRegistry(registry);
  const counts = new Map(routes.map(route => [route.key, 0]));
  const unknown = new Map();
  const exclusions = {outsideWindow: 0, malformed: 0, bot: 0, healthOrAdmin: 0, externalWrite: 0, nonProductionVhost: 0, nonApiWeb: 0};
  let rawCount = 0;
  let eligibleCount = 0;
  let seenLines = 0;
  let timestampLines = 0;
  let requestLines = 0;
  let structuralProbe = null;
  let sourceMinMs = null;
  let sourceMaxMs = null;
  const clientProfiles = new Map();
  const recordClient=(platform,appVersion,userAgent,features)=>{if(!features)return;const family=/\b(?:Bara(?:-Android)?|Dart)\/[0-9]+(?:\.[0-9]+){0,3}/.exec(userAgent)?.[0];if(!family)return;const key=JSON.stringify([platform,appVersion,family,features]);clientProfiles.set(key,(clientProfiles.get(key)||0)+1);};
  const sourceFiles = [];
  const bot = /(bot|crawler|spider|headless|uptime|healthcheck|monitoring)/i;
  const safePaths=(Array.isArray(logPaths)?logPaths:[]).filter(path=>/^\/var\/log\/nginx\/[A-Za-z0-9_.-]+$/.test(path));
  if(!safePaths.length)throw new Error('production nginx access-log path could not be proven from the active vhost');
  const names=[...new Set(safePaths.map(path=>path.split('/').at(-1)))];
  const predicates=names.map(name=>`-name '${name}*'`).join(' -o ');
  const identityCommand = `find -L /var/log/nginx -maxdepth 1 -type f \\( ${predicates} \\) ! -name '*bots*' -printf '%f\\t%s\\t%T@\\n' | sort`;
  await sshLines(sshTarget, identityCommand, line => {
    const [name, bytes, modifiedEpoch] = line.split('\t');
    if (!name || !Number.isFinite(Number(bytes)) || !Number.isFinite(Number(modifiedEpoch))) return;
    sourceFiles.push({nameHash: createHash('sha256').update(name).digest('hex'), bytes: Number(bytes), modifiedAt: new Date(Number(modifiedEpoch) * 1000).toISOString()});
  },deadlineMs===null?undefined:deadlineMs-Date.now());
  const command = `find -L /var/log/nginx -maxdepth 1 -type f \\( ${predicates} \\) ! -name '*bots*' -print0 | sort -z | xargs -0 -r zcat -f --`;
  const consumeLine = line => {
    seenLines += 1;
    if (structuralProbe === null && line.length) {
      structuralProbe = {
        json: line.trimStart().startsWith('{'),
        bracketTimestamp: /\[\d{2}\/[A-Z][a-z]{2}\/\d{4}:/.test(line),
        isoTimestamp: /\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(line),
        quotedHttpRequest: /"[A-Z]+\s+[^\s"]+\s+HTTP\/[0-9.]+"/.test(line),
        tabFields: line.split('\t').length,
      };
    }
    const timestamp = nginxTime(line);
    if (timestamp === null) { exclusions.malformed += 1; return; }
    timestampLines += 1;
    sourceMinMs = sourceMinMs === null ? timestamp : Math.min(sourceMinMs, timestamp);
    sourceMaxMs = sourceMaxMs === null ? timestamp : Math.max(sourceMaxMs, timestamp);
    if (timestamp < startMs || timestamp >= endMs) { exclusions.outsideWindow += 1; return; }
    rawCount += 1;
    if (line.includes('staging.steptracker-api.org')) { exclusions.nonProductionVhost += 1; return; }
    if (bot.test(line)) { exclusions.bot += 1; return; }
    const ua = /"([^"]*)"\s*$/.exec(line)?.[1] || '';
    const ios = /\bBara\/([0-9]+(?:\.[0-9]+){1,3})\b/i.exec(ua);
    const android = /\b(?:Android|Bara-Android)\b[^\"]*?(?:Bara\/)?([0-9]+(?:\.[0-9]+){1,3})?/i.exec(ua);
    const features=/(?:x-client-features|client[_-]?features)[=: "\t]+([a-z0-9_-]+(?:,[a-z0-9_-]+)+)/i.exec(line)?.[1] || /"(characters,[a-z0-9_,-]*api_payload_compact_v1[a-z0-9_,-]*)"/i.exec(line)?.[1];
    if (ios) recordClient('ios',ios[1],line,features);
    else if (android) recordClient('android',android[1]||'unknown',line,features);
    else {
      const loggedVersion=/(?:x-app-version|app[_-]?version)[=: "\t]+([0-9]+(?:\.[0-9]+){2,3})/i.exec(line)?.[1] || /"([0-9]+(?:\.[0-9]+){2,3})"/.exec(line)?.[1];
      const loggedPlatform=/\b(android|ios)\b/i.exec(line)?.[1]?.toLowerCase() || (line.includes('admin_metrics_v2')?'ios':line.includes('api_payload_compact_v1')?'android':null);
      if(loggedVersion&&loggedPlatform)recordClient(loggedPlatform,loggedVersion,line,features);
    }
    const request = requestFromLine(line);
    if (!request) { exclusions.malformed += 1; return; }
    requestLines += 1;
    if (request.pathname === '/health' || request.pathname.startsWith('/admin')) { exclusions.healthOrAdmin += 1; return; }
    const route = routes.find(candidate => candidate.method === request.method && candidate.matcher.test(request.pathname));
    if (!route) {
      const template=genericTemplate(request.pathname, routeLiteralSegments);
      if(template==='/:param'||template.startsWith('/:param/')){exclusions.nonApiWeb += 1;return;}
      const safe = `${request.method} ${template}`;
      unknown.set(safe, (unknown.get(safe) || 0) + 1);
      return;
    }
    if (route.externalWrite) { exclusions.externalWrite += 1; return; }
    counts.set(route.key, counts.get(route.key) + 1);
    eligibleCount += 1;
  };
  await sshLines(sshTarget, command, consumeLine, deadlineMs===null?undefined:deadlineMs-Date.now());
  let fallbackCommand = null;
  if (seenLines === 0) {
    const fallbackIdentity = "find -L /var/log/nginx -maxdepth 1 -type f -iname '*access*' ! -iname '*staging*' ! -iname '*bots*' -printf '%f\\t%s\\t%T@\\n' | sort";
    await sshLines(sshTarget, fallbackIdentity, line => {
      const [name, bytes, modifiedEpoch] = line.split('\t');
      if (!name || !Number.isFinite(Number(bytes)) || !Number.isFinite(Number(modifiedEpoch))) return;
      sourceFiles.push({nameHash: createHash('sha256').update(name).digest('hex'), bytes: Number(bytes), modifiedAt: new Date(Number(modifiedEpoch) * 1000).toISOString(), discoveredFallback: true});
    }, deadlineMs===null?undefined:deadlineMs-Date.now());
    fallbackCommand = "find -L /var/log/nginx -maxdepth 1 -type f -iname '*access*' ! -iname '*staging*' ! -iname '*bots*' -print0 | sort -z | xargs -0 -r zcat -f --";
    await sshLines(sshTarget, fallbackCommand, consumeLine, deadlineMs===null?undefined:deadlineMs-Date.now());
  }
  let journalCommand = null;
  if (seenLines === 0) {
    const journalStart = Math.floor((startMs - 5 * 60 * 1000) / 1000);
    const journalEnd = Math.ceil(endMs / 1000);
    journalCommand = `journalctl --unit nginx --since '@${journalStart}' --until '@${journalEnd}' --output cat --no-pager`;
    sourceFiles.push({source: 'systemd-nginx-journal', intervalHash: createHash('sha256').update(`${journalStart}:${journalEnd}`).digest('hex')});
    await sshLines(sshTarget, journalCommand, consumeLine, deadlineMs===null?undefined:deadlineMs-Date.now());
  }
  if (rawCount < 1) {
    let nginxDirectoryFiles = 0;
    await sshLines(sshTarget, "find -L /var/log/nginx -maxdepth 1 -type f -printf 'x\\n'", () => { nginxDirectoryFiles += 1; }, deadlineMs===null?undefined:deadlineMs-Date.now());
    throw new Error(`rolling production interval contained no parseable requests (sources=${sourceFiles.length}, nginxDirectoryFiles=${nginxDirectoryFiles}, seen=${seenLines}, timestamps=${timestampLines}, requests=${requestLines}, structure=${JSON.stringify(structuralProbe)})`);
  }
  const tailToleranceMs = 5 * 60 * 1000;
  const windowCoverage = {
    sourceMin: sourceMinMs === null ? null : new Date(sourceMinMs).toISOString(),
    sourceMax: sourceMaxMs === null ? null : new Date(sourceMaxMs).toISOString(),
    startCovered: sourceMinMs !== null && sourceMinMs <= startMs,
    endCovered: sourceMaxMs !== null && sourceMaxMs >= endMs - tailToleranceMs,
    tailToleranceSeconds: tailToleranceMs / 1000,
  };
  if (!windowCoverage.startCovered || !windowCoverage.endCovered) throw new Error(`nginx sources do not cover the exact rolling week (source ${windowCoverage.sourceMin || 'unknown'} through ${windowCoverage.sourceMax || 'unknown'}; required ${new Date(startMs).toISOString()} through ${new Date(endMs).toISOString()} with at most 5 minutes ingestion lag)`);
  const comparableDenominator = eligibleCount + [...unknown.values()].reduce((sum, value) => sum + value, 0);
  const coveragePercent = comparableDenominator ? eligibleCount / comparableDenominator * 100 : 0;
  const weights = Object.fromEntries([...counts.entries()].filter(([, value]) => value > 0).map(([key, value]) => [key, value / eligibleCount]));
  const unknownRoutes = [...unknown.entries()].sort((a, b) => b[1] - a[1]).map(([template, count]) => ({template, count}));
  const observedClientProfiles = [...clientProfiles.entries()].sort((a,b)=>b[1]-a[1]).map(([key,count])=>{const [platform,appVersion,userAgent,clientFeatures]=JSON.parse(key);return {platform,appVersion,userAgent,clientFeatures,count};});
  const sourceCommandHash = createHash('sha256').update(journalCommand || fallbackCommand || command).digest('hex');
  return {
    schemaVersion: 'stepv2-production-mix-v1',
    registryVersion: registry.version,
    interval: {start: new Date(startMs).toISOString(), end: new Date(endMs).toISOString(), halfOpen: true},
    rawCount, eligibleCount, comparableDenominator, coveragePercent, weights, exclusions, unknownRoutes, sourceCommandHash, sourceFiles, windowCoverage, observedClientProfiles,
  };
}
