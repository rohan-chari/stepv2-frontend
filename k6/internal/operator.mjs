#!/usr/bin/env node

import {createHash, randomBytes} from 'node:crypto';
import {spawn, spawnSync} from 'node:child_process';
import {connect, isIP} from 'node:net';
import {networkInterfaces} from 'node:os';
import {
  chmodSync, createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync,
  lstatSync, readdirSync, renameSync, rmSync, statfsSync, statSync, writeFileSync,
} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {createInterface} from 'node:readline';

import {
  acquireLock, activeRun, atomicJson, clearActive, newState, phaseComplete,
  phaseFailed, phaseStart, readJson, saveState, setActive, stateRoot,
} from './state.mjs';
import {deriveRollingMix} from './traffic.mjs';
import {logicalSpan, validateEightHourEnvelope} from './self-validate.mjs';

const HERE = dirname(new URL(import.meta.url).pathname);
const K6_ROOT = resolve(HERE, '..');
const REPO_ROOT = resolve(K6_ROOT, '..');
const REGISTRY_PATH = join(HERE, 'route-registry.v1.json');
const LOAD_PATH = join(HERE, 'operator-load.js');
const WATCHDOG_PATH = join(HERE,'child-watchdog.mjs');
const REQUIREMENTS_PATH = join(REPO_ROOT, 'docs/k6-operator-workflow-requirements.md');
const PROD_ENV_PATH = '/var/www/step-tracker-backend/.env';
const BACKEND_DIR = '/opt/stepv2-capacity/backend';
const EFFECTIVE_ENV_PATH = `${BACKEND_DIR}/.env`;
const HELPER_PATH = 'scripts/perf/capacity-runtime.js';
const SERVER_PATH = 'scripts/perf/capacity-server.js';
const APP_SPEC = Object.freeze({cpus: 2, memoryGiB: 2, diskGiB: 60});
const DB_SPEC = Object.freeze({cpus: 1, memoryGiB: 2, diskGiB: 30, maxConnections: 47});
const WORKLOAD = Object.freeze({users: 10_000, minRaces: 1, maxRaces: 5, startRps: 50, stepRps: 10, warmupSeconds: 30, measureSeconds: 180, deadlineSeconds: 28_800, coverageMinimum: 95});
const EXPERIMENT_PROFILE_NAME='app4-workers3-pool12-fixed150';
const TOPOLOGY_REVISION = 'lima-loopback-ssh-tunnel-v3';
let cancellationRequested = false;
let activeLoadProcess = null;
let activePhaseDeadlineMs = null;
let cancelConfirmation = null;
for (const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>{
  cancellationRequested = true;
  if(cancelConfirmation)cancelConfirmation();
  if(activeLoadProcess && activeLoadProcess.exitCode===null){
    activeLoadProcess.kill('SIGINT');
    process.stderr.write(`\n${signal}: stopping new traffic; bounded drain/report/cleanup will follow\n`);
  }else{
    process.stderr.write(`\n${signal}: cancellation recorded; bounded terminalization will begin at the phase boundary\n`);
  }
});

function die(message, code = 2) {
  process.stderr.write(`${message}\n`);
  process.exitCode = code;
}
function absoluteDeadline(state){return Date.parse(state.plan?.deadlineAt||state.createdAt)+ (state.plan?.deadlineAt?0:WORKLOAD.deadlineSeconds*1000);}
async function withinRunDeadline(state,phase,action){
  const deadline=absoluteDeadline(state);if(Date.now()>=deadline){const error=new Error(`absolute eight-hour run deadline expired before ${phase}`);error.code='CAPACITY_DEADLINE';throw error;}
  const previous=activePhaseDeadlineMs;activePhaseDeadlineMs=deadline;
  try{return await action();}catch(error){if(Date.now()>=deadline)error.code='CAPACITY_DEADLINE';throw error;}finally{activePhaseDeadlineMs=previous;}
}

function commandExists(command) {
  return spawnSync('sh', ['-c', 'command -v "$1" >/dev/null 2>&1', 'sh', command]).status === 0;
}

function run(command, args, options = {}) {
  const requestedTimeout=options.timeoutMs||30*60*1000;const deadlineRemaining=activePhaseDeadlineMs===null?Infinity:activePhaseDeadlineMs-Date.now();const deadlineBound=deadlineRemaining<=requestedTimeout;const timeoutMs=Math.max(1,Math.min(requestedTimeout,deadlineRemaining));
  const envelope={command,args,cwd:options.cwd,env:options.env||process.env,inputBase64:options.input===undefined?null:Buffer.from(options.input).toString('base64'),timeoutMs,maxBuffer:options.maxBuffer||32*1024*1024};
  const wrapped=spawnSync(process.execPath,[WATCHDOG_PATH],{input:JSON.stringify(envelope),encoding:'utf8',maxBuffer:(options.maxBuffer||32*1024*1024)*2});
  if(wrapped.error)throw wrapped.error;
  const document=JSON.parse(String(wrapped.stdout||'{}'));
  const result={status:document.status,signal:document.signal,stdout:Buffer.from(document.stdout||'','base64'),stderr:Buffer.from(document.stderr||'','base64')};
  if(options.encoding!==null){result.stdout=result.stdout.toString('utf8');result.stderr=result.stderr.toString('utf8');}
  if(document.timedOut){const error=new Error(`${command} exceeded its ${timeoutMs}ms watchdog and was terminated`);if(deadlineBound)error.code='CAPACITY_DEADLINE';throw error;}
  if(document.error)throw new Error(document.error);
  if(document.overflow)throw new Error(`${command} exceeded its captured output limit`);
  if(options.stdio==='inherit'){if(result.stdout?.length)process.stdout.write(result.stdout);if(result.stderr?.length)process.stderr.write(result.stderr);}
  if (result.status !== 0 && !options.allowFailure) {
    const detail = String(result.stderr || result.stdout || '').trim().slice(-4000);
    throw new Error(`${command} failed (${result.status})${detail ? `: ${detail}` : ''}`);
  }
  return result;
}

function productionClientProfile(traffic, production) {
  const logObserved = traffic.observedClientProfiles?.sort((a,b)=>b.count-a.count)[0];
  const databaseObserved = production.dbRuntime?.clientProfiles?.sort((a,b)=>b.count-a.count)[0];
  const observed=logObserved||databaseObserved;
  if (!observed) throw new Error('rolling production sources did not provide a versioned deployed client profile');
  const featureValue=Array.isArray(observed.clientFeatures)?observed.clientFeatures.join(','):String(observed.clientFeatures||'');
  const tokens=featureValue.split(',').filter(Boolean);
  if(!tokens.length||featureValue.length>512||tokens.some(token=>!/^[a-z0-9_-]+$/.test(token)))throw new Error('production-observed deployed capability manifest is invalid');
  const userAgent=observed.userAgent||`${observed.platform==='android'?'Bara-Android':'Bara'}/${observed.appVersion}`;
  return {appVersion:observed.appVersion,platform:observed.platform,clientFeatures:featureValue,userAgent,timezone:'America/New_York',releaseChannel:'prod',observedRequests:observed.count,source:logObserved?'versioned deployed profile observed in rolling production nginx logs':'dominant privacy-safe deployed profile aggregated from active production users over seven days'};
}

function configuredDumpActiveConnectionLimit(){
  const value=Number(process.env.K6_PROD_DUMP_ACTIVE_CONNECTION_LIMIT||38);
  if(!Number.isInteger(value)||value<1||value>DB_SPEC.maxConnections)throw new Error(`K6_PROD_DUMP_ACTIVE_CONNECTION_LIMIT must be an integer from 1 through ${DB_SPEC.maxConnections}`);
  return value;
}

function configuredPoolerNearSaturationGate(){
  const value=String(process.env.K6_FAIL_ON_PGBOUNCER_NEAR_SATURATION||'false').trim().toLowerCase();
  if(!['true','false'].includes(value))throw new Error('K6_FAIL_ON_PGBOUNCER_NEAR_SATURATION must be true or false');
  return value==='true';
}

function configuredTargetPoolerSize(){
  const raw=process.env.K6_TARGET_PGBOUNCER_POOL_SIZE;
  if(raw===undefined||String(raw).trim()==='')return null;
  const value=Number(raw);
  const maximum=2*20;
  if(!Number.isInteger(value)||value<1||value>maximum)throw new Error(`K6_TARGET_PGBOUNCER_POOL_SIZE must be an integer from 1 through ${maximum}`);
  return value;
}

function configuredExperiment(){
  const raw=String(process.env.K6_EXPERIMENTAL_PROFILE||'').trim();
  if(!raw)return null;
  if(raw!==EXPERIMENT_PROFILE_NAME)throw new Error(`K6_EXPERIMENTAL_PROFILE must be exactly ${EXPERIMENT_PROFILE_NAME}`);
  return Object.freeze({
    name:EXPERIMENT_PROFILE_NAME,label:'EXPERIMENTAL ONLY — one fixed 150 RPS level',
    app:Object.freeze({cpus:4,memoryGiB:4,diskGiB:60}),workers:3,poolSize:12,
    workload:Object.freeze({...WORKLOAD,mode:'fixed-one-level',startRps:150,stepRps:0}),
  });
}

function runWorkload(state){return state.plan?.workload||WORKLOAD;}

function approvalPlanFingerprint(plan){
  const contract={
    app:plan.app,database:plan.database,workers:plan.workers,poolSize:plan.poolSize,
    targetPooler:plan.targetPooler||null,backendCommit:plan.backendCommit,
    experimental:plan.experimental||null,
    productionSourceHash:plan.productionSourceHash,trafficMixSha256:plan.trafficMixSha256,
    routeRegistrySha256:plan.routeRegistrySha256,clientProfile:plan.clientProfile,
    workload:plan.workload,safetyGates:plan.safetyGates,retention:plan.retention,
    deadlineAt:plan.deadlineAt,
    productionDatabaseShape:{
      maxConnections:plan.production?.dbRuntime?.maxConnections,
      settings:plan.production?.dbRuntime?.settings,
      poolMode:plan.production?.dbRuntime?.poolMode,
      poolerConfig:plan.production?.dbRuntime?.poolerTelemetry?.config,
      poolerDatabase:plan.production?.dbRuntime?.poolerTelemetry?.database,
    },
  };
  return createHash('sha256').update(JSON.stringify(contract)).digest('hex');
}

function completeApproval(runDir,state){
  const current=approvalPlanFingerprint(state.plan);
  if(current!==state.plan.approvalFingerprint)throw new Error('confirmed run plan changed before approval could be recorded');
  phaseComplete(runDir,state,'approval',{explicit:true,approvedAt:new Date().toISOString(),planFingerprint:current});
}

function assertApprovedPlanImmutable(state){
  if(state.phases.approval.status!=='complete')return;
  const expected=state.phases.approval.postconditions?.planFingerprint;
  const current=approvalPlanFingerprint(state.plan);
  if(!expected||expected!==state.plan.approvalFingerprint||current!==expected)throw new Error('approved run plan fingerprint no longer matches; refusing to continue');
}

function runText(command, args, options = {}) {
  return String(run(command, args, options).stdout || '').trim();
}

function runAsync(command,args,options={}){
  return new Promise((resolveRun,rejectRun)=>{
    const child=spawn(command,args,{cwd:options.cwd,env:options.env||process.env,stdio:options.stdio||'inherit'});
    const requestedTimeout=options.timeoutMs||30*60*1000;const deadlineRemaining=activePhaseDeadlineMs===null?Infinity:activePhaseDeadlineMs-Date.now();const deadlineBound=deadlineRemaining<=requestedTimeout;const timeoutMs=Math.max(1,Math.min(requestedTimeout,deadlineRemaining));let timedOut=false,killTimer=null;
    const watchdog=setTimeout(()=>{timedOut=true;child.kill('SIGTERM');killTimer=setTimeout(()=>child.kill('SIGKILL'),10_000);},timeoutMs);
    child.once('error',error=>{clearTimeout(watchdog);rejectRun(error);});
    child.once('close',code=>{clearTimeout(watchdog);if(killTimer)clearTimeout(killTimer);if(code===0&&!timedOut){resolveRun();return;}const error=new Error(`${command} ${timedOut?'exceeded watchdog':`failed (${code})`}`);if(timedOut&&deadlineBound)error.code='CAPACITY_DEADLINE';rejectRun(error);});
  });
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function shortHash(value) {
  return createHash('sha256').update(String(value)).digest('hex').slice(0, 12);
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function parseDotenv(raw) {
  const values = {};
  for (const line of raw.split(/\r?\n/)) {
    const match = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!match) continue;
    let value = match[2];
    if (value.startsWith("'") && value.endsWith("'")) value = value.slice(1, -1);
    else if (value.startsWith('"') && value.endsWith('"')) value = value.slice(1, -1).replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
    else value = value.replace(/\s+#.*$/, '').trim();
    values[match[1]] = value;
  }
  return values;
}

function dotenvLine(key, value) {
  return `${key}=${JSON.stringify(String(value))}`;
}

function readLocalBackendPath() {
  if (process.env.K6_BACKEND_REPO) return resolve(process.env.K6_BACKEND_REPO);
  const local = join(REPO_ROOT, 'CLAUDE.local.md');
  if (!existsSync(local)) throw new Error('CLAUDE.local.md is missing; set K6_BACKEND_REPO');
  const match = /Local backend repo:\s*`([^`]+)`/.exec(readFileSync(local, 'utf8'));
  if (!match) throw new Error('local backend path is not configured; set K6_BACKEND_REPO');
  return resolve(match[1]);
}

function readProductionSsh(backendRepo) {
  if (process.env.K6_PROD_SSH) return process.env.K6_PROD_SSH;
  const local = join(backendRepo, 'CLAUDE.local.md');
  if (existsSync(local)) {
    const match = /root@(?:\d{1,3}\.){3}\d{1,3}/.exec(readFileSync(local, 'utf8'));
    if (match) return match[0];
  }
  throw new Error('production SSH target could not be recovered locally; set K6_PROD_SSH for this invocation');
}

function pgTools() {
  const prefix = process.env.K6_PG_BIN_DIR || '/opt/homebrew/opt/postgresql@18/bin';
  const tools = {psql: join(prefix, 'psql'), pgDump: join(prefix, 'pg_dump'), pgRestore: join(prefix, 'pg_restore')};
  for (const [name, path] of Object.entries(tools)) if (!existsSync(path)) throw new Error(`${name} PG18 binary missing at ${path}; set K6_PG_BIN_DIR`);
  return tools;
}

function backendRouteLiteralSegments(backendRepo, backendCommit) {
  const result=run('git',['-C',backendRepo,'grep','-h','-E','["\x27`]/',backendCommit,'--','src'],{allowFailure:true});
  const source=String(result.stdout||'');
  const literals=new Set();
  for(const match of source.matchAll(/(["'`])(\/[A-Za-z0-9_:/.*-]*)\1/g)){
    for(const segment of match[2].split('/').filter(Boolean)){
      if(/^[A-Za-z][A-Za-z0-9_-]*$/.test(segment))literals.add(segment);
    }
  }
  if(literals.size<10)throw new Error('backend route literal catalog could not be derived from origin/main');
  return [...literals].sort();
}

function commandVersion(command, args = ['--version']) {
  const result = run(command, args, {allowFailure: true});
  if (result.status !== 0) throw new Error(`${command} version check failed`);
  return String(result.stdout || result.stderr || '').trim().split(/\r?\n/)[0];
}

function localPreflight(tools) {
  const filesystem = statfsSync(REPO_ROOT);
  return {
    versions: {
      lima: commandVersion('limactl'), ssh: commandVersion('ssh', ['-V']),
      node: commandVersion('node'), npm: commandVersion('npm'), k6: commandVersion('k6', ['version']),
      pgDump: commandVersion(tools.pgDump), pgRestore: commandVersion(tools.pgRestore),
    },
    availableDiskBytes: Number(filesystem.bavail) * Number(filesystem.bsize),
  };
}

function remoteInspection(sshTarget) {
  const script = String.raw`
const fs=require('fs'),crypto=require('crypto'),cp=require('child_process'),os=require('os');
const envPath='/var/www/step-tracker-backend/.env';
const parse=s=>Object.fromEntries(s.split(/\r?\n/).map(x=>/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(x)).filter(Boolean).map(m=>[m[1],m[2].trim().replace(/^['"]|['"]$/g,'')]));
const hash=v=>crypto.createHash('sha256').update(String(v)).digest('hex');
const envRaw=fs.readFileSync(envPath,'utf8');const file=parse(envRaw);
const list=JSON.parse(cp.execFileSync('pm2',['jlist'],{encoding:'utf8'})).filter(p=>p.name==='steps-tracker');
const workers=list.map(p=>{let live={}; try{live=Object.fromEntries(fs.readFileSync('/proc/'+p.pid+'/environ').toString().split('\0').filter(Boolean).map(x=>{const i=x.indexOf('=');return [x.slice(0,i),x.slice(i+1)]}))}catch{} return {pid:p.pid,instance:String(live.NODE_APP_INSTANCE??p.pm2_env?.NODE_APP_INSTANCE??''),status:p.pm2_env?.status||'',memoryRestart:p.pm2_env?.max_memory_restart||null,envHashes:Object.fromEntries(Object.entries(live).map(([k,v])=>[k,hash(v)]))}});
const fileHashes=Object.fromEntries(Object.entries(file).map(([k,v])=>[k,hash(v)]));
const comparableKeys=Object.entries(file).filter(([k,v])=>/^(RACE_|STEP_|QUEUE_|.*_ENABLED$|.*_DISABLED$|NODE_ENV$|APNS_PRODUCTION$)/.test(k)&&/^(true|false|-?\d+(?:\.\d+)?|[A-Z_]+)$/i.test(v)).map(([k])=>k);
const drift=comparableKeys.filter(k=>workers.some(w=>w.envHashes[k]!==fileHashes[k]));
let nginx='';try{nginx=cp.execFileSync('nginx',['-T'],{encoding:'utf8',stdio:['ignore','pipe','ignore']})}catch{}
const pick=re=>nginx.match(re)?.[1]||null;
const productionAccessLogs=(()=>{const paths=[];const starts=[];for(const match of nginx.matchAll(/\bserver\s*\{/g))starts.push(match.index);for(const start of starts){let depth=0,end=start;for(;end<nginx.length;end++){if(nginx[end]==='{')depth++;else if(nginx[end]==='}'&&--depth===0){end++;break}}const block=nginx.slice(start,end);const names=[...block.matchAll(/^\s*server_name\s+([^;]+);/gm)].flatMap(m=>m[1].trim().split(/\s+/));if(!names.includes('steptracker-api.org'))continue;for(const match of block.matchAll(/^\s*access_log\s+([^;\s]+)/gm))if(match[1]!=='off')paths.push(match[1])}const existing=[...new Set(paths)].filter(path=>path.startsWith('/var/log/nginx/')&&fs.existsSync(path));if(existing.length)return existing;const inherited=[...nginx.matchAll(/^\s*access_log\s+([^;\s]+)/gm)].map(match=>match[1]).filter(path=>path!=='off'&&path.startsWith('/var/log/nginx/')&&!/staging/i.test(path)&&fs.existsSync(path));return [...new Set(inherited)]})();
const db=(()=>{try{const u=new URL(file.DATABASE_URL);return {host:u.hostname,database:u.pathname.slice(1),hostHash:hash(u.hostname),port:u.port||'5432',databaseHash:hash(u.pathname.slice(1)),sslmode:u.searchParams.get('sslmode'),proxyDetected:/pool|pgbouncer/i.test(u.hostname)||u.port==='6432'}}catch{return null}})();
const redis=(()=>{try{const u=new URL(file.REDIS_URL);const args=['-h',u.hostname,'-p',u.port||'6379'];if(u.protocol==='rediss:')args.push('--tls');args.push('INFO');let info='';try{info=cp.execFileSync('redis-cli',args,{encoding:'utf8',env:{...process.env,REDISCLI_AUTH:decodeURIComponent(u.password||'')}})}catch{};const value=k=>new RegExp('^'+k+':([^\\r\\n]+)','m').exec(info)?.[1]||null;return {enabled:true,scheme:u.protocol,hostHash:hash(u.hostname),version:value('redis_version'),maxMemoryBytes:Number(value('maxmemory')||0),maxMemoryPolicy:value('maxmemory_policy')}}catch{return {enabled:false}}})();
const safeFlags=Object.fromEntries(Object.entries(file).filter(([k,v])=>/^(RACE_|STEP_|QUEUE_|.*_ENABLED$|.*_DISABLED$|NODE_ENV$|APNS_PRODUCTION$)/.test(k)&&/^(true|false|-?\d+(?:\.\d+)?|[A-Z_]+)$/i.test(v)));
const diskBytes=(()=>{try{return Number(cp.execFileSync('df',['-B1','--output=size','/'],{encoding:'utf8'}).trim().split(/\s+/).at(-1))}catch{return null}})();
const poolSize=(()=>{try{return Number(/new pg\.Pool\(\{[\s\S]*?max:\s*(\d+)/.exec(fs.readFileSync('/var/www/step-tracker-backend/src/db.js','utf8'))?.[1]||0)}catch{return null}})();
(async()=>{let dbRuntime=null,dbRuntimeError=null;const pgModulePath='/var/www/step-tracker-backend/node_modules/pg';if(file.DATABASE_URL){try{const {Client}=require(pgModulePath);const inspectedDbUrl=file.DATABASE_URL.replace(/[?&]sslmode=[^&]*/g,'');const client=new Client({connectionString:inspectedDbUrl,ssl:{rejectUnauthorized:false},connectionTimeoutMillis:5000});await client.connect();const result=await client.query("SELECT current_setting('server_version') AS version,current_setting('max_connections')::int AS max_connections,pg_database_size(current_database())::bigint AS database_bytes");const names=['shared_buffers','work_mem','effective_cache_size','random_page_cost','effective_io_concurrency','max_worker_processes','max_parallel_workers','max_parallel_workers_per_gather','jit'];const settings=Object.fromEntries((await client.query('SELECT name,current_setting(name) AS value FROM pg_settings WHERE name=ANY($1)',[names])).rows.map(r=>[r.name,r.value]));const clientProfiles=(await client.query("SELECT last_app_version AS \"appVersion\",CASE WHEN google_sub IS NOT NULL THEN 'android' WHEN apple_id IS NOT NULL THEN 'ios' ELSE 'unknown' END AS platform,client_features AS \"clientFeatures\",COUNT(*)::int AS count FROM users WHERE last_seen_at >= NOW()-INTERVAL '7 days' AND last_app_version IS NOT NULL AND cardinality(client_features)>0 GROUP BY last_app_version,platform,client_features ORDER BY count DESC LIMIT 20")).rows.filter(row=>row.platform!=='unknown');await client.end();let poolMode=null,poolerTelemetry={available:false};try{const adminUrl=new URL(inspectedDbUrl);adminUrl.pathname='/pgbouncer';const admin=new Client({connectionString:adminUrl.toString(),ssl:{rejectUnauthorized:false},connectionTimeoutMillis:5000});await admin.connect();const configRows=(await admin.query('SHOW CONFIG')).rows;poolMode=configRows.find(r=>r.key==='pool_mode')?.value||null;const pools=await admin.query('SHOW POOLS'),stats=await admin.query('SHOW STATS'),databases=await admin.query('SHOW DATABASES');const aggregate=(rows,keys)=>Object.fromEntries(keys.map(k=>[k,rows.reduce((s,r)=>s+Number(r[k]||0),0)]));const configKeys=['default_pool_size','reserve_pool_size','max_client_conn','max_db_connections','max_user_connections','server_lifetime','server_idle_timeout','query_timeout','client_idle_timeout','server_connect_timeout','server_login_retry','ignore_startup_parameters'];const productionDb=new URL(file.DATABASE_URL).pathname.slice(1);const databaseRow=databases.rows.find(r=>r.name===productionDb||r.database===productionDb)||{};poolerTelemetry={available:true,pools:aggregate(pools.rows,['cl_active','cl_waiting','sv_active','sv_idle','sv_used','sv_tested','sv_login']),stats:aggregate(stats.rows,['total_xact_count','total_query_count','total_received','total_sent','total_xact_time','total_query_time','total_wait_time']),config:Object.fromEntries(configRows.filter(r=>configKeys.includes(r.key)).map(r=>[r.key,r.value])),database:Object.fromEntries(['pool_size','reserve_pool','max_connections','current_connections','pool_mode'].map(k=>[k,databaseRow[k]??null]))};await admin.end()}catch{}dbRuntime={version:result.rows[0].version,maxConnections:result.rows[0].max_connections,databaseBytes:Number(result.rows[0].database_bytes),poolMode,settings,poolerTelemetry,clientProfiles}}catch(error){dbRuntimeError={name:String(error?.name||'Error'),code:error?.code==null?null:String(error.code),pgModuleReadable:fs.existsSync(pgModulePath)}}}const materialHash=hash(JSON.stringify({env:hash(envRaw),fileHashes,workers:workers.map(w=>({instance:w.instance,status:w.status,memoryRestart:w.memoryRestart,envHashes:w.envHashes})),poolSize,safeFlags,db,nginx:{workerProcesses:pick(/worker_processes\s+([^;]+);/),workerConnections:pick(/worker_connections\s+(\d+);/),workerRlimit:pick(/worker_rlimit_nofile\s+(\d+);/),proxyHttpVersion:pick(/proxy_http_version\s+([^;]+);/)}}));process.stdout.write(JSON.stringify({workerCount:workers.length,poolSize,workers:workers.map(({envHashes,...w})=>w),envFileSha256:hash(envRaw),materialHash,envKeyCount:Object.keys(file).length,envKeyHash:hash(Object.keys(file).sort().join('\n')),effectiveDriftKeys:drift.sort(),safeFlags,appResources:{cpus:os.cpus().length,memoryBytes:os.totalmem(),diskBytes},db,dbRuntime,dbRuntimeError,redis,nginx:{workerProcesses:pick(/worker_processes\s+([^;]+);/),workerConnections:pick(/worker_connections\s+(\d+);/),workerRlimit:pick(/worker_rlimit_nofile\s+(\d+);/),proxyHttpVersion:pick(/proxy_http_version\s+([^;]+);/),productionAccessLogs}}))})().catch(error=>{process.stderr.write(error.message);process.exit(2)});
`;
  const result = run('ssh', ['-o', 'BatchMode=yes', sshTarget, 'node', '-'], {input: script});
  return JSON.parse(result.stdout);
}

function productionUsesPooler(production) {
  return Boolean(production.db?.proxyDetected || production.dbRuntime?.poolMode);
}

function printPlan(state, context) {
  const plan = state.plan;
  process.stdout.write(`\nK6 capacity run ${state.runId}\n\n`);
  if(plan.experimental)process.stdout.write(`  EXPERIMENT:   ${plan.experimental.label}; production/default specifications are unchanged\n`);
  process.stdout.write(`  App VM:       ${plan.app.cpus} vCPU / ${plan.app.memoryGiB} GiB / ${plan.app.diskGiB} GiB\n`);
  process.stdout.write(`  Database VM:  ${plan.database.cpus} shared vCPU / ${plan.database.memoryGiB} GiB / ${plan.database.diskGiB} GiB\n`);
  process.stdout.write(`  PostgreSQL:   ${plan.database.maxConnections} connections; ${plan.workers} backend workers x pool ${plan.poolSize}\n`);
  process.stdout.write(`  Observed prod:${plan.production.appResources?.cpus} vCPU / ${(Number(plan.production.appResources?.memoryBytes||0)/1073741824).toFixed(2)} GiB / ${(Number(plan.production.appResources?.diskBytes||0)/1073741824).toFixed(2)} GiB filesystem; PG ${plan.production.dbRuntime?.version||'unknown'} (${productionUsesPooler(plan.production)?'pooler':'direct'})\n`);
  process.stdout.write(`  Prod runtime: ${plan.production.workerCount} workers x pool ${plan.production.poolSize}; database ceiling ${plan.production.dbRuntime?.maxConnections}\n`);
  process.stdout.write(`  DB parity:    ${Object.keys(plan.production.dbRuntime?.settings||{}).length} PostgreSQL settings captured; PgBouncer SHOW telemetry=${productionUsesPooler(plan.production)?(plan.production.dbRuntime?.poolerTelemetry?.available?'captured':'unavailable/non-comparable'):'not applicable'}\n`);
  if(plan.targetPooler)process.stdout.write(`  PgBouncer:    production per-database pool_size ${plan.targetPooler.productionObservedPoolSize} -> disposable target ${plan.targetPooler.disposablePoolSize}; PostgreSQL ceiling remains ${plan.database.maxConnections}\n`);
  process.stdout.write(`  Backend:      origin/main @ ${plan.backendCommit}\n`);
  process.stdout.write(`  Production:   source sha256:${plan.productionSourceHash}, ${PROD_ENV_PATH}; .env copied byte-for-byte after approval\n`);
  process.stdout.write(`  Database:     host sha256:${plan.production.db.hostHash.slice(0,12)}, database sha256:${plan.production.db.databaseHash.slice(0,12)}, port ${plan.production.db.port} (credentials suppressed)\n`);
  process.stdout.write(`  VM action:    create two unique run-bound VMs; reuse only within this run; destroy after report\n`);
  process.stdout.write(`  Traffic:      ${plan.traffic.interval.start} through ${plan.traffic.interval.end} (half-open UTC)\n`);
  process.stdout.write(`  Log proof:    ${plan.traffic.windowCoverage.sourceMin} through ${plan.traffic.windowCoverage.sourceMax}; both rolling-week boundaries covered\n`);
  process.stdout.write(`                ${plan.traffic.eligibleCount}/${plan.traffic.comparableDenominator} eligible requests; ${plan.traffic.coveragePercent.toFixed(2)}% registry coverage\n`);
  process.stdout.write(plan.workload.mode==='fixed-one-level'?`  Load:         production mix, fixed ${plan.workload.startRps} RPS only; 30s warm-up + 3m measured; one same-rate retry on failure; no lower ramp\n`:`  Load:         production mix, 50 RPS +10/pass; 30s warm-up + 3m measured; fail twice stops; 8h deadline; no RPS cap\n`);
  process.stdout.write(`  Client:       ${plan.clientProfile.platform} ${plan.clientProfile.appVersion}; ${plan.clientProfile.clientFeatures.split(',').length} confirmed capabilities; ${plan.clientProfile.observedRequests} observed requests\n`);
  process.stdout.write(`  Deadline:     ${plan.deadlineAt} (anchored to run creation)\n`);
  process.stdout.write(`  Data:         fresh prod restore; exactly 10,000 synthetic users; 1-5 active races each; device/push/queue rows scrubbed\n`);
  process.stdout.write(`  Safety:       capacity-only tokens; all external writes blocked; isolated Redis=${plan.production.redis.enabled ? 'required' : 'not used'}\n`);
  process.stdout.write(`  Barriers:     derived drain timeout ${durationTimeout(plan)}s; production dump aborts above ${plan.safetyGates.dumpActiveConnectionLimit} active connections; PgBouncer near-saturation failure=${plan.safetyGates.failOnPoolerNearSaturation}\n`);
  process.stdout.write('  Cleanup:      save redacted report and receipt, then destroy both VMs and every run secret\n');
  if (plan.production.effectiveDriftKeys.length) process.stdout.write(`  Env drift:    ${plan.production.effectiveDriftKeys.join(', ')}\n`);
  if(plan.productionDeviations.length)process.stdout.write(`  Differences:  ${plan.productionDeviations.join('; ')}\n`);
  process.stdout.write(`  Plan proof:   sha256:${plan.approvalFingerprint}\n`);
  process.stdout.write('  Route weights:\n');
  for (const [key,weight] of Object.entries(plan.traffic.weights).sort(([a],[b])=>a.localeCompare(b))) process.stdout.write(`    ${key}: ${(weight*100).toFixed(6)}%\n`);
  process.stdout.write('  Unknown route exclusions:\n');
  if (!plan.traffic.unknownRoutes.length) process.stdout.write('    none\n');
  for (const item of plan.traffic.unknownRoutes) process.stdout.write(`    ${item.template}: ${item.count}\n`);
  process.stdout.write('  Filtered request exclusions:\n');
  for(const [reason,count] of Object.entries(plan.traffic.exclusions).sort(([a],[b])=>a.localeCompare(b)))process.stdout.write(`    ${reason}: ${count}\n`);
  process.stdout.write('\n');
}

async function confirm() {
  if (!process.stdin.isTTY || !process.stdout.isTTY) throw new Error('run confirmation requires an interactive terminal');
  const reader = createInterface({input: process.stdin, output: process.stdout});
  const answer = await new Promise(resolveAnswer => {let settled=false;const finish=value=>{if(settled)return;settled=true;cancelConfirmation=null;resolveAnswer(value);};cancelConfirmation=()=>{reader.close();finish('');};reader.question('Type RUN to approve this exact plan: ', finish);});
  reader.close();
  return answer.trim() === 'RUN';
}

function makeRunId() {
  return `stepv2-k6-${new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z').toLowerCase()}-${randomBytes(3).toString('hex')}`;
}

function directories(root, runId) {
  const runDir = join(root, 'runs', runId);
  const publicDir = join(runDir, 'public');
  const secretDir = join(runDir, 'protected');
  mkdirSync(publicDir, {recursive: true, mode: 0o700});
  mkdirSync(secretDir, {recursive: true, mode: 0o700});
  chmodSync(runDir, 0o700); chmodSync(publicDir, 0o700); chmodSync(secretDir, 0o700);
  return {runDir, publicDir, secretDir};
}

async function discover(runDir, state, secretContext) {
  phaseStart(runDir, state, 'discovery');
  try {
    const experiment=configuredExperiment();
    const appSpec=experiment?.app||APP_SPEC,workers=experiment?.workers||2,poolSize=experiment?.poolSize||20,workload=experiment?.workload||WORKLOAD;
    for (const command of ['limactl','ssh','scp','git','node','npm','k6']) if (!commandExists(command)) throw new Error(`${command} is required`);
    const tools = pgTools();
    const preflight = localPreflight(tools);
    const selfValidation = validateEightHourEnvelope();
    if (!existsSync(REQUIREMENTS_PATH)) throw new Error('approved k6 requirements document is missing');
    const backendRepo = readLocalBackendPath();
    const sshTarget = readProductionSsh(backendRepo);
    run('git', ['-C', backendRepo, 'fetch', '--quiet', 'origin', 'main']);
    const backendCommit = runText('git', ['-C', backendRepo, 'rev-parse', 'origin/main']);
    if (!/^[a-f0-9]{40}$/.test(backendCommit)) throw new Error('origin/main did not resolve to a commit');
    for(const path of [HELPER_PATH,SERVER_PATH,'scripts/perf/capacity-effective-env.js','src/localCapacitySafety.js','package-lock.json']){
      const exists=run('git',['-C',backendRepo,'cat-file','-e',`${backendCommit}:${path}`],{allowFailure:true});
      if(exists.status!==0)throw new Error(`latest origin/main is missing required capacity support: ${path}`);
    }
    const originDbSource=runText('git',['-C',backendRepo,'show',`${backendCommit}:src/db.js`]);
    const originCapacitySafetySource=runText('git',['-C',backendRepo,'show',`${backendCommit}:src/localCapacitySafety.js`]);
    if(!/max:\s*databasePoolMax\b/.test(originDbSource))throw new Error('latest origin/main does not route the application pool through the capacity-safe pool-size helper');
    if(!/const productionDefault = 20;/.test(originCapacitySafetySource)||!/if \(!strictTrue\(env\.CAPACITY_MODE\)\) return productionDefault;/.test(originCapacitySafetySource))throw new Error('latest origin/main does not prove the production/default application pool remains 20');
    run('ssh', ['-o', 'BatchMode=yes', sshTarget, 'test', '-r', PROD_ENV_PATH]);
    const production = remoteInspection(sshTarget);
    if(!production.db?.host||!production.db?.database)throw new Error('production database source could not be resolved without credentials');
    const productionDatabaseSource={host:production.db.host,port:production.db.port,database:production.db.database};
    delete production.db.host; delete production.db.database;
    if(!Number.isInteger(production.workerCount)||production.workerCount<1||!Number.isInteger(production.poolSize)||production.poolSize<1)throw new Error('production worker/pool topology could not be inspected');
    const memoryRestartLimits=[...new Set(production.workers.map(worker=>Number(worker.memoryRestart||0)))];
    if(memoryRestartLimits.length!==1)throw new Error('production PM2 memory restart policy differs between workers');
    if(!production.dbRuntime){
      const diagnostic=production.dbRuntimeError||{};
      throw new Error(`production PostgreSQL version/connection ceiling could not be inspected read-only (error=${diagnostic.name||'unknown'}, code=${diagnostic.code||'none'}, pgModuleReadable=${diagnostic.pgModuleReadable===true})`);
    }
    const sourcePgMajor=Number(/^\s*(\d+)/.exec(String(production.dbRuntime.version||''))?.[1]);
    const clientPgMajor=Number(/(\d+)(?:\.\d+)?/.exec(preflight.versions.pgDump)?.[1]);
    if(!Number.isInteger(sourcePgMajor)||!Number.isInteger(clientPgMajor)||sourcePgMajor>clientPgMajor)throw new Error(`PG dump client ${preflight.versions.pgDump} is not compatible with production PostgreSQL ${production.dbRuntime.version||'unknown'}`);
    if(!Number.isInteger(production.dbRuntime?.maxConnections))throw new Error('production database connection ceiling could not be inspected');
    const databaseBytes=Number(production.dbRuntime.databaseBytes||0);
    const localBytesRequired=Math.ceil(databaseBytes*2.25)+15*1073741824;
    if(!Number.isFinite(databaseBytes)||databaseBytes<1)throw new Error('production database size could not be inspected read-only');
    if(preflight.availableDiskBytes<localBytesRequired)throw new Error(`insufficient local disk for protected dump: need ${Math.ceil(localBytesRequired/1073741824)} GiB, have ${(preflight.availableDiskBytes/1073741824).toFixed(1)} GiB`);
    if(databaseBytes>DB_SPEC.diskGiB*1073741824*0.70)throw new Error(`production database ${(databaseBytes/1073741824).toFixed(1)} GiB cannot be restored safely inside the confirmed ${DB_SPEC.diskGiB} GiB database VM`);
    if(production.redis.enabled&&!production.redis.version)throw new Error('production Redis is enabled but its version/limits could not be inspected read-only');
    const routeLiteralSegments=backendRouteLiteralSegments(backendRepo,backendCommit);
    const traffic = await deriveRollingMix({sshTarget, registryPath: REGISTRY_PATH,logPaths:production.nginx.productionAccessLogs,routeLiteralSegments,endMs:Date.parse(state.createdAt),deadlineMs:absoluteDeadline(state)});
    if (traffic.coveragePercent < workload.coverageMinimum) {
      const unknownSummary=traffic.unknownRoutes.slice(0,25).map(item=>`${item.template}=${item.count}`).join(', ');
      throw new Error(`route registry coverage ${traffic.coveragePercent.toFixed(2)}% is below ${workload.coverageMinimum}%; anonymized unknowns: ${unknownSummary||'none'}`);
    }
    if(durationTimeout({production})>7200)throw new Error('derived queue drain timeout exceeds the guarded backend maximum of two hours; review production timing flags before running');
    const clientProfile = productionClientProfile(traffic,production);
    Object.assign(secretContext, {backendRepo, sshTarget, productionDatabaseSource,backendCommit});
    atomicJson(join(runDir, 'protected/context.json'), secretContext);
    const productionDeviations=[];
    if(production.appResources?.cpus!==appSpec.cpus||Math.round(Number(production.appResources?.memoryBytes||0)/1073741824)!==appSpec.memoryGiB)productionDeviations.push(`droplet observed as ${production.appResources?.cpus} vCPU/${(Number(production.appResources?.memoryBytes||0)/1073741824).toFixed(2)} GiB, confirmed VM target is ${appSpec.cpus}/${appSpec.memoryGiB}`);
    if(production.workerCount!==workers||production.poolSize!==poolSize)productionDeviations.push(`production runtime observed as ${production.workerCount} workers x pool ${production.poolSize}, confirmed run target is ${workers} x ${poolSize}`);
    if(production.dbRuntime.maxConnections!==DB_SPEC.maxConnections)productionDeviations.push(`production database ceiling observed as ${production.dbRuntime.maxConnections}, confirmed run remains ${DB_SPEC.maxConnections}`);
    if(sourcePgMajor!==18)productionDeviations.push(`production PostgreSQL major ${sourcePgMajor} differs from recreated PostgreSQL 18; final result is non-comparable`);
    if(productionUsesPooler(production)&&production.dbRuntime?.poolerTelemetry?.available!==true)productionDeviations.push('production PgBouncer SHOW POOLS/STATS unavailable; final result is non-comparable');
    if(productionUsesPooler(production)&&production.dbRuntime?.poolerTelemetry?.available===true&&Object.keys(production.dbRuntime.poolerTelemetry.config||{}).length<10)productionDeviations.push('production PgBouncer SHOW CONFIG was incomplete; final result is non-comparable');
    const requestedPoolerSize=configuredTargetPoolerSize();
    if(requestedPoolerSize!==null&&!productionUsesPooler(production))throw new Error('K6_TARGET_PGBOUNCER_POOL_SIZE was set but production does not use a PgBouncer path');
    const observedPoolerSize=productionUsesPooler(production)?Number(production.dbRuntime?.poolerTelemetry?.database?.pool_size):null;
    if(requestedPoolerSize!==null&&(!Number.isInteger(observedPoolerSize)||observedPoolerSize<1))throw new Error('production per-database PgBouncer pool_size could not be observed for the requested capacity-only override');
    const observedPoolerMax=productionUsesPooler(production)?Number(production.dbRuntime?.poolerTelemetry?.database?.max_connections||0):0;
    if(requestedPoolerSize!==null&&Number.isInteger(observedPoolerMax)&&observedPoolerMax>0&&observedPoolerMax<requestedPoolerSize)throw new Error(`production-reproduced PgBouncer max_db_connections ${observedPoolerMax} would cap requested pool_size ${requestedPoolerSize}`);
    const targetPooler=productionUsesPooler(production)?{
      productionObservedPoolSize:observedPoolerSize,
      disposablePoolSize:requestedPoolerSize??observedPoolerSize,
      explicitOverride:requestedPoolerSize!==null,
    }:null;
    if(targetPooler?.explicitOverride&&targetPooler.disposablePoolSize!==targetPooler.productionObservedPoolSize)productionDeviations.push(`PgBouncer per-database pool_size intentionally changed from production ${targetPooler.productionObservedPoolSize} to disposable target ${targetPooler.disposablePoolSize}; production remains unchanged`);
    const safetyGates={dumpActiveConnectionLimit:configuredDumpActiveConnectionLimit(),failOnPoolerNearSaturation:configuredPoolerNearSaturationGate()};
    state.plan = {
      app: appSpec, database: DB_SPEC, workers, poolSize,experimental:experiment,
      backendCommit, productionSourceHash: shortHash(sshTarget), production, traffic, preflight,
      clientProfile, selfValidation, deadlineAt:new Date(Date.parse(state.createdAt)+workload.deadlineSeconds*1000).toISOString(), nextStepLogicalBase:1,
      productionDeviations,safetyGates,targetPooler,
      workload, retention: 'destroy-after-report',
    };
    atomicJson(join(runDir, 'public/traffic-mix.json'), traffic, 0o600);
    atomicJson(join(runDir, 'public/route-registry.v1.json'), JSON.parse(readFileSync(REGISTRY_PATH,'utf8')), 0o600);
    state.plan.trafficMixSha256=sha256(join(runDir,'public/traffic-mix.json'));
    state.plan.routeRegistrySha256=sha256(join(runDir,'public/route-registry.v1.json'));
    state.plan.approvalFingerprint=approvalPlanFingerprint(state.plan);
    atomicJson(join(runDir, 'public/discovery.json'), {
      backendCommit, productionSourceHash: state.plan.productionSourceHash, production, traffic, clientProfile, selfValidation,safetyGates,targetPooler,experimental:experiment,approvalFingerprint:state.plan.approvalFingerprint,
      discoveredAt: new Date().toISOString(),
    });
    phaseComplete(runDir, state, 'discovery', {backendCommit, coveragePercent: traffic.coveragePercent});
  } catch (error) {
    phaseFailed(runDir, state, 'discovery', error);
    throw error;
  }
}

function limaExists(name) {
  const result = run('limactl', ['list', name, '--json'], {allowFailure: true});
  return result.status === 0 && String(result.stdout).trim() !== '';
}

function lima(runContext, vm, args, options = {}) {
  return run('limactl', ['shell', vm, '--', ...args], options);
}

function limaAsync(vm,args,options={}){return runAsync('limactl',['shell',vm,'--',...args],options);}

function markerValid(runContext, vm) {
  if (!limaExists(vm)) return false;
  const result = lima(runContext, vm, ['sudo','cat','/etc/stepv2-capacity-run'], {allowFailure: true});
  return result.status === 0 && String(result.stdout).trim() === runContext.runId;
}

function vmHostIdentity(vm){
  const document=JSON.parse(runText('limactl',['list',vm,'--json']));
  if(document.name!==vm||!document.dir)throw new Error('Lima host identity did not match the requested VM');
  const metadata=lstatSync(document.dir);
  if(!metadata.isDirectory())throw new Error('Lima instance directory is not a directory');
  const stable={name:document.name,dirHash:shortHash(document.dir),device:String(metadata.dev),inode:String(metadata.ino),birthtimeMs:metadata.birthtimeMs,vmType:document.vmType,arch:document.arch,cpus:Number(document.cpus),memory:Number(document.memory),disk:Number(document.disk),portForwards:document.config?.portForwards||[]};
  return createHash('sha256').update(JSON.stringify(stable)).digest('hex');
}

function vmOwnershipValid(context,vm){
  const receipt=context.vmOwnership?.[vm];
  if(receipt?.owned!==true||receipt.runId!==context.runId||receipt.vmNameHash!==shortHash(vm)||receipt.topologyRevision!==context.topologyRevision)return false;
  try{return receipt.hostIdentitySha256===vmHostIdentity(vm);}catch{return false;}
}

function recordVmOwnership(runDir,context,vm){
  context.vmOwnership||={};
  context.vmOwnership[vm]={owned:true,runId:context.runId,vmNameHash:shortHash(vm),hostIdentitySha256:vmHostIdentity(vm),topologyRevision:context.topologyRevision,createdAt:new Date().toISOString()};
  atomicJson(join(runDir,'protected/context.json'),context);
}

function privateControlAddress(value){
  const address=String(value||'').toLowerCase();
  const family=isIP(address);if(!family)return false;
  if(family===4){const octets=address.split('.').map(Number);return octets[0]===10||octets[0]===127||(octets[0]===169&&octets[1]===254)||(octets[0]===192&&octets[1]===168)||(octets[0]===172&&octets[1]>=16&&octets[1]<=31)||(octets[0]===100&&octets[1]>=64&&octets[1]<=127);}
  return address==='::1'||address.startsWith('fc')||address.startsWith('fd')||/^fe[89ab]/.test(address);
}

function discoverLimaControlPlane(context,vm){
  const script=`set -u
set -- \${SSH_CONNECTION:?missing SSH_CONNECTION}
test "$#" -eq 4 || exit 1
source_address="$1"
source_port="$2"
server_address="$3"
server_port="$4"
if [ "$source_address" = UNKNOWN ] || [ "$server_address" = UNKNOWN ]; then
  printf 'vsock\\t%s\\t%s\\t%s\\t%s\\n' "$source_address" "$source_port" "$server_address" "$server_port"
  exit 0
fi
route="$(ip -o route get "$source_address" | head -n 1)"
interface="$(printf '%s\\n' "$route" | awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')"
gateway="$(printf '%s\\n' "$route" | awk '{for(i=1;i<=NF;i++)if($i=="via"){print $(i+1);exit}}')"
test -n "$interface"
test -n "$gateway" || gateway=direct
printf 'tcp\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$source_address" "$source_port" "$server_address" "$server_port" "$interface" "$gateway"`;
  const fields=String(lima(context,vm,['bash','-lc',script],{timeoutMs:15_000}).stdout||'').trim().split('\t');
  if(fields[0]==='vsock'){
    if(fields.length!==5||fields[1]!=='UNKNOWN'||fields[3]!=='UNKNOWN')throw new Error('Lima vsock control-plane discovery returned an invalid tuple');
    const sourcePort=Number(fields[2]),serverPort=Number(fields[4]);
    const document=JSON.parse(runText('limactl',['list',vm,'--json']));
    if(document.name!==vm||document.vmType!=='vz'||!vmOwnershipValid(context,vm))throw new Error('Lima UNKNOWN control-plane tuple was not backed by a run-owned VZ instance');
    if(sourcePort!==65535||serverPort!==65535)throw new Error('Lima vsock control-plane sentinel ports are invalid');
    return {transport:'vsock',sourceAddress:'vsock',serverAddress:'vsock',serverPort:null,interfaceName:'vsock',gateway:'direct'};
  }
  if(fields.length!==7||fields[0]!=='tcp')throw new Error('Lima control-plane discovery returned an invalid tuple');
  const [,sourceAddress,sourcePortText,serverAddress,serverPortText,interfaceName,gateway]=fields;
  const sourcePort=Number(sourcePortText),serverPort=Number(serverPortText);
  if(!privateControlAddress(sourceAddress)||!privateControlAddress(serverAddress))throw new Error('Lima control-plane SSH addresses are not private or loopback');
  if(gateway!=='direct'&&!privateControlAddress(gateway))throw new Error('Lima control-plane gateway is not private or direct');
  if(!Number.isInteger(sourcePort)||sourcePort<1||sourcePort>65535||serverPort!==22)throw new Error('Lima control-plane SSH ports are invalid');
  if(!/^[A-Za-z0-9_.:-]{1,32}$/.test(interfaceName))throw new Error('Lima control-plane interface is invalid');
  return {transport:'tcp',sourceAddress,serverAddress,serverPort,interfaceName,gateway};
}

function stopVmAfterControlFailure(context,vm,message){
  if(!vmOwnershipValid(context,vm))throw new Error(`${message}; refusing fail-safe stop without a valid host ownership receipt`);
  const stopped=run('limactl',['stop','--force',vm],{allowFailure:true});
  if(stopped.status!==0)throw new Error(`${message}; fail-safe stop of the run-owned VM failed`);
  throw new Error(`${message}; the run-owned VM was stopped and can be recreated or deleted from its host ownership receipt`);
}

function configureGuestFirewall(runDir,context,vm){
  const expected=discoverLimaControlPlane(context,vm);
  context.controlPlanes||={};context.controlPlanes[vm]=expected;atomicJson(join(runDir,'protected/context.json'),context);
  const controlRule=expected.transport==='vsock'?'true':`sudo ufw allow in on ${shellQuote(expected.interfaceName)} from ${shellQuote(expected.sourceAddress)} to ${shellQuote(expected.serverAddress)} port ${expected.serverPort} proto tcp`;
  const firewall=`set -eu; sudo ufw --force reset >/dev/null; sudo ufw default deny incoming; sudo ufw default deny outgoing; sudo ufw allow in on lo; sudo ufw allow out on lo; ${controlRule}; sudo ufw --force enable`;
  try{lima(context,vm,['bash','-lc',firewall],{timeoutMs:30_000});}catch{stopVmAfterControlFailure(context,vm,'guest firewall application did not complete through the Lima control plane');}
  let actual=null,marker=false;
  try{actual=discoverLimaControlPlane(context,vm);marker=markerValid(context,vm);}catch{}
  if(!marker||JSON.stringify(actual)!==JSON.stringify(expected))stopVmAfterControlFailure(context,vm,'post-firewall Lima SSH/control-plane verification failed');
  const proofPath=join(runDir,'public/control-plane.json');const proof=existsSync(proofPath)?readJson(proofPath):{schemaVersion:'stepv2-capacity-control-plane-v1',vms:{}};
  proof.vms[shortHash(vm)]={verifiedAt:new Date().toISOString(),transport:expected.transport,sourceHash:shortHash(expected.sourceAddress),serverHash:shortHash(expected.serverAddress),gatewayHash:expected.gateway==='direct'?'direct':shortHash(expected.gateway),interfaceHash:shortHash(expected.interfaceName),sshPort:expected.serverPort,defaultInbound:'deny',defaultOutbound:'deny'};
  atomicJson(proofPath,proof);
}

async function installVmPackages(context) {
  const dbScript = `set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq ca-certificates curl postgresql-common
sudo install -d -m 0755 /usr/share/postgresql-common/pgdg
sudo curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc
. /etc/os-release
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq postgresql-18 postgresql-client-18 pgbouncer ufw
sudo sed -ri "s/^#?max_connections\s*=.*/max_connections = ${DB_SPEC.maxConnections}/; s/^#?listen_addresses\s*=.*/listen_addresses = '*'/" /etc/postgresql/18/main/postgresql.conf
sudo systemctl restart postgresql`;
  const appScript = `set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq ca-certificates curl nginx redis-server ufw
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y -qq nodejs
sudo npm install -g pm2
sudo systemctl disable --now redis-server >/dev/null 2>&1 || true`;
  const installs=await Promise.allSettled([
    limaAsync(context.dbVm,['bash','-lc',dbScript],{stdio:'inherit'}),
    limaAsync(context.appVm,['bash','-lc',appScript],{stdio:'inherit'}),
  ]);
  const failures=installs.filter(result=>result.status==='rejected');
  if(failures.length)throw new Error(`VM package installation failed: ${failures.map(result=>result.reason?.message||result.reason).join('; ')}`);
}

function vmPackagesReady(context) {
  const db=lima(context,context.dbVm,['bash','-lc','command -v psql >/dev/null && command -v pg_restore >/dev/null && command -v pgbouncer >/dev/null && command -v ufw >/dev/null'],{allowFailure:true});
  const app=lima(context,context.appVm,['bash','-lc','command -v node >/dev/null && command -v nginx >/dev/null && command -v redis-server >/dev/null && command -v ufw >/dev/null && command -v pm2 >/dev/null'],{allowFailure:true});
  return db.status===0&&app.status===0;
}

function vmIp(context, vm) {
  const output = String(lima(context, vm, ['hostname','-I']).stdout || '').trim();
  const addresses=output.split(/\s+/);
  const ip = addresses.find(value=>context.sharedNetworkPrefix&&value.startsWith(context.sharedNetworkPrefix))||addresses.find(value => /^(?:10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(value));
  if (!ip) throw new Error(`no private address found for ${vm}`);
  return ip;
}

function actualVm(name, expected) {
  const document = JSON.parse(runText('limactl',['list',name,'--json']));
  const actual = {cpus:Number(document.cpus),memoryGiB:Number(document.memory)/1073741824,diskGiB:Number(document.disk)/1073741824,vmType:document.vmType,arch:document.arch,status:document.status};
  if(actual.cpus!==expected.cpus||actual.memoryGiB!==expected.memoryGiB||actual.diskGiB!==expected.diskGiB)throw new Error(`${name} actual resources do not match the confirmed plan`);
  return actual;
}

function selectedHostDatabasePort(context,production){return productionUsesPooler(production)?context.dbPoolerPort:context.dbDirectPort;}

function tcpReachable(host,port,timeoutMs=750){
  return new Promise(resolveReachable=>{
    const socket=connect({host,port});let settled=false;
    const finish=value=>{if(settled)return;settled=true;socket.destroy();resolveReachable(value);};
    socket.once('connect',()=>finish(true));socket.once('error',()=>finish(false));socket.setTimeout(timeoutMs,()=>finish(false));
  });
}

async function assertHostLoopbackOnly(port){
  if(!Number.isInteger(port)||port<1024||port>65535)throw new Error('capacity database host-forward port is invalid');
  if(!await tcpReachable('127.0.0.1',port))throw new Error('capacity database host forward is not reachable on host loopback');
  const addresses=Object.values(networkInterfaces()).flat().filter(entry=>entry&&entry.family==='IPv4'&&!entry.internal).map(entry=>entry.address);
  for(const address of new Set(addresses))if(await tcpReachable(address,port))throw new Error('capacity database host forward is reachable through a non-loopback host interface');
}

function dbTunnelMapping(context,production){return `127.0.0.1:${context.appDbPort}:127.0.0.1:${selectedHostDatabasePort(context,production)}`;}

function loopbackListenerOnly(output,port){
  const rows=String(output||'').trim().split(/\r?\n/).filter(Boolean);
  if(!rows.length)return false;
  return rows.every(row=>{
    const fields=row.trim().split(/\s+/);const localEndpoint=fields[3];
    return localEndpoint===`127.0.0.1:${port}`||localEndpoint===`[::1]:${port}`;
  });
}

function dbTunnelProcessValid(context,production){
  const pid=Number(context.dbTunnelPid||0);if(!Number.isInteger(pid)||pid<1)return false;
  const probe=run('ps',['-p',String(pid),'-o','stat=,command='],{allowFailure:true});if(probe.status!==0)return false;
  const match=/^\s*(\S+)\s+([\s\S]+)$/.exec(String(probe.stdout||''));if(!match||match[1].startsWith('Z'))return false;
  const command=match[2];
  return command.includes('ssh')&&command.includes(dbTunnelMapping(context,production))&&command.includes(`lima-${context.appVm}`);
}

function stopDbTunnel(context,production){
  if(!dbTunnelProcessValid(context,production)){context.dbTunnelPid=null;return;}
  const pid=Number(context.dbTunnelPid);
  for(const [signal,waitMs] of [['SIGTERM',4_000],['SIGKILL',2_000]]){
    if(!dbTunnelProcessValid(context,production))break;
    try{process.kill(pid,signal);}catch(error){if(error?.code!=='ESRCH')throw error;}
    const deadline=Date.now()+waitMs;while(Date.now()<deadline&&dbTunnelProcessValid(context,production))Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,100);
  }
  if(dbTunnelProcessValid(context,production))throw new Error('run-bound database SSH tunnel did not stop after bounded TERM/KILL escalation');
  context.dbTunnelPid=null;
}

async function ensureDbTunnel(runDir,state,context){
  const production=state.plan.production;const hostPort=selectedHostDatabasePort(context,production);
  try{await assertHostLoopbackOnly(hostPort);}catch(error){
    if(!markerValid(context,context.dbVm)&&!vmOwnershipValid(context,context.dbVm))throw new Error(`database host isolation failed and the VM lacks run ownership proof: ${error.message}`);
    const stopped=run('limactl',['stop','--force',context.dbVm],{allowFailure:true});
    if(stopped.status!==0)throw new Error(`database host isolation failed and the run-bound database VM could not be stopped: ${error.message}`);
    throw new Error(`database host isolation failed; the run-bound database VM was stopped: ${error.message}`);
  }
  if(!dbTunnelProcessValid(context,production)){
    context.dbTunnelPid=null;
    const existing=lima(context,context.appVm,['sudo','ss','-H','-ltn',`sport = :${context.appDbPort}`],{allowFailure:true});
    if(String(existing.stdout||'').trim())throw new Error('application database tunnel port is occupied without the recorded run-bound SSH tunnel');
    const sshConfig=runText('limactl',['list',context.appVm,'--format','{{.SSHConfigFile}}']);
    if(!sshConfig||!existsSync(sshConfig))throw new Error('Lima application SSH config is unavailable for the private database tunnel');
    const alias=`lima-${context.appVm}`;const aliases=readFileSync(sshConfig,'utf8').split(/\r?\n/).map(line=>/^Host\s+(\S+)\s*$/.exec(line)?.[1]).filter(Boolean);
    if(!aliases.includes(alias))throw new Error('Lima application SSH alias does not match the run-bound VM');
    const child=spawn('ssh',['-F',sshConfig,'-N','-T','-o','BatchMode=yes','-o','ExitOnForwardFailure=yes','-o','ControlMaster=no','-o','ControlPath=none','-o','ServerAliveInterval=15','-o','ServerAliveCountMax=3','-R',dbTunnelMapping(context,production),alias],{detached:true,stdio:'ignore'});
    await new Promise((resolveSpawn,rejectSpawn)=>{child.once('spawn',resolveSpawn);child.once('error',rejectSpawn);});
    if(!Number.isInteger(child.pid)||child.pid<1)throw new Error('run-bound database SSH tunnel did not return a valid process identity');
    context.dbTunnelPid=child.pid;child.unref();atomicJson(join(runDir,'protected/context.json'),context);
  }
  const deadline=Date.now()+10_000;let listener='';
  while(Date.now()<deadline&&dbTunnelProcessValid(context,production)){
    const probe=lima(context,context.appVm,['sudo','ss','-H','-ltn',`sport = :${context.appDbPort}`],{allowFailure:true});listener=String(probe.stdout||'').trim();if(listener)break;
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,200);
  }
  if(!dbTunnelProcessValid(context,production)||!listener){stopDbTunnel(context,production);throw new Error('run-bound database SSH tunnel did not establish within its bounded deadline');}
  if(!loopbackListenerOnly(listener,context.appDbPort)){stopDbTunnel(context,production);throw new Error('application database tunnel is not bound exclusively to app-VM loopback');}
  atomicJson(join(runDir,'public/database-transport.json'),{
    schemaVersion:'stepv2-capacity-database-transport-v1',
    verifiedAt:new Date().toISOString(),
    hostForwardBind:'loopback-only',
    appEndpointBind:'loopback-only',
    mechanism:'run-bound authenticated SSH reverse tunnel',
    hostNonLoopbackReachable:false,
  });
  atomicJson(join(runDir,'protected/context.json'),context);
}

async function provision(runDir, state, context) {
  phaseStart(runDir, state, 'provisioning');
  try {
    context.dbDirectPort ||= availableLoopbackPort(45432);
    context.dbPoolerPort ||= availableLoopbackPort(46432);
    context.appDbPort ||= 15432;
    if (context.topologyRevision !== TOPOLOGY_REVISION) {
      for (const name of [context.appVm,context.dbVm]) {
        if (!limaExists(name)) continue;
        if (!markerValid(context,name)&&!vmOwnershipValid(context,name))throw new Error(`refusing to replace ${name} without the exact run marker or a valid host ownership receipt during topology upgrade`);
        run('limactl',['delete','--force',name]);
      }
      context.topologyRevision = TOPOLOGY_REVISION;
      context.vmOwnership={};
      atomicJson(join(runDir,'protected/context.json'),context);
    }
    for (const [name, spec, role] of [[context.appVm, state.plan.app, 'app'], [context.dbVm, DB_SPEC, 'db']]) {
      if(limaExists(name)&&!markerValid(context,name)){
        if(!vmOwnershipValid(context,name))throw new Error(`${name} is unmarked and lacks a valid host operator ownership receipt; refusing delete`);
        run('limactl',['delete','--force',name]);
      }
      if (!limaExists(name)) {
        const args = ['start', '--tty=false', `--name=${name}`, `--cpus=${spec.cpus}`, `--memory=${spec.memoryGiB}`, `--disk=${spec.diskGiB}`, '--mount-none'];
        if (role === 'app') args.push('--set',`.portForwards += [{"guestPort":80,"hostPort":${context.appPort},"hostIP":"127.0.0.1"}]`);
        if (role === 'db') {
          const poolerEnabled = productionUsesPooler(state.plan.production);
          const guestPort=poolerEnabled?6432:5432;
          const hostPort=poolerEnabled?context.dbPoolerPort:context.dbDirectPort;
          args.push('--set',`.portForwards += [{"guestPort":${guestPort},"hostPort":${hostPort},"hostIP":"127.0.0.1"}]`);
        }
        args.push('template:ubuntu-lts');
        run('limactl', args, {stdio: 'inherit'});
        recordVmOwnership(runDir,context,name);
        lima(context, name, ['bash','-lc',`printf '%s\\n' ${shellQuote(context.runId)} | sudo tee /etc/stepv2-capacity-run >/dev/null && sudo chmod 600 /etc/stepv2-capacity-run`]);
      }
      if (!markerValid(context, name)) throw new Error(`${name} exists without the exact ${context.runId} marker; refusing reuse`);
    }
    if(!vmPackagesReady(context))await installVmPackages(context);
    dbSql(context,`ALTER SYSTEM SET max_connections TO '${DB_SPEC.maxConnections}';\n`);
    lima(context,context.dbVm,['sudo','systemctl','restart','postgresql']);
    const configuredMax=Number(runText('limactl',['shell',context.dbVm,'--','sudo','-u','postgres','psql','-Atc',"SELECT current_setting('max_connections')"]));
    if(configuredMax!==DB_SPEC.maxConnections)throw new Error(`isolated PostgreSQL max_connections is ${configuredMax}; expected ${DB_SPEC.maxConnections}`);
    const settings=state.plan.production.dbRuntime?.settings||{};
    const settingNames=['shared_buffers','work_mem','effective_cache_size','random_page_cost','effective_io_concurrency','max_worker_processes','max_parallel_workers','max_parallel_workers_per_gather','jit'];
    const statements=[];
    for(const name of settingNames){const value=String(settings[name]??'');if(!/^[A-Za-z0-9. -]+$/.test(value))throw new Error(`production PostgreSQL setting ${name} has an unsafe/unreproducible value`);statements.push(`ALTER SYSTEM SET ${name} TO '${value.replaceAll("'","''")}';`);}
    if(statements.length){dbSql(context,`${statements.join('\n')}\n`);lima(context,context.dbVm,['sudo','systemctl','restart','postgresql']);const actual=JSON.parse(String(lima(context,context.dbVm,['sudo','-u','postgres','psql','-Atc',`SELECT json_object_agg(name,current_setting(name)) FROM pg_settings WHERE name=ANY(ARRAY[${settingNames.map(x=>`'${x}'`).join(',')}])`]).stdout||'{}'));const mismatches=settingNames.filter(name=>String(actual[name])!==String(settings[name]));state.plan.databaseSettings={expected:settings,actual,mismatches};if(mismatches.length)state.plan.productionDeviations.push(`PostgreSQL settings not reproduced: ${mismatches.join(', ')}`);saveState(runDir,state);}
    context.appIp = vmIp(context, context.appVm);
    context.dbGuestIp = vmIp(context, context.dbVm);
    context.dbIp='127.0.0.1';
    const actualApp=actualVm(context.appVm,state.plan.app);
    const actualDatabase=actualVm(context.dbVm,DB_SPEC);
    atomicJson(join(runDir, 'protected/context.json'), context);
    atomicJson(join(runDir, 'public/topology.json'), {
      app: {...actualApp, vmNameHash: shortHash(context.appVm), privateIpHash: shortHash(context.appIp),os:runText('limactl',['shell',context.appVm,'--','uname','-srmo']),node:runText('limactl',['shell',context.appVm,'--','node','--version'])},
      database: {...actualDatabase,maxConnections:DB_SPEC.maxConnections,vmNameHash: shortHash(context.dbVm), privateIpHash: shortHash(context.dbGuestIp),os:runText('limactl',['shell',context.dbVm,'--','uname','-srmo']),postgres:runText('limactl',['shell',context.dbVm,'--','psql','--version'])},
      limaVersion: runText('limactl', ['--version']), limaBackend: process.platform,
      generator: {platform: process.platform, arch: process.arch, node: process.version,hardware:runText('sh',['-c','sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m'])},
      swap:{app:runText('limactl',['shell',context.appVm,'--','bash','-lc',"swapon --show --noheadings | wc -l"]),database:runText('limactl',['shell',context.dbVm,'--','bash','-lc',"swapon --show --noheadings | wc -l"])},
    });
    phaseComplete(runDir, state, 'provisioning', {appMarker: true, dbMarker: true, actualSpecsRecorded: true});
  } catch (error) {
    phaseFailed(runDir, state, 'provisioning', error); throw error;
  }
}

function writeEffectiveEnv(evidencePath, outputPath, context, plan) {
  const production=plan.production;
  const values = parseDotenv(readFileSync(evidencePath, 'utf8'));
  const overrides = {
    NODE_ENV: 'production', PORT: '3002', HOST: '127.0.0.1',
    DATABASE_URL: `postgresql://capacity_user:${encodeURIComponent(context.dbPassword)}@${context.dbIp}:${context.appDbPort}/${context.dbName}?schema=public`,
    PEER_DATABASE_URL: '', PROD_DATABASE_URL:'', STAGING_DATABASE_URL:'', SESSION_TOKEN_SECRET: context.authSecret,
    CAPACITY_AUTH_SECRET: context.authSecret, CAPACITY_JWT_SECRET: context.authSecret,
    CAPACITY_MODE: 'true', CAPACITY_RUN_ID: context.runId, CAPACITY_DB_MARKER: context.dbMarker,
    CAPACITY_DB_HOST_ALLOWLIST: context.dbIp, CAPACITY_DB_NAME: context.dbName,
    CAPACITY_ATTESTATION_DIR:'/opt/stepv2-capacity/attestations',CAPACITY_EXPECTED_COMMIT_SHA:context.backendCommit,
    CAPACITY_OUTBOUND_DISABLED: 'true', APNS_PRODUCTION: 'false', APNS_KEY_PATH: '', APNS_SIGNING_KEY: '',
    APNS_KEY_ID: '', APNS_TEAM_ID: '', APNS_BUNDLE_ID: '', FCM_SERVICE_ACCOUNT: '',
    FCM_SERVICE_ACCOUNT_PATH: '', GOOGLE_APPLICATION_CREDENTIALS: '',
    S3_ACCESS_KEY_ID: '', S3_SECRET_ACCESS_KEY: '', S3_SESSION_TOKEN: '', S3_BUCKET: '', S3_AVATAR_PREFIX: '',
    AWS_ACCESS_KEY_ID: '', AWS_SECRET_ACCESS_KEY: '', AWS_SESSION_TOKEN: '',
    PUBLIC_BASE_URL: 'http://127.0.0.1', ASSET_BASE_URL: 'http://127.0.0.1',
    REDIS_URL: production.redis.enabled ? 'redis://127.0.0.1:6379/15' : '', CACHE_ENV_PREFIX: `capacity:${context.runId}:`,
    PRISMA_QUERY_EVENTS_ENABLED: 'false',
  };
  overrides.DB_POOL_MAX=String(plan.poolSize);
  if (productionUsesPooler(production)) {
    overrides.CAPACITY_DATABASE_SSL_DISABLED = 'true';
    overrides.CAPACITY_PGBOUNCER_ADMIN_URL = `postgresql://capacity_user:${encodeURIComponent(context.dbPassword)}@${context.dbIp}:${context.appDbPort}/pgbouncer`;
  }
  const isolatedUrlKeys=new Set(['DATABASE_URL','PEER_DATABASE_URL','REDIS_URL','PUBLIC_BASE_URL','ASSET_BASE_URL']);
  for (const key of Object.keys(values)) {
    if (/(MAIL|EMAIL|SMS|TWILIO|RESEND|SENDGRID|POSTMARK|WEBHOOK|ANALYTICS|SEGMENT|MIXPANEL|AMPLITUDE|CALLBACK|SLACK|DISCORD|ONESIGNAL|BRAZE|S3|AWS|R2|GCS|CLOUDINARY|OBJECT_STORAGE|UPLOAD).*(KEY|TOKEN|SECRET|URL|BUCKET|ENABLED|DISABLED)?/i.test(key)) overrides[key] = /_DISABLED$/i.test(key)?'true':/_ENABLED$/i.test(key)?'false':'';
    if(/_URL$/i.test(key)&&!isolatedUrlKeys.has(key))overrides[key]='';
  }
  Object.assign(values, overrides);
  writeFileSync(outputPath, `${Object.keys(values).sort().map(key => dotenvLine(key, values[key])).join('\n')}\n`, {mode: 0o600});
  chmodSync(outputPath, 0o600);
  return {keyCount: Object.keys(values).length, overrideKeys: Object.keys(overrides).sort()};
}

function acquireInputs(runDir, state, context) {
  phaseStart(runDir, state, 'input_acquisition');
  try {
    const evidence = join(runDir, 'protected/production.env.evidence');
    run('scp', ['-q', `${context.sshTarget}:${PROD_ENV_PATH}`, evidence]);
    chmodSync(evidence, 0o600);
    const localChecksum = sha256(evidence);
    const sourceChecksum = runText('ssh', ['-o','BatchMode=yes',context.sshTarget,'sha256sum',PROD_ENV_PATH]).split(/\s+/)[0];
    if (localChecksum !== sourceChecksum) throw new Error('production .env evidence checksum mismatch');
    const currentProduction = remoteInspection(context.sshTarget);
    if (currentProduction.envFileSha256 !== state.plan.production.envFileSha256 || currentProduction.materialHash !== state.plan.production.materialHash) {
      state.phases.discovery.status='pending'; state.phases.approval.status='pending';
      state.phases.discovery.error='production runtime/env changed after confirmation';
      saveState(runDir,state);
      throw new Error('production .env or material runtime configuration changed after confirmation; resume forces fresh discovery and a new RUN confirmation');
    }
    const nginxPath = join(runDir, 'protected/production-nginx.txt');
    const nginx = run('ssh', ['-o','BatchMode=yes',context.sshTarget,'nginx','-T']);
    writeFileSync(nginxPath, nginx.stdout, {mode: 0o600});
    const effective = join(runDir, 'protected/effective.env');
    const effectiveSummary = writeEffectiveEnv(evidence, effective, context, state.plan);
    const effectiveChecksum=sha256(effective);
    atomicJson(join(runDir, 'public/input-provenance.json'), {
      acquiredAt: new Date().toISOString(), sourceHash: state.plan.productionSourceHash,
      evidenceSha256: localChecksum, evidenceMode: (statSync(evidence).mode & 0o777).toString(8),
      backendCommit: state.plan.backendCommit, effective: {...effectiveSummary,sha256:effectiveChecksum,mode:(statSync(effective).mode&0o777).toString(8)},
    });
    phaseComplete(runDir, state, 'input_acquisition', {byteExact: true, checksum: localChecksum, effectiveChecksum, effectiveSeparate: true});
  } catch (error) { phaseFailed(runDir, state, 'input_acquisition', error); throw error; }
}

function databaseConnectionFromEvidence(runDir) {
  const values = parseDotenv(readFileSync(join(runDir, 'protected/production.env.evidence'), 'utf8'));
  const raw = values.DATABASE_URL || values.PROD_DATABASE_URL;
  if (!raw) throw new Error('production evidence contains no DATABASE_URL');
  const url = new URL(raw);
  if (!['postgres:','postgresql:'].includes(url.protocol)) throw new Error('production DATABASE_URL is not PostgreSQL');
  return url;
}

function postgresEnv(url) {
  const requestedMode = String(url.searchParams.get('sslmode') || '').toLowerCase();
  const sslmode = ['require','verify-ca','verify-full'].includes(requestedMode) ? requestedMode : 'require';
  return {...process.env, PGPASSWORD: decodeURIComponent(url.password), PGSSLMODE: sslmode, PGAPPNAME: 'stepv2-capacity-readonly'};
}

function productionReadOnlyScalar(psql, args, url, selectSql, options = {}) {
  if (!/^\s*SELECT\b/i.test(selectSql) || /;/.test(selectSql)) throw new Error('production scalar probe must be one SELECT statement');
  const output = runText(psql, [...args,'-XqAtc',`BEGIN TRANSACTION READ ONLY; ${selectSql}; ROLLBACK;`], {...options,env:postgresEnv(url)});
  const value = output.split(/\r?\n/).map(line=>line.trim()).find(line=>/^-?\d+$/.test(line));
  if (value == null) throw new Error('production read-only scalar probe returned no numeric value');
  return value;
}

async function dumpProduction(runDir, state) {
  phaseStart(runDir, state, 'dump');
  try {
    const threshold=Number(state.plan.safetyGates?.dumpActiveConnectionLimit);
    const configuredThreshold=configuredDumpActiveConnectionLimit();
    if(!Number.isInteger(threshold)||threshold!==configuredThreshold){
      state.phases.discovery.status='pending';state.phases.approval.status='pending';
      state.phases.discovery.error='production dump active-connection limit changed after confirmation';
      saveState(runDir,state);
      throw new Error('K6_PROD_DUMP_ACTIVE_CONNECTION_LIMIT changed after confirmation; resume forces fresh discovery and a new RUN confirmation');
    }
    const tools = pgTools();
    const url = databaseConnectionFromEvidence(runDir);
    const args = ['-h',url.hostname,'-p',url.port || '5432','-U',decodeURIComponent(url.username),'-d',decodeURIComponent(url.pathname.slice(1))];
    const loadText = productionReadOnlyScalar(tools.psql,args,url,"SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND state <> 'idle'");
    const active = Number(loadText);
    if (!Number.isInteger(active) || active > threshold) throw new Error(`production has ${loadText} active DB connections; dump threshold is ${threshold}`);
    const dumpPath = join(runDir, 'protected/production.dump');
    const startedAt = new Date().toISOString();
    const child=spawn(tools.pgDump,[...args,'--format=custom','--compress=6','--serializable-deferrable','--no-owner','--file',dumpPath],{env:postgresEnv(url),stdio:['ignore','ignore','pipe']});
    let stderr='';child.stderr.on('data',chunk=>{stderr+=chunk;if(stderr.length>16000)stderr=stderr.slice(-16000);});
    const closed=new Promise((resolveClose,rejectClose)=>{child.once('error',rejectClose);child.once('close',resolveClose);});
    const samples=[{at:startedAt,activeConnections:active}];
    const phaseDeadline=Math.min(Date.parse(state.plan.deadlineAt),Date.now()+2*60*60*1000);
    let abortedReason=null;
    while(child.exitCode===null){
      await Promise.race([closed,new Promise(resolveDelay=>setTimeout(resolveDelay,5000))]);
      if(child.exitCode!==null)break;
      const sampleText=productionReadOnlyScalar(tools.psql,args,url,"SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND state <> 'idle'",{timeoutMs:30_000});
      const count=Number(sampleText);samples.push({at:new Date().toISOString(),activeConnections:count});
      if(!Number.isInteger(count)||count>threshold)abortedReason=`production active connections ${sampleText} exceeded threshold ${threshold}`;
      if(Date.now()>=phaseDeadline)abortedReason='production dump exceeded its absolute run/phase watchdog';
      if(abortedReason){child.kill('SIGTERM');setTimeout(()=>{if(child.exitCode===null)child.kill('SIGKILL');},10_000).unref();break;}
    }
    const code=await closed;
    if(abortedReason||code!==0){rmSync(dumpPath,{force:true});atomicJson(join(runDir,'public/dump-abort.json'),{startedAt,abortedAt:new Date().toISOString(),reason:abortedReason||`pg_dump exited ${code}`,impactThreshold:threshold,loadSamples:samples});throw new Error(abortedReason||`pg_dump failed (${code}): ${stderr.slice(-4000)}`);}
    chmodSync(dumpPath, 0o600);
    const listing = run(tools.pgRestore, ['--list',dumpPath]);
    const tableData = String(listing.stdout).split('\n').filter(line => line.includes('TABLE DATA')).length;
    if (tableData < 1) throw new Error('production dump has no table data entries');
    atomicJson(join(runDir, 'public/dump-provenance.json'), {startedAt, endedAt: new Date().toISOString(), activeConnectionsAtStart: active, maximumActiveConnections:Math.max(...samples.map(x=>x.activeConnections)),impactThreshold: threshold, loadSamples:samples,sha256: sha256(dumpPath), bytes: statSync(dumpPath).size, tableDataEntries: tableData});
    phaseComplete(runDir, state, 'dump', {readOnly: true, consistent: true, readable: true, tableDataEntries: tableData, checksum: sha256(dumpPath)});
  } catch (error) { phaseFailed(runDir, state, 'dump', error); throw error; }
}

function dbSql(context, sql) {
  return lima(context, context.dbVm, ['sudo','-u','postgres','psql','--set=ON_ERROR_STOP=1'], {input: sql});
}

async function restoreDatabase(runDir, state, context) {
  phaseStart(runDir, state, 'restore');
  try {
    if (!markerValid(context, context.dbVm)) throw new Error('database VM run marker missing before restore');
    if (!/^stepv2_capacity_[a-z0-9_]+$/.test(context.dbName)) throw new Error('capacity database name is unsafe');
    const escapedPassword = context.dbPassword.replaceAll("'", "''");
    const setup = `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${context.dbName}' AND pid<>pg_backend_pid();\nDROP DATABASE IF EXISTS ${context.dbName};\nDROP ROLE IF EXISTS capacity_user;\nCREATE ROLE capacity_user LOGIN PASSWORD '${escapedPassword}';\nCREATE DATABASE ${context.dbName} OWNER capacity_user;\n`;
    dbSql(context, setup);
    const dump = createReadStream(join(runDir, 'protected/production.dump'));
    const restore = spawn('limactl', ['shell',context.dbVm,'--','sudo','-u','postgres','pg_restore','--exit-on-error','--no-owner','--role=capacity_user','--dbname',context.dbName], {stdio: ['pipe','pipe','pipe']});
    dump.pipe(restore.stdin);
    let stderr = ''; restore.stderr.on('data', chunk => { stderr += chunk; });
    const restoreWatchdog=setTimeout(()=>{restore.kill('SIGTERM');setTimeout(()=>restore.kill('SIGKILL'),10_000).unref();},Math.max(1,Math.min(Date.parse(state.plan.deadlineAt)-Date.now(),2*60*60*1000)));
    const code = await new Promise((resolveCode, reject) => { restore.on('error', reject); restore.on('close', resolveCode); });
    clearTimeout(restoreWatchdog);
    if (code !== 0) throw new Error(`pg_restore failed (${code}): ${stderr.slice(-4000)}`);
    dbSql(context, `\\connect ${context.dbName}\nCREATE TABLE IF NOT EXISTS capacity_run_marker (run_id text PRIMARY KEY, marker text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());\nTRUNCATE capacity_run_marker;\nINSERT INTO capacity_run_marker(run_id,marker) VALUES ('${context.runId}','${context.dbMarker}');\nGRANT SELECT ON capacity_run_marker TO capacity_user;\n`);
    lima(context, context.dbVm, ['bash','-lc',`printf '%s\\n' ${shellQuote(`host ${context.dbName} capacity_user 127.0.0.1/32 scram-sha-256`)} | sudo tee -a /etc/postgresql/18/main/pg_hba.conf >/dev/null && sudo systemctl reload postgresql`]);
    if (productionUsesPooler(state.plan.production)) {
      const observedMode=/^(session|transaction|statement)$/.test(String(state.plan.production.dbRuntime?.poolMode||''))?state.plan.production.dbRuntime.poolMode:'transaction';
      const observedConfig=state.plan.production.dbRuntime?.poolerTelemetry?.config||{};const integerSetting=(key,fallback)=>/^\d+$/.test(String(observedConfig[key]||''))?String(observedConfig[key]):String(fallback);const ignore=/^[A-Za-z0-9_, -]+$/.test(String(observedConfig.ignore_startup_parameters||''))?observedConfig.ignore_startup_parameters:'extra_float_digits';
      const reproduced={default_pool_size:integerSetting('default_pool_size',40),reserve_pool_size:integerSetting('reserve_pool_size',2),max_client_conn:integerSetting('max_client_conn',47),max_db_connections:integerSetting('max_db_connections',0),max_user_connections:integerSetting('max_user_connections',0),server_lifetime:integerSetting('server_lifetime',3600),server_idle_timeout:integerSetting('server_idle_timeout',600),query_timeout:integerSetting('query_timeout',0),client_idle_timeout:integerSetting('client_idle_timeout',0),server_connect_timeout:integerSetting('server_connect_timeout',15),server_login_retry:integerSetting('server_login_retry',15)};
      const observedDatabase=state.plan.production.dbRuntime?.poolerTelemetry?.database||{};
      const expectedDatabase={...observedDatabase,pool_size:String(state.plan.targetPooler?.disposablePoolSize??observedDatabase.pool_size??'')};
      const databaseOptions=[];for(const [sourceKey,targetKey] of [['pool_size','pool_size'],['reserve_pool','reserve_pool'],['max_connections','max_db_connections']])if(/^\d+$/.test(String(expectedDatabase[sourceKey]||'')))databaseOptions.push(`${targetKey}=${expectedDatabase[sourceKey]}`);if(/^(session|transaction|statement)$/.test(String(expectedDatabase.pool_mode||'')))databaseOptions.push(`pool_mode=${expectedDatabase.pool_mode}`);
      const pgbouncer = `[databases]\n${context.dbName} = host=127.0.0.1 port=5432 dbname=${context.dbName} user=capacity_user password=${context.dbPassword} ${databaseOptions.join(' ')}\n[pgbouncer]\nlisten_addr = 127.0.0.1\nlisten_port = 6432\nauth_type = scram-sha-256\nauth_file = /etc/pgbouncer/userlist.txt\nadmin_users = capacity_user\nstats_users = capacity_user\npool_mode = ${observedMode}\n${Object.entries(reproduced).map(([k,v])=>`${k} = ${v}`).join('\n')}\nignore_startup_parameters = ${ignore}\n`;
      lima(context, context.dbVm, ['sudo','tee','/etc/pgbouncer/pgbouncer.ini'], {input: pgbouncer});
      lima(context, context.dbVm, ['sudo','tee','/etc/pgbouncer/userlist.txt'], {input: `"capacity_user" "${context.dbPassword}"\n`});
      lima(context, context.dbVm, ['sudo','chown','postgres:postgres','/etc/pgbouncer/pgbouncer.ini','/etc/pgbouncer/userlist.txt']);lima(context, context.dbVm, ['sudo','chmod','600','/etc/pgbouncer/pgbouncer.ini','/etc/pgbouncer/userlist.txt']);
      lima(context, context.dbVm, ['sudo','systemctl','enable','pgbouncer']);
      lima(context, context.dbVm, ['sudo','systemctl','restart','pgbouncer']);
      const pgpassPath='/tmp/stepv2-capacity.pgpass';
      lima(context,context.dbVm,['bash','-lc',`umask 077; cat > ${pgpassPath}`],{input:`127.0.0.1:6432:*:capacity_user:${context.dbPassword}\n`});
      try {
        const serviceUser=runText('limactl',['shell',context.dbVm,'--','systemctl','show','pgbouncer','--property=User','--value']);if(serviceUser!=='postgres')throw new Error(`PgBouncer service user ${serviceUser||'unset'} is not the explicit postgres owner`);const configText=String(lima(context,context.dbVm,['env',`PGPASSFILE=${pgpassPath}`,'psql','-h','127.0.0.1','-p','6432','-U','capacity_user','-d','pgbouncer','-At','-F','\t','-c','SHOW CONFIG']).stdout||'');const actualConfig=Object.fromEntries(configText.trim().split('\n').map(line=>line.split('\t')).filter(parts=>parts.length>=2).map(parts=>[parts[0],parts[1]]));const databaseText=String(lima(context,context.dbVm,['env',`PGPASSFILE=${pgpassPath}`,'psql','-h','127.0.0.1','-p','6432','-U','capacity_user','-d','pgbouncer','-A','-F','\t','-c','SHOW DATABASES']).stdout||'');const databaseLines=databaseText.trim().split('\n');const headers=databaseLines.shift()?.split('\t')||[];const row=databaseLines.map(line=>line.split('\t')).find(parts=>parts[0]===context.dbName)||[];const actualDatabase=Object.fromEntries(headers.map((key,index)=>[key,row[index]??null]));const configMismatches=Object.entries(observedConfig).filter(([key,value])=>String(actualConfig[key]??'')!==String(value)).map(([key])=>key);const databaseMismatches=[['pool_size','pool_size'],['reserve_pool','reserve_pool'],['max_connections','max_connections'],['pool_mode','pool_mode']].filter(([source,target])=>expectedDatabase[source]!=null&&String(expectedDatabase[source])!==String(actualDatabase[target]??'')).map(([source])=>source);state.plan.pgbouncerReproduction={config:reproduced,poolMode:observedMode,ignoreStartupParameters:ignore,actualConfig:Object.fromEntries(Object.keys(observedConfig).map(key=>[key,actualConfig[key]??null])),databaseOptions,expectedDatabase:Object.fromEntries(['pool_size','reserve_pool','max_connections','pool_mode'].map(key=>[key,expectedDatabase[key]??null])),actualDatabase:Object.fromEntries(['pool_size','reserve_pool','max_connections','pool_mode'].map(key=>[key,actualDatabase[key]??null])),serviceUser,configMismatches,databaseMismatches};saveState(runDir,state);if(configMismatches.length||databaseMismatches.length)throw new Error(`PgBouncer settings did not match the approved target: ${[...configMismatches,...databaseMismatches.map(x=>`database.${x}`)].join(', ')}`);
      } finally { lima(context,context.dbVm,['rm','-f',pgpassPath],{allowFailure:true}); }
    }
    configureGuestFirewall(runDir,context,context.dbVm);
    const countsText = String(lima(context, context.dbVm, ['sudo','-u','postgres','psql','-d',context.dbName,'-Atc',`SELECT json_build_object('users',(SELECT count(*) FROM users),'races',(SELECT count(*) FROM races),'schemaMigrations',(SELECT count(*) FROM _prisma_migrations WHERE finished_at IS NOT NULL),'marker',(SELECT count(*) FROM capacity_run_marker WHERE run_id='${context.runId}'))`]).stdout || '').trim();
    const representativeCounts=JSON.parse(countsText);
    if(Number(representativeCounts.marker)!==1||Number(representativeCounts.users)<1||Number(representativeCounts.races)<1||Number(representativeCounts.schemaMigrations)<1)throw new Error('restored schema/representative row-count proof failed');
    atomicJson(join(runDir, 'public/restore.json'), {completedAt: new Date().toISOString(), destinationDatabaseHash: shortHash(context.dbName), dbVmHash: shortHash(context.dbVm), representativeCounts});
    phaseComplete(runDir, state, 'restore', {destinationMarker: true, streamedIntoVm: true});
  } catch (error) { phaseFailed(runDir, state, 'restore', error); throw error; }
}

function pgbouncerReproductionValid(state,context){
  if(!productionUsesPooler(state.plan.production))return true;
  const reproduction=state.plan.pgbouncerReproduction;
  const approvedTarget=Number(state.plan.targetPooler?.disposablePoolSize);
  if(!reproduction||!Number.isInteger(approvedTarget))return false;
  const pgpassPath=`/tmp/${context.runId}-verify-pgbouncer.pgpass`;
  const parseConfig=text=>Object.fromEntries(String(text||'').trim().split('\n').map(line=>line.split('\t')).filter(parts=>parts.length>=2).map(parts=>[parts[0],parts[1]]));
  try{
    lima(context,context.dbVm,['bash','-lc',`umask 077; cat > ${pgpassPath}`],{input:`127.0.0.1:6432:*:capacity_user:${context.dbPassword}\n`});
    const serviceUser=runText('limactl',['shell',context.dbVm,'--','systemctl','show','pgbouncer','--property=User','--value']);
    if(serviceUser!=='postgres')return false;
    const configText=lima(context,context.dbVm,['env',`PGPASSFILE=${pgpassPath}`,'psql','-h','127.0.0.1','-p','6432','-U','capacity_user','-d','pgbouncer','-At','-F','\t','-c','SHOW CONFIG']).stdout;
    const actualConfig=parseConfig(configText);
    const expectedConfig={...reproduction.config,pool_mode:reproduction.poolMode,ignore_startup_parameters:reproduction.ignoreStartupParameters};
    if(Object.entries(expectedConfig).some(([key,value])=>String(actualConfig[key]??'')!==String(value)))return false;
    const databaseText=String(lima(context,context.dbVm,['env',`PGPASSFILE=${pgpassPath}`,'psql','-h','127.0.0.1','-p','6432','-U','capacity_user','-d','pgbouncer','-A','-F','\t','-c','SHOW DATABASES']).stdout||'');
    const databaseLines=databaseText.trim().split('\n');const headers=databaseLines.shift()?.split('\t')||[];const row=databaseLines.map(line=>line.split('\t')).find(parts=>parts[0]===context.dbName)||[];const actualDatabase=Object.fromEntries(headers.map((key,index)=>[key,row[index]??null]));
    if(Number(actualDatabase.pool_size)!==approvedTarget)return false;
    return Object.entries(reproduction.expectedDatabase||{}).every(([key,value])=>value==null||String(actualDatabase[key]??'')===String(value));
  }catch{return false;}finally{lima(context,context.dbVm,['rm','-f',pgpassPath],{allowFailure:true});}
}

function restoredMarkerValid(state,context) {
  if(!markerValid(context,context.dbVm))return false;
  const query=`SELECT count(*) FROM capacity_run_marker WHERE run_id='${context.runId}' AND marker='${context.dbMarker}'`;
  const result=lima(context,context.dbVm,['sudo','-u','postgres','psql','-d',context.dbName,'-Atc',query],{allowFailure:true});
  return result.status===0&&String(result.stdout).trim()==='1'&&pgbouncerReproductionValid(state,context);
}

function provisionedTopologyValid(state,context) {
  if(context.topologyRevision!==TOPOLOGY_REVISION||!markerValid(context,context.appVm)||!markerValid(context,context.dbVm))return false;
  const result=lima(context,context.dbVm,['sudo','-u','postgres','psql','-Atc',"SELECT current_setting('max_connections')"],{allowFailure:true});
  try{return result.status===0&&Number(String(result.stdout).trim())===DB_SPEC.maxConnections&&actualVm(context.appVm,state.plan.app).status==='Running'&&actualVm(context.dbVm,DB_SPEC).status==='Running';}catch{return false;}
}

function backendHealthy(context,expectedWorkers=2) {
  const response=run('curl',['--silent','--fail','--max-time','3',`http://127.0.0.1:${context.appPort}/health`],{allowFailure:true});
  if(response.status!==0)return false;
  const processes=JSON.parse(String(lima(context,context.appVm,['pm2','jlist'],{allowFailure:true}).stdout||'[]')).filter(item=>item.name==='stepv2-capacity'&&item.pm2_env?.status==='online');
  return processes.length===expectedWorkers;
}
function remoteArtifactValid(runDir,context,localName,remote){const local=join(runDir,'protected',localName);if(!existsSync(local))return false;const probe=lima(context,context.appVm,['sha256sum',remote],{allowFailure:true});return probe.status===0&&String(probe.stdout).trim().split(/\s+/)[0]===sha256(local);}

function backendCheckoutReady(context,commit){
  const probe=lima(context,context.appVm,['bash','-lc',`test -f ${shellQuote(`${BACKEND_DIR}/${HELPER_PATH}`)} && test "$(cat ${shellQuote(`${BACKEND_DIR}/.capacity-source-commit`)} 2>/dev/null)" = ${shellQuote(commit)} && test "$(git -C ${shellQuote(BACKEND_DIR)} rev-parse HEAD 2>/dev/null)" = ${shellQuote(commit)} && git -C ${shellQuote(BACKEND_DIR)} diff --quiet HEAD --`],{allowFailure:true});
  return probe.status===0;
}

async function copyBackend(runDir, context, commit) {
  if (!markerValid(context, context.appVm)) throw new Error('application VM run marker missing before checkout');
  const reusable=lima(context,context.appVm,['bash','-lc',`test -f ${shellQuote(`${BACKEND_DIR}/${HELPER_PATH}`)} && test "$(cat ${shellQuote(`${BACKEND_DIR}/.capacity-source-commit`)} 2>/dev/null)" = ${shellQuote(commit)}`],{allowFailure:true}).status===0;
  if(!reusable){
    lima(context, context.appVm, ['sudo','rm','-rf',BACKEND_DIR]);
    lima(context, context.appVm, ['bash','-lc',`sudo install -d /opt/stepv2-capacity ${shellQuote(BACKEND_DIR)} && sudo chown -R "$(id -u):$(id -g)" /opt/stepv2-capacity`]);
    const archive = spawn('git', ['-C',context.backendRepo,'archive','--format=tar',commit], {stdio: ['ignore','pipe','pipe']});
    const extract = spawn('limactl', ['shell',context.appVm,'--','tar','-xf','-','-C',BACKEND_DIR], {stdio: ['pipe','pipe','pipe']});
    const copyTimeout=Math.max(1,Math.min(30*60*1000,activePhaseDeadlineMs===null?Infinity:activePhaseDeadlineMs-Date.now()));const watchdog=setTimeout(()=>{archive.kill('SIGTERM');extract.kill('SIGTERM');setTimeout(()=>{archive.kill('SIGKILL');extract.kill('SIGKILL');},10_000).unref();},copyTimeout);
    archive.stdout.pipe(extract.stdin);
    let errors = ''; archive.stderr.on('data', x => { errors += x; }); extract.stderr.on('data', x => { errors += x; });
    try{await Promise.all([
      new Promise((ok, bad) => { archive.on('error', bad); archive.on('close', code => code === 0 ? ok() : bad(new Error(`git archive failed: ${errors}`))); }),
      new Promise((ok, bad) => { extract.on('error', bad); extract.on('close', code => code === 0 ? ok() : bad(new Error(`backend extract failed: ${errors}`))); }),
    ]);}finally{clearTimeout(watchdog);}
    lima(context,context.appVm,['bash','-lc',`printf '%s\n' ${shellQuote(commit)} > ${shellQuote(`${BACKEND_DIR}/.capacity-source-commit`)} && chmod 600 ${shellQuote(`${BACKEND_DIR}/.capacity-source-commit`)}`]);
  }
  const originMain=runText('git',['-C',context.backendRepo,'rev-parse','refs/remotes/origin/main']);
  if(originMain!==commit)throw new Error('backend origin/main changed after approval; refusing to hydrate a different checkout commit');
  const bundle=join(runDir,'protected/backend-source.bundle');
  const remoteBundle=`/tmp/${context.runId}-backend-source.bundle`;
  rmSync(bundle,{force:true});
  try{
    run('git',['-C',context.backendRepo,'bundle','create',bundle,'refs/remotes/origin/main']);chmodSync(bundle,0o600);
    const heads=runText('git',['bundle','list-heads',bundle]);if(!heads.split(/\r?\n/).some(line=>line.startsWith(`${commit} `)))throw new Error('backend source bundle does not contain the approved origin/main commit');
    limaCopy(bundle,`${context.appVm}:${remoteBundle}`);lima(context,context.appVm,['chmod','600',remoteBundle]);
    lima(context,context.appVm,['bash','-lc',`cd ${shellQuote(BACKEND_DIR)} && rm -rf .git && git init -q && git fetch -q ${shellQuote(remoteBundle)} refs/remotes/origin/main && git reset --hard -q ${shellQuote(commit)} && git checkout -q --detach ${shellQuote(commit)}`]);
    if(!backendCheckoutReady(context,commit))throw new Error('hydrated backend checkout did not verify as clean approved origin/main');
  }finally{
    lima(context,context.appVm,['rm','-f',remoteBundle],{allowFailure:true});rmSync(bundle,{force:true});
  }
}

function ensureRuntimeArtifacts(runDir,context,{identities=false}={}){for(const [local,remote] of [[join(runDir,'protected/effective.env'),EFFECTIVE_ENV_PATH],...(identities?[[join(runDir,'protected/identities.ndjson'),'/opt/stepv2-capacity/identities.ndjson']]:[])]){if(!existsSync(local))throw new Error(`protected runtime artifact missing: ${shortHash(local)}`);const expected=sha256(local);const probe=lima(context,context.appVm,['sha256sum',remote],{allowFailure:true});const actual=probe.status===0?String(probe.stdout).trim().split(/\s+/)[0]:null;if(actual!==expected)limaCopy(local,`${context.appVm}:${remote}`);lima(context,context.appVm,['chmod','600',remote]);const verified=String(lima(context,context.appVm,['sha256sum',remote]).stdout).trim().split(/\s+/)[0];if(verified!==expected)throw new Error('remote runtime artifact hash did not revalidate');}}

function limaCopy(source, destination) {
  run('limactl', ['copy', source, destination]);
}

function helper(context, args, options = {}) {
  const command = `cd ${shellQuote(BACKEND_DIR)} && CAPACITY_EFFECTIVE_ENV_PATH=${shellQuote(EFFECTIVE_ENV_PATH)} node ${shellQuote(HELPER_PATH)} ${args.map(shellQuote).join(' ')}`;
  const result = lima(context, context.appVm, ['bash','-lc',command], options);
  const output = String(result.stdout || result.stderr || '').trim();
  if (!output) return {ok: result.status === 0};
  try { return JSON.parse(output.split('\n').at(-1)); }
  catch { throw new Error(`capacity helper returned non-JSON output: ${output.slice(-1000)}`); }
}

function redactedBackendEvidence(inspect, canary) {
  const safeInspect=JSON.parse(JSON.stringify(inspect));
  if(safeInspect.database?.host){safeInspect.database.hostHash=shortHash(safeInspect.database.host);delete safeInspect.database.host;}
  if(safeInspect.database?.serverAddress){safeInspect.database.serverAddressHash=shortHash(safeInspect.database.serverAddress);delete safeInspect.database.serverAddress;}
  if(safeInspect.redis?.host){safeInspect.redis.hostHash=shortHash(safeInspect.redis.host);delete safeInspect.redis.host;}
  if(safeInspect.pooler?.host){safeInspect.pooler.hostHash=shortHash(safeInspect.pooler.host);delete safeInspect.pooler.host;}
  const safeCanary={...canary};
  if(safeCanary.authenticatedUserId){safeCanary.authenticatedUserHash=shortHash(safeCanary.authenticatedUserId);delete safeCanary.authenticatedUserId;}
  return {inspect:safeInspect,canary:safeCanary};
}

async function prepareBackendCheckout(runDir, state, context, commit) {
  if (!restoredMarkerValid(state,context)) throw new Error('run-bound database marker failed immediately before backend write-capable setup');
  await copyBackend(runDir, context, commit);
  lima(context,context.appVm,['install','-d','-m','700','/opt/stepv2-capacity/attestations']);
  ensureRuntimeArtifacts(runDir,context);
  const dependenciesReady=lima(context,context.appVm,['bash','-lc',`cd ${shellQuote(BACKEND_DIR)} && test -d node_modules/@prisma/client && test -d node_modules/express`],{allowFailure:true}).status===0;
  if(!dependenciesReady)lima(context, context.appVm, ['bash','-lc',`cd ${shellQuote(BACKEND_DIR)} && npm ci --omit=dev && npx prisma generate`], {stdio: 'inherit'});
  const destination = helper(context, ['inspect','--json']);
  if (destination.ok !== true || destination.database?.name !== context.dbName || Number(destination.database?.maxConnections)!==DB_SPEC.maxConnections) {
    const proof={helperOk:destination.ok===true,databaseNameMatches:destination.database?.name===context.dbName,maxConnections:Number(destination.database?.maxConnections),expectedMaxConnections:DB_SPEC.maxConnections,runIdMatches:destination.runId===context.runId};
    throw new Error(`capacity destination proof failed immediately before migrations (${JSON.stringify(proof)})`);
  }
  if (!restoredMarkerValid(state,context)) throw new Error('run-bound database marker failed immediately before migrations');
  lima(context, context.appVm, ['bash','-lc',`cd ${shellQuote(BACKEND_DIR)} && npx prisma migrate deploy`], {stdio: 'inherit'});
}

async function sanitize(runDir, state, context) {
  phaseStart(runDir, state, 'sanitization');
  try {
    await prepareBackendCheckout(runDir, state, context, state.plan.backendCommit);
    if (!restoredMarkerValid(state,context)) throw new Error('run-bound database marker failed immediately before sanitization');
    const result = helper(context, ['sanitize','--run-id',context.runId,'--json']);
    const verified = helper(context, ['verify-sanitized','--scope','baseline','--run-id',context.runId,'--json']);
    if (result.ok !== true || verified.ok !== true) throw new Error('backend sanitization did not verify');
    atomicJson(join(runDir, 'public/sanitization.json'), {result, verified});
    phaseComplete(runDir, state, 'sanitization', {deviceTokens: 0, outboundDisabled: true, inheritedQueueCleared: true});
  } catch (error) { phaseFailed(runDir, state, 'sanitization', error); throw error; }
}

function inflate(runDir, state, context) {
  phaseStart(runDir, state, 'inflation');
  try {
    const workload=runWorkload(state);
    if (!restoredMarkerValid(state,context)) throw new Error('run-bound database marker failed immediately before inflation');
    const remoteOutput = '/opt/stepv2-capacity/identities.ndjson';
    const result = helper(context, ['inflate','--run-id',context.runId,'--users',String(workload.users),'--seed',String(context.seed),'--output',remoteOutput,'--json']);
    const verified = helper(context, ['verify-inflation','--run-id',context.runId,'--users',String(workload.users),'--json']);
    if (result.ok !== true || verified.ok !== true) throw new Error('inflated capacity corpus did not verify');
    const localOutput = join(runDir, 'protected/identities.ndjson');
    limaCopy(`${context.appVm}:${remoteOutput}`, localOutput);
    chmodSync(localOutput, 0o600);
    atomicJson(join(runDir, 'public/inflation.json'), {result: {...result, output: undefined}, verified, identityFileSha256: sha256(localOutput)});
    phaseComplete(runDir, state, 'inflation', {users: workload.users, membershipRange: [workload.minRaces,workload.maxRaces], tokens: 'capacity-only',identityChecksum:sha256(localOutput)});
  } catch (error) { phaseFailed(runDir, state, 'inflation', error); throw error; }
}

function refreshCapacityTokens(runDir, context, state) {
  const workload=runWorkload(state);
  const remoteOutput = '/opt/stepv2-capacity/identities.ndjson';
  const refreshed = helper(context, ['inflate','--run-id',context.runId,'--users',String(workload.users),'--seed',String(context.seed),'--output',remoteOutput,'--json']);
  if (refreshed.ok !== true) throw new Error('capacity token refresh failed');
  const localOutput = join(runDir,'protected/identities.ndjson');
  const temporary = `${localOutput}.refresh`;
  limaCopy(`${context.appVm}:${remoteOutput}`,temporary);
  chmodSync(temporary,0o600);
  renameSync(temporary,localOutput);
  state.phases.inflation.postconditions.identityChecksum=sha256(localOutput);
  saveState(runDir,state);
}

function nginxConfig(context, production) {
  const connections = Number(production.nginx?.workerConnections || 768);
  const rlimit = Number(production.nginx?.workerRlimit || 65535);
  const workers = /^(?:auto|\d+)$/.test(String(production.nginx?.workerProcesses || '')) ? production.nginx.workerProcesses : 'auto';
  const proxyVersion = /^(?:1\.0|1\.1)$/.test(String(production.nginx?.proxyHttpVersion || '')) ? production.nginx.proxyHttpVersion : '1.1';
  if (!Number.isInteger(connections) || connections < 128 || !Number.isInteger(rlimit) || rlimit < connections) throw new Error('discovered nginx limits are invalid');
  return `user www-data;\nworker_processes ${workers};\nworker_rlimit_nofile ${rlimit};\nevents { worker_connections ${connections}; }\nhttp {\n  access_log /var/log/nginx/capacity-access.log;\n  error_log /var/log/nginx/capacity-error.log warn;\n  upstream stepv2_capacity { server 127.0.0.1:3002; keepalive 64; }\n  server { listen 80 default_server; server_name capacity.invalid;\n    location / { proxy_http_version ${proxyVersion}; proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr; proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header Connection ""; proxy_pass http://stepv2_capacity; }\n  }\n}\n`;
}

function productionRedisBinary(context, productionVersion) {
  if(!/^7\.\d+\.\d+$/.test(productionVersion))throw new Error(`production Redis version ${productionVersion||'unknown'} is not a supported reproducible Redis 7 release`);
  const prefix=`/opt/stepv2-capacity/redis-${productionVersion}`;
  const binary=`${prefix}/bin/redis-server`;
  const ready=lima(context,context.appVm,[binary,'--version'],{allowFailure:true});
  if(ready.status===0&&new RegExp(`v=${productionVersion.replaceAll('.','\\.')}(?:\\s|$)`).test(String(ready.stdout)))return binary;
  const install=`set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential ca-certificates curl
build_dir="$(mktemp -d /tmp/stepv2-redis-build.XXXXXX)"
curl -fsSLo "$build_dir/redis.tgz" ${shellQuote(`https://download.redis.io/releases/redis-${productionVersion}.tar.gz`)}
tar -xzf "$build_dir/redis.tgz" -C "$build_dir" --strip-components=1
make -C "$build_dir" -j2 BUILD_TLS=no
sudo make -C "$build_dir" install PREFIX=${shellQuote(prefix)}`;
  lima(context,context.appVm,['bash','-lc',install],{stdio:'inherit',timeoutMs:30*60*1000});
  const installed=lima(context,context.appVm,[binary,'--version']);
  if(!new RegExp(`v=${productionVersion.replaceAll('.','\\.')}(?:\\s|$)`).test(String(installed.stdout)))throw new Error('isolated Redis exact-version installation did not verify');
  return binary;
}

async function startBackend(runDir, state, context) {
  phaseStart(runDir, state, 'backend_startup');
  try {
    if(!backendCheckoutReady(context,state.plan.backendCommit))await prepareBackendCheckout(runDir,state,context,state.plan.backendCommit);ensureRuntimeArtifacts(runDir,context,{identities:true});lima(context,context.appVm,['install','-d','-m','700','/opt/stepv2-capacity/attestations']);
    let redisRuntime = null;
    if (state.plan.production.redis.enabled) {
      const productionVersion=String(state.plan.production.redis.version||'');
      const redisBinary=productionRedisBinary(context,productionVersion);
      const maximum = Number(state.plan.production.redis.maxMemoryBytes || 0);
      const policy = state.plan.production.redis.maxMemoryPolicy || 'noeviction';
      const redisDataDir='/var/lib/redis/stepv2-capacity';
      const settings = `bind 127.0.0.1\nprotected-mode yes\nport 6379\ndatabases 16\nmaxmemory ${maximum}\nmaxmemory-policy ${policy}\nsave ""\nappendonly no\ndir ${redisDataDir}\ndbfilename capacity.rdb\nlogfile ""\n`;
      lima(context, context.appVm, ['sudo','tee','/etc/redis/redis.conf'], {input: settings});
      lima(context,context.appVm,['sudo','chown','redis:redis','/etc/redis/redis.conf']);
      lima(context,context.appVm,['sudo','chmod','640','/etc/redis/redis.conf']);
      lima(context,context.appVm,['sudo','install','-d','-o','redis','-g','redis','-m','750','/var/lib/redis']);
      lima(context,context.appVm,['sudo','install','-d','-o','redis','-g','redis','-m','750',redisDataDir]);
      lima(context, context.appVm, ['sudo','systemctl','disable','redis-server'],{allowFailure:true,timeoutMs:15_000});
      lima(context, context.appVm, ['sudo','systemctl','kill','--kill-whom=all','--signal=SIGKILL','redis-server'],{allowFailure:true,timeoutMs:15_000});
      const stopPrior=`pid_file=/tmp/stepv2-capacity-redis.pid; if test -r "$pid_file"; then pid="$(cat "$pid_file")"; case "$pid" in ''|*[!0-9]*) exit 1;; esac; actual="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"; if test "$actual" = ${shellQuote(redisBinary)}; then sudo kill "$pid"; fi; fi`;
      lima(context,context.appVm,['bash','-lc',stopPrior],{allowFailure:true,timeoutMs:15_000});
      lima(context,context.appVm,['sudo','systemctl','stop','stepv2-capacity-redis.service'],{allowFailure:true,timeoutMs:15_000});
      lima(context,context.appVm,['sudo','pkill','-KILL','-x','redis-server'],{allowFailure:true,timeoutMs:15_000});
      const redisPortProbe=lima(context,context.appVm,['sudo','ss','-H','-ltn','sport = :6379'],{timeoutMs:15_000});
      if(String(redisPortProbe.stdout).trim())throw new Error('Redis loopback port remained occupied after run-VM-scoped service cleanup');
      const redisUnit=`[Unit]\nDescription=StepV2 run-bound capacity Redis\nAfter=network.target\n\n[Service]\nType=simple\nUser=redis\nGroup=redis\nWorkingDirectory=/var/lib/redis\nExecStart=${redisBinary} /etc/redis/redis.conf --daemonize no\nRestart=no\nNoNewPrivileges=true\nPrivateTmp=true\n\n[Install]\nWantedBy=multi-user.target\n`;
      lima(context,context.appVm,['sudo','tee','/etc/systemd/system/stepv2-capacity-redis.service'],{input:redisUnit,timeoutMs:15_000});
      lima(context,context.appVm,['sudo','chmod','644','/etc/systemd/system/stepv2-capacity-redis.service']);
      lima(context,context.appVm,['sudo','systemctl','daemon-reload'],{timeoutMs:15_000});
      lima(context,context.appVm,['sudo','systemctl','start','stepv2-capacity-redis.service'],{timeoutMs:15_000});
      let activeProbe={status:1,stdout:''};
      const redisReadyDeadline=Date.now()+10_000;
      while(Date.now()<redisReadyDeadline){
        activeProbe=lima(context,context.appVm,['systemctl','is-active','stepv2-capacity-redis.service'],{allowFailure:true,timeoutMs:5_000});
        if(activeProbe.status===0&&String(activeProbe.stdout).trim()==='active')break;
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,250);
      }
      if(activeProbe.status!==0||String(activeProbe.stdout).trim()!=='active'){
        const serviceProbe=lima(context,context.appVm,['systemctl','show','stepv2-capacity-redis.service','--property=Result','--property=ExecMainCode','--property=ExecMainStatus','--value'],{allowFailure:true,timeoutMs:15_000});
        const fields=String(serviceProbe.stdout||'').trim().split(/\r?\n/).filter(value=>/^[A-Za-z0-9_-]+$/.test(value)).slice(0,3);
        const journalProbe=lima(context,context.appVm,['journalctl','-u','stepv2-capacity-redis.service','--no-pager','-n','40'],{allowFailure:true,timeoutMs:15_000});
        const journal=String(journalProbe.stdout||journalProbe.stderr||'');
        const directive=/>>>\s*['"]?([a-z][a-z0-9_-]*)/i.exec(journal)?.[1]?.toLowerCase();
        const reason=/Permission denied/i.test(journal)?'permission':/Address already in use/i.test(journal)?'address-in-use':/Bad directive|wrong number of arguments|FATAL CONFIG FILE ERROR/i.test(journal)?`configuration-${directive||'unknown-directive'}`:/WorkingDirectory|CHDIR/i.test(journal)?'working-directory':/No such file or directory/i.test(journal)?'missing-file':'unclassified';
        throw new Error(`exact-version capacity Redis service did not become active (service result: ${fields.join('/')||'unavailable'}; classified cause: ${reason})`);
      }
      redisRuntime = {version: runText('limactl',['shell',context.appVm,'--',redisBinary,'--version']), maxMemoryBytes: maximum, maxMemoryPolicy: policy};
      const localMajor=/v=(\d+)/.exec(redisRuntime.version)?.[1];
      const productionMajor=productionVersion.split('.')[0];
      if(!localMajor||localMajor!==productionMajor)throw new Error(`isolated Redis major (${localMajor||'unknown'}) does not match production (${productionMajor||'unknown'})`);
    }
    const config = nginxConfig(context,state.plan.production);
    lima(context, context.appVm, ['sudo','tee','/etc/nginx/nginx.conf'], {input: config});
    lima(context, context.appVm, ['sudo','nginx','-t']);
    lima(context, context.appVm, ['sudo','systemctl','restart','nginx']);
    configureGuestFirewall(runDir,context,context.appVm);
    const memoryRestart=Number(state.plan.production.workers[0].memoryRestart);
    const memoryOption=memoryRestart>0?` --max-memory-restart ${memoryRestart}`:'';
    const start = `cd ${shellQuote(BACKEND_DIR)} && CAPACITY_EFFECTIVE_ENV_PATH=${shellQuote(EFFECTIVE_ENV_PATH)} pm2 delete stepv2-capacity >/dev/null 2>&1 || true; CAPACITY_EFFECTIVE_ENV_PATH=${shellQuote(EFFECTIVE_ENV_PATH)} pm2 start ${shellQuote(SERVER_PATH)} --name stepv2-capacity -i ${state.plan.workers} --time${memoryOption} && pm2 save`;
    lima(context, context.appVm, ['bash','-lc',start], {stdio: 'inherit'});
    const deadline = Date.now() + 60_000;
    let healthy = false;
    while (Date.now() < deadline) {
      const response = run('curl', ['--silent','--fail','--max-time','3',`http://127.0.0.1:${context.appPort}/health`], {allowFailure: true});
      if (response.status === 0) { healthy = true; break; }
      await new Promise(resolveDelay => setTimeout(resolveDelay, 1000));
    }
    if (!healthy) {
      const guestHealth=lima(context,context.appVm,['curl','--silent','--fail','--max-time','3','http://127.0.0.1/health'],{allowFailure:true,timeoutMs:10_000});
      const directHealth=lima(context,context.appVm,['curl','--silent','--fail','--max-time','3','http://127.0.0.1:3002/health'],{allowFailure:true,timeoutMs:10_000});
      const directListener=lima(context,context.appVm,['sudo','ss','-H','-ltn','sport = :3002'],{allowFailure:true,timeoutMs:10_000});
      const nginxState=lima(context,context.appVm,['systemctl','is-active','nginx'],{allowFailure:true,timeoutMs:10_000});
      let processSummary={online:0,restarts:0};
      try{const entries=JSON.parse(String(lima(context,context.appVm,['pm2','jlist'],{allowFailure:true,timeoutMs:10_000}).stdout||'[]')).filter(item=>item.name==='stepv2-capacity');processSummary={online:entries.filter(item=>item.pm2_env?.status==='online').length,restarts:entries.reduce((sum,item)=>sum+Number(item.pm2_env?.restart_time||0),0)};}catch{}
      const startupLogs=lima(context,context.appVm,['pm2','logs','stepv2-capacity','--nostream','--lines','120'],{allowFailure:true,timeoutMs:10_000});
      const startupText=`${startupLogs.stdout||''}\n${startupLogs.stderr||''}`;
      const startupClassification=/capacity_backend_started/.test(startupText)?'started':/capacity database marker|marker/i.test(startupText)?'database-marker':/ECONN|timeout|connect|database/i.test(startupText)?'database-connectivity':/capacity_backend_start_failed/.test(startupText)?'startup-failed-other':'no-startup-event';
      let startupError=null;
      for(const line of startupText.split(/\r?\n/)){
        const start=line.indexOf('{"event":"capacity_backend_start_failed"');if(start<0)continue;
        try{const parsed=JSON.parse(line.slice(start));startupError=String(parsed.error||'').replace(/(?:postgres(?:ql)?|redis):\/\/\S+/gi,'[redacted-url]').replace(/\b(?:\d{1,3}\.){3}\d{1,3}\b/g,'[redacted-address]').replace(/\/[A-Za-z0-9_.\/-]+/g,'[redacted-path]').replace(new RegExp(context.runId.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'),'g'),'[redacted-run]').replace(/\b[A-Za-z0-9_-]{32,}\b/g,'[redacted-value]').slice(0,300);}catch{}
      }
      const diagnostic={guestNginxHealth:guestHealth.status===0,directBackendHealth:directHealth.status===0,directListener:Boolean(String(directListener.stdout).trim()),nginxActive:String(nginxState.stdout).trim()==='active',pm2Online:processSummary.online,pm2Restarts:processSummary.restarts,startupClassification,startupError};
      throw new Error(`${state.plan.workers}-worker backend did not become healthy through nginx (${JSON.stringify(diagnostic)})`);
    }
    const inspect = helper(context, ['inspect','--json']);
    const profile=state.plan.clientProfile;
    const canary = helper(context, ['canary','--base-url','http://127.0.0.1','--identity-file','/opt/stepv2-capacity/identities.ndjson','--app-version',profile.appVersion,'--platform',profile.platform,'--client-features',profile.clientFeatures,'--user-agent',profile.userAgent,'--timezone',profile.timezone,'--release-channel',profile.releaseChannel,'--json']);
    if (inspect.ok !== true || canary.ok !== true) throw new Error('backend inspect/canary failed');
    if(productionUsesPooler(state.plan.production)&&inspect.pooler?.enabled!==true)throw new Error('recreated PgBouncer admin telemetry did not validate before load');
    if(Number(inspect.database?.applicationPoolPerWorker)!==state.plan.poolSize)throw new Error('backend database pool size did not match the approved plan');
    const attestation=helper(context,['attest-workers','--run-id',context.runId,'--expected-workers',String(state.plan.workers),'--json']);if(attestation.ok!==true||attestation.authenticated!==true||attestation.allLive!==true||attestation.allMatched!==true||attestation.commitSha!==state.plan.backendCommit||attestation.effectiveEnvSha256!==sha256(join(runDir,'protected/effective.env')))throw new Error(`${state.plan.workers}-worker startup attestation failed`);
    const pm2 = JSON.parse(String(lima(context, context.appVm, ['pm2','jlist']).stdout || '[]')).filter(item => item.name === 'stepv2-capacity');
    if (pm2.length !== state.plan.workers || new Set(pm2.map(item => String(item.pm2_env?.NODE_APP_INSTANCE))).size !== state.plan.workers) throw new Error(`PM2 did not launch exactly ${state.plan.workers} distinct workers`);
    const startupLogs=lima(context,context.appVm,['pm2','logs','stepv2-capacity','--nostream','--lines','300'],{allowFailure:true});
    const startupText=`${startupLogs.stdout||''}\n${startupLogs.stderr||''}`;
    const missingSchedulerProof=[];if(!/"nodeAppInstance":"0"/.test(startupText))missingSchedulerProof.push('owner-0');for(let index=1;index<state.plan.workers;index+=1)if(!new RegExp(`Skipping cron scheduling on NODE_APP_INSTANCE=${index}`).test(startupText))missingSchedulerProof.push(`skip-${index}`);if(missingSchedulerProof.length)throw new Error(`PM2 scheduler ownership proof failed: ${missingSchedulerProof.join(',')}`);
    const redacted=redactedBackendEvidence(inspect,canary);
    atomicJson(join(runDir, 'public/backend.json'), {...redacted, workers: pm2.map(item => ({pid:item.pid, instance:String(item.pm2_env?.NODE_APP_INSTANCE), status:item.pm2_env?.status})),workerAttestation:{schemaVersion:attestation.schemaVersion,commitSha:attestation.commitSha,effectiveEnvSha256:attestation.effectiveEnvSha256,authenticated:attestation.authenticated,allLive:attestation.allLive,allMatched:attestation.allMatched,workers:attestation.workers?.map(worker=>({workerInstance:worker.workerInstance,runtimeFingerprint:worker.runtimeFingerprint,authenticated:worker.authenticated,live:worker.live,matchesRuntime:worker.matchesRuntime}))}, schedulerOwnership:{instance0Owner:true,skippedInstances:Array.from({length:state.plan.workers-1},(_,index)=>index+1),scheduledWorkers:['race-resolution','resolution-post-tasks']}, nginxPath: `${state.plan.production.nginx?.proxyHttpVersion || '1.1'} loopback-forwarded nginx to PM2`, poolSize: state.plan.poolSize, redis: redisRuntime});
    phaseComplete(runDir, state, 'backend_startup', {healthy: true, workers: state.plan.workers, poolSize: state.plan.poolSize, canary: true, outboundDefaultDeny: true});
  } catch (error) { phaseFailed(runDir, state, 'backend_startup', error); throw error; }
}

function verifyBackendRuntime(runDir,state,context){try{if(!backendCheckoutReady(context,state.plan.backendCommit)||!remoteArtifactValid(runDir,context,'effective.env',EFFECTIVE_ENV_PATH)||!remoteArtifactValid(runDir,context,'identities.ndjson','/opt/stepv2-capacity/identities.ndjson'))return false;const inspect=helper(context,['inspect','--json']);const attestation=helper(context,['attest-workers','--run-id',context.runId,'--expected-workers',String(state.plan.workers),'--json']);const pm2=JSON.parse(String(lima(context,context.appVm,['pm2','jlist']).stdout||'[]')).filter(item=>item.name==='stepv2-capacity'&&item.pm2_env?.status==='online');const expectedMemory=Number(state.plan.production.workers[0]?.memoryRestart||0);const pm2Matches=pm2.every(item=>String(item.pm2_env?.pm_exec_path||'').endsWith(SERVER_PATH)&&Number(item.pm2_env?.max_memory_restart||0)===expectedMemory);return inspect.ok===true&&Number(inspect.database?.applicationPoolPerWorker)===state.plan.poolSize&&attestation.ok===true&&attestation.authenticated===true&&attestation.allLive===true&&attestation.allMatched===true&&attestation.commitSha===state.plan.backendCommit&&attestation.effectiveEnvSha256===sha256(join(runDir,'protected/effective.env'))&&pm2.length===state.plan.workers&&pm2Matches&&new Set(pm2.map(item=>String(item.pm2_env?.NODE_APP_INSTANCE))).size===state.plan.workers&&(!productionUsesPooler(state.plan.production)||inspect.pooler?.enabled===true);}catch{return false;}}

function barrier(context, timeoutSeconds) {
  const result = helper(context, ['barrier','--timeout-seconds',String(timeoutSeconds),'--json'],{timeoutMs:(timeoutSeconds+30)*1000,allowFailure:true});
  return result;
}
function requireCleanBarrier(result){if(result.ok!==true||result.successful!==true||result.drained!==true||result.queueEmpty!==true||Number(result.permanentFailureCount||0)!==0)throw new Error(`queue barrier failed (${result.drainState||'unknown'}): pending=${Number(result.pending||0)} permanentFailures=${Number(result.permanentFailureCount||0)}`);return result;}

function clearTrafficErrorLogs(context){
  lima(context,context.appVm,['pm2','flush']);
  lima(context,context.appVm,['sudo','truncate','-s','0','/var/log/nginx/capacity-error.log']);
}

function initializeTrafficDiagnostics(context){
  lima(context,context.appVm,['pm2','reset','stepv2-capacity']);
  clearTrafficErrorLogs(context);
}

function durationTimeout(plan) {
  const flags = plan.production.safeFlags || {};
  const debounce = Number(flags.RACE_RESOLVE_DEBOUNCE_MS || 30_000);
  const quietPeriod = Number(flags.RACE_QUEUE_V2_QUIET_PERIOD_MS || 0);
  const resolutionLease = 30_000;
  const retryBackoffTotal = 1_000 + 5_000 + 30_000;
  const postTaskLease = 30_000;
  return Math.max(120, Math.ceil((debounce + quietPeriod + resolutionLease + retryBackoffTotal + postTaskLease) / 1000));
}

function localDateInTimeZone(date,timeZone){
  const parts=Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date).filter(part=>part.type!=='literal').map(part=>[part.type,part.value]));
  if(!/^\d{4}$/.test(parts.year||'')||!/^\d{2}$/.test(parts.month||'')||!/^\d{2}$/.test(parts.day||''))throw new Error('discovered client timezone did not produce a valid local date');
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function k6Environment(runDir, context, state, {phase, rps, seconds, repeat, vuMultiplier, summaryPath,logicalBase,logicalWindow}) {
  const now = Date.now();
  let epoch = Math.floor(now / 300_000) * 300_000 + 120_000;
  if (epoch > now) epoch -= 300_000;
  return {
    ...process.env, PHASE: phase, RPS: String(rps), DURATION: `${seconds}s`, DURATION_SECONDS: String(seconds),
    BASE_URL: `http://127.0.0.1:${context.appPort}`, RUN_ID: context.runId, RUN_SEED: String(context.seed),
    REPEAT_INDEX: String(repeat), VU_MULTIPLIER: String(vuMultiplier),
    IDENTITY_PATH: join(runDir, 'protected/identities.ndjson'), MIX_PATH: join(runDir, 'public/traffic-mix.json'), REGISTRY_PATH:join(runDir,'public/route-registry.v1.json'),
    SUMMARY_PATH: summaryPath, LOCAL_DATE: localDateInTimeZone(new Date(now),state.plan.clientProfile.timezone), LOGICAL_EPOCH_MS: String(epoch),
    STEP_LOGICAL_BASE:String(logicalBase),STEP_LOGICAL_SPAN:String(logicalWindow),
    APP_VERSION:state.plan.clientProfile.appVersion,PLATFORM:state.plan.clientProfile.platform,CLIENT_FEATURES:state.plan.clientProfile.clientFeatures,USER_AGENT:state.plan.clientProfile.userAgent,TIMEZONE:state.plan.clientProfile.timezone,RELEASE_CHANNEL:state.plan.clientProfile.releaseChannel,
  };
}

async function runK6(runDir, context, state, configuration) {
  const logicalWindow=logicalSpan(configuration.rps,configuration.seconds);
  const logicalBase=Number(state.plan.nextStepLogicalBase||1);
  state.plan.nextStepLogicalBase=logicalBase+logicalWindow+1;saveState(runDir,state);
  configuration={...configuration,logicalBase,logicalWindow};
  const baselineObservation=helper(context,['observe','--json']);
  const logCounts=()=>{
    const logs=lima(context,context.appVm,['pm2','logs','stepv2-capacity','--nostream','--lines','5000'],{allowFailure:true});
    const lines=`${logs.stdout||''}\n${logs.stderr||''}`.split('\n');
    return {
      databaseConnectionErrors:lines.filter(line=>/(deadlock|econn|pool.*(?:wait|timeout)|connection.*(?:fail|timeout)|too many clients)/i.test(line)).length,
      backendErrors:lines.filter(line=>/(error|timeout|deadlock|econn|pool.*wait|out of memory)/i.test(line)).length,
      nginxErrors:Number(String(lima(context,context.appVm,['sudo','wc','-l','/var/log/nginx/capacity-error.log'],{allowFailure:true}).stdout||'0').trim().split(/\s+/)[0]||0),
    };
  };
  const baselineLogs=logCounts();
  const child = spawn('k6', ['run','--quiet',LOAD_PATH], {env: k6Environment(runDir,context,state,configuration), stdio: ['ignore','pipe','pipe']});
  activeLoadProcess = child;
  state.activeLoad={pid:child.pid,script:LOAD_PATH,startedAt:new Date().toISOString()};saveState(runDir,state);
  const closed = new Promise((resolveExit, reject) => { child.on('error', reject); child.on('close', resolveExit); });
  const childDeadline=Math.min(Date.parse(state.plan.deadlineAt),Date.now()+(configuration.seconds+30)*1000);
  const absoluteDeadlineTriggered=childDeadline===Date.parse(state.plan.deadlineAt);
  let watchdogTriggered=false;
  const watchdog=setTimeout(()=>{if(child.exitCode===null){watchdogTriggered=true;child.kill('SIGTERM');setTimeout(()=>{if(child.exitCode===null)child.kill('SIGKILL');},10_000).unref();}},Math.max(1,childDeadline-Date.now()));
  const stdout = createWriteStream(`${configuration.summaryPath}.stdout.log`, {mode: 0o600});
  const stderr = createWriteStream(`${configuration.summaryPath}.stderr.log`, {mode: 0o600});
  const logsClosed=Promise.all([stdout,stderr].map(stream=>new Promise((resolveLog,rejectLog)=>{
    stream.once('finish',resolveLog);stream.once('error',rejectLog);
  })));
  child.stdout.pipe(stdout); child.stderr.pipe(stderr);
  const observations = [baselineObservation];
  let observationIndex = 0;
  while (child.exitCode === null) {
    try {
      const snapshot = helper(context, ['observe','--json']);
      if (observationIndex % 5 === 0) {
        const processes = JSON.parse(String(lima(context, context.appVm, ['pm2','jlist']).stdout || '[]')).filter(item => item.name === 'stepv2-capacity');
        snapshot.workers = processes.map(item => ({
          instance: String(item.pm2_env?.NODE_APP_INSTANCE), status: item.pm2_env?.status,
          cpuPercent: Number(item.monit?.cpu || 0), memoryBytes: Number(item.monit?.memory || 0),
          restarts: Number(item.pm2_env?.restart_time || 0),
          eventLoopLatencyMs: Number(item.axm_monitor?.['Loop delay']?.value || item.axm_monitor?.['Event Loop Latency']?.value || 0),
        }));
      }
      observations.push(snapshot);
    } catch (error) { observations.push({ok:false,error:String(error.message)}); }
    observationIndex += 1;
    await Promise.race([new Promise(resolveDelay => setTimeout(resolveDelay, 2000)), closed]);
  }
  const code = await closed;
  clearTimeout(watchdog);
  await logsClosed;
  activeLoadProcess = null;
  state.activeLoad=null;saveState(runDir,state);
  const finalLogs=logCounts();
  if(watchdogTriggered&&absoluteDeadlineTriggered){const error=new Error('k6 child reached the absolute eight-hour deadline');error.code='CAPACITY_DEADLINE';throw error;}return {code,watchdogTriggered, observations, logDelta:{databaseConnectionErrors:Math.max(0,finalLogs.databaseConnectionErrors-baselineLogs.databaseConnectionErrors),backendErrors:Math.max(0,finalLogs.backendErrors-baselineLogs.backendErrors),nginxErrors:Math.max(0,finalLogs.nginxErrors-baselineLogs.nginxErrors)}};
}

function classifyStage(summary, observations, rps, diagnostics={}) {
  if (!summary || summary.schemaVersion !== 'stepv2-k6-stage-summary-v1') return {kind:'invalid', reasons:['missing or invalid k6 summary']};
  const reasons = [];
  const invalid = [];
  if (summary.dropped > 0) invalid.push(`${summary.dropped} dropped iterations / VU saturation`);
  if (summary.configuredMaxVUs > 0 && summary.peakActiveVUs >= summary.configuredMaxVUs) invalid.push(`active VUs reached configured maximum ${summary.configuredMaxVUs}`);
  if (summary.authFailures > 0) invalid.push(`${summary.authFailures} auth failures`);
  if (Math.abs(summary.achievedRps - rps) / rps > 0.02) invalid.push(`achieved ${summary.achievedRps.toFixed(2)} RPS outside ±2%`);
  if (observations.some(item => item.ok === false)) invalid.push('telemetry snapshot failed');
  if(diagnostics.expectedPooler&&observations.some(item=>item.pooler?.enabled!==true))invalid.push('PgBouncer telemetry was not enabled for the recreated pooler path');
  if (invalid.length) return {kind:'invalid', reasons:invalid};
  if (summary.failureRate >= 0.01) reasons.push(`HTTP failure rate ${(summary.failureRate*100).toFixed(2)}%`);
  if (summary.p95Ms >= 2000) reasons.push(`HTTP p95 ${summary.p95Ms.toFixed(0)}ms`);
  for (const [route, values] of Object.entries(summary.routes || {})) {
    if (values.count >= 100 && values.failureRate >= 0.01) reasons.push(`${route} failure rate ${(values.failureRate*100).toFixed(2)}%`);
    if (values.count >= 100 && values.p95Ms >= 2000) reasons.push(`${route} p95 ${values.p95Ms.toFixed(0)}ms`);
  }
  const deadlocks = observations.map(item => Number(item.database?.deadlocks || 0));
  const waiting = observations.map(item => Number(item.database?.connections?.waiting || 0));
  const connections = observations.map(item => Number(item.database?.connections?.total || 0));
  const permanent = observations.map(item => Number(item.queue?.v1?.failed || 0) + Number(item.queue?.v2?.failed || 0) + Number(item.queue?.postTasks?.failed || 0) + Number(item.queue?.deliveryIntents?.failed || 0));
  const terminal=[];
  if (deadlocks.length && Math.max(...deadlocks) - deadlocks[0] > 0) terminal.push('database deadlocks');
  if (observations.some(item => (item.workers || []).some(worker => worker.status !== 'online' || worker.restarts > 0))) terminal.push('backend worker loss or restart');
  if (Math.max(0, ...waiting) >= DB_SPEC.maxConnections - 2) terminal.push('database connection exhaustion');
  if (Math.max(0, ...connections) >= DB_SPEC.maxConnections - 1) terminal.push('database connection ceiling exhausted');
  if(Number(diagnostics.databaseConnectionErrors||0)>0)terminal.push(`${diagnostics.databaseConnectionErrors} database connection error log lines`);
  if(observations.some(item=>item.pooler?.enabled===true&&item.pooler?.saturation?.saturated===true))terminal.push('PgBouncer client wait saturation');
  if(diagnostics.failOnPoolerNearSaturation===true&&observations.some(item=>item.pooler?.enabled===true&&item.pooler?.saturation?.nearSaturation===true))reasons.push('PgBouncer near saturation');
  if(terminal.length)return {kind:'terminal',reasons:terminal};
  if (Math.max(0, ...permanent) > 0) reasons.push('permanently failed queue jobs');
  return {kind: reasons.length ? 'fail' : 'pass', reasons};
}
function limitingClassification(reasons=[],diagnostics={}){return Number(diagnostics.databaseConnectionErrors||0)>0||reasons.some(reason=>/database|deadlock|connection|pgbouncer|saturation|wait/i.test(reason))?'database limit':'application limit';}

async function executeTraffic(runDir, state, context) {
  phaseStart(runDir, state, 'traffic');
  try {
    const workload=runWorkload(state);
    const deadline = Date.parse(state.plan.deadlineAt||state.createdAt) + (state.plan.deadlineAt?0:workload.deadlineSeconds*1000);
    const stagesPath=join(runDir,'public/stages.json');
    const stages = existsSync(stagesPath)?readJson(stagesPath).stages||[]:[];
    if(workload.mode==='fixed-one-level'&&stages.at(-1)?.classification?.kind==='pass'){const reconstructedRps=Number(stages.at(-1).rps);state.highestPassingRps=reconstructedRps;state.trafficProgress=null;state.terminalReason='fixed-experimental-level-complete';state.terminalClassification='pass';state.terminalCauses=[];phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length,targetRps:reconstructedRps,passed:true,reconstructed:true});return;}
    if(state.trafficProgress){const wave=stages.filter(stage=>Number(stage.rps)===Number(state.trafficProgress.rps));if(wave.at(-1)?.classification?.kind==='pass'){state.highestPassingRps=Number(state.trafficProgress.rps);state.trafficProgress=null;saveState(runDir,state);}else{state.trafficProgress.sameRateFailures=Math.min(1,wave.filter(stage=>stage.classification?.kind==='fail').length);state.trafficProgress.generatorRetries=Math.min(1,wave.filter(stage=>stage.classification?.kind==='invalid').length);state.trafficProgress.vuMultiplier=state.trafficProgress.generatorRetries?12:6;saveState(runDir,state);}}
    if(stages.at(-1)?.classification?.kind==='terminal'){state.terminalReason='terminal-safety-failure';state.terminalClassification=limitingClassification(stages.at(-1).classification.reasons,stages.at(-1).logDelta);state.terminalCauses=stages.at(-1).classification.reasons;phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length,reconstructed:true});return;}
    if(state.trafficProgress&&stages.filter(stage=>Number(stage.rps)===Number(state.trafficProgress.rps)&&stage.classification?.kind==='fail').length>=2){const last=stages.at(-1);state.terminalReason='application-or-database-limit';state.terminalClassification=limitingClassification(last.classification.reasons,last.logDelta);state.terminalCauses=last.classification.reasons;phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length,reconstructed:true});return;}
    if(state.trafficProgress&&stages.filter(stage=>Number(stage.rps)===Number(state.trafficProgress.rps)&&stage.classification?.kind==='invalid').length>=2){state.terminalReason='invalid/harness-limited';state.terminalClassification='inconclusive';state.terminalCauses=stages.at(-1).classification.reasons;phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length,reconstructed:true});return;}
    initializeTrafficDiagnostics(context);
    let rps = Number(state.trafficProgress?.rps||(state.highestPassingRps === null ? workload.startRps : state.highestPassingRps + workload.stepRps));
    let ordinal = Number(state.trafficProgress?.ordinal||new Set(stages.map(stage=>stage.rps)).size);
    let loadSequence = Number(state.plan.loadSequence || 0);
    while (Date.now() < deadline) {
      if (Date.now() + (workload.warmupSeconds + workload.measureSeconds + durationTimeout(state.plan)) * 1000 >= deadline) {
        state.terminalReason='wall-clock-deadline';
        state.terminalClassification='inconclusive';state.terminalCauses=[state.trafficProgress?.sameRateFailures===1?'deadline reached after only one failure at the current level':'deadline reached without a twice-failed level'];
        phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length});
        return;
      }
      if(!state.trafficProgress?.warmupComplete){ordinal += 1;state.trafficProgress={rps,ordinal,warmupComplete:false,sameRateFailures:0,generatorRetries:0,vuMultiplier:6};saveState(runDir,state);}
      const drainTimeout = durationTimeout(state.plan);
      if(!state.trafficProgress.warmupComplete){requireCleanBarrier(barrier(context, drainTimeout));refreshCapacityTokens(runDir,context,state);const warmupPath = join(runDir, 'public', `stage-${String(ordinal).padStart(4,'0')}-${rps}rps-warmup.json`);loadSequence += 1; state.plan.loadSequence=loadSequence; saveState(runDir,state);const warmup = await runK6(runDir, context, state, {phase:'warmup',rps,seconds:workload.warmupSeconds,repeat:loadSequence,vuMultiplier:6,summaryPath:warmupPath});if(cancellationRequested){state.terminalReason='operator-cancelled';state.terminalClassification='inconclusive';state.terminalCauses=['operator cancelled before a level failed twice'];phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length});return;}if (warmup.code !== 0) throw new Error(`warm-up process failed at ${rps} RPS with exit ${warmup.code}`);requireCleanBarrier(barrier(context, drainTimeout));state.trafficProgress.warmupComplete=true;saveState(runDir,state);}
      let sameRateFailures = Number(state.trafficProgress.sameRateFailures||0);
      let generatorRetries = Number(state.trafficProgress.generatorRetries||0);
      let vuMultiplier = Number(state.trafficProgress.vuMultiplier||6);
      while (true) {
        if(Date.now()+(workload.measureSeconds+drainTimeout)*1000>=deadline){state.terminalReason='wall-clock-deadline';state.terminalClassification='inconclusive';state.terminalCauses=[sameRateFailures===1?'deadline reached after only one failure at the current level':'deadline reached without a twice-failed level'];phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length});return;}
        clearTrafficErrorLogs(context);
        refreshCapacityTokens(runDir,context,state);
        const summaryPath = join(runDir, 'public', `stage-${String(ordinal).padStart(4,'0')}-${rps}rps-attempt-${sameRateFailures+generatorRetries+1}.json`);
        loadSequence += 1; state.plan.loadSequence=loadSequence; saveState(runDir,state);
        const measured = await runK6(runDir, context, state, {phase:'measure',rps,seconds:workload.measureSeconds,repeat:loadSequence,vuMultiplier,summaryPath});
        const summary = existsSync(summaryPath) ? readJson(summaryPath) : null;
        let classification = classifyStage(summary, measured.observations, rps, {...measured.logDelta,expectedPooler:productionUsesPooler(state.plan.production),failOnPoolerNearSaturation:state.plan.safetyGates?.failOnPoolerNearSaturation===true});
        if(measured.watchdogTriggered)classification={kind:'invalid',reasons:['k6 process exceeded the absolute run/stage watchdog']};
        else if(![0,99].includes(Number(measured.code)))classification={kind:'invalid',reasons:[`k6 process exited ${measured.code}`]};
        const drain = barrier(context, drainTimeout);
        if(Number(drain.permanentFailureCount||0)>0)classification={kind:'terminal',reasons:[`${drain.permanentFailureCount} permanent queue failures after drain`]};
        else if(drain.successful!==true)classification={kind:'fail',reasons:[`queue drain ${drain.drainState||'failed'} with ${Number(drain.pending||0)} pending`]};
        const record = {rps, attempt:sameRateFailures+generatorRetries+1, summary, classification, drain, observations:measured.observations,logDelta:measured.logDelta};
        stages.push(record);
        atomicJson(stagesPath, {schemaVersion:'stepv2-capacity-stages-v1',stages});
        if(cancellationRequested){state.terminalReason='operator-cancelled';state.terminalClassification='inconclusive';state.terminalCauses=['operator cancelled before the same level failed twice'];phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length});return;}
        if(classification.kind==='terminal'){state.terminalReason='terminal-safety-failure';state.terminalClassification=limitingClassification(classification.reasons,measured.logDelta);state.terminalCauses=classification.reasons;phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length});return;}
        if (classification.kind === 'pass') { state.highestPassingRps = rps;state.trafficProgress=null;if(workload.mode==='fixed-one-level'){state.terminalReason='fixed-experimental-level-complete';state.terminalClassification='pass';state.terminalCauses=[];saveState(runDir,state);phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length,targetRps:rps,passed:true});return;}rps += workload.stepRps;saveState(runDir,state); break; }
        if (classification.kind === 'invalid' && generatorRetries < 1) { generatorRetries += 1; vuMultiplier *= 2;Object.assign(state.trafficProgress,{generatorRetries,vuMultiplier,sameRateFailures});saveState(runDir,state);requireCleanBarrier(barrier(context,drainTimeout)); continue; }
        if (classification.kind === 'invalid') { state.terminalReason='invalid/harness-limited';state.terminalClassification='inconclusive';state.terminalCauses=classification.reasons; phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length}); return; }
        if (sameRateFailures < 1) { sameRateFailures += 1;Object.assign(state.trafficProgress,{sameRateFailures,generatorRetries,vuMultiplier});saveState(runDir,state);requireCleanBarrier(barrier(context,drainTimeout)); continue; }
        state.terminalReason='application-or-database-limit';state.terminalClassification=limitingClassification(classification.reasons,measured.logDelta);state.terminalCauses=classification.reasons; phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length}); return;
      }
    }
    state.terminalReason='wall-clock-deadline';
    phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,stages:stages.length});
  } catch (error) {
    if(error.code==='CAPACITY_DEADLINE'||error.code==='CAPACITY_CANCELLED')throw error;
    state.terminalReason = /barrier|drain|queue/i.test(String(error.message)) ? 'terminal-drain-failure' : 'traffic-runtime-failure';
    atomicJson(join(runDir,'public/traffic-error.json'),{occurredAt:new Date().toISOString(),terminalReason:state.terminalReason,error:String(error.message)});
    phaseComplete(runDir,state,'traffic',{terminalReason:state.terminalReason,errorRecorded:true});
  }
}

function finalDrain(runDir,state,context) {
  phaseStart(runDir,state,'drain');
  try {
    const result = barrier(context,durationTimeout(state.plan));
    atomicJson(join(runDir,'public/final-drain.json'),result);
    if(result.successful!==true){const count=Number(result.permanentFailureCount||0);if(!state.terminalClassification||state.terminalClassification==='inconclusive'){state.terminalClassification=count>0?'application limit':'inconclusive';state.terminalCauses=[...(state.terminalCauses||[]),count>0?`${count} permanent queue failures remained at final drain`:`final queue drain ${result.drainState||'failed'} with ${Number(result.pending||0)} pending`];saveState(runDir,state);}}
    phaseComplete(runDir,state,'drain',{drained:result.successful===true,drainState:result.drainState,permanentFailureCount:Number(result.permanentFailureCount||0)});
  } catch (error) {
    atomicJson(join(runDir,'public/final-drain.json'),{ok:false,drained:false,error:String(error.message)});
    if(!state.terminalClassification||state.terminalClassification==='inconclusive'){state.terminalClassification='application limit';state.terminalCauses=[...(state.terminalCauses||[]),`final queue drain failed: ${error.message}`];saveState(runDir,state);}
    phaseComplete(runDir,state,'drain',{drained:false,errorRecorded:true});
  }
}

function diagnosticClassification(stages) {
  const final = stages.at(-1);
  if (!final) return {classification:'inconclusive',causes:['no measured stage completed']};
  if (final.classification.kind === 'invalid') return {classification:'harness limitation',causes:final.classification.reasons};
  const observations = final.observations || [];
  const peakConnections = Math.max(0,...observations.map(value=>Number(value.database?.connections?.total||0)));
  const dbReasons = final.classification.reasons.filter(reason => /database|deadlock|connection|pgbouncer|saturation|wait/i.test(reason));
  if (dbReasons.length || peakConnections >= DB_SPEC.maxConnections - 2) return {classification:'database limit',causes:[...dbReasons,peakConnections?`peak ${peakConnections}/${DB_SPEC.maxConnections} database connections`:null].filter(Boolean)};
  if (final.classification.kind === 'fail'||final.classification.kind==='terminal') return {classification:'application limit',causes:final.classification.reasons};
  return {classification:'inconclusive',causes:[`terminated by ${final.terminalReason||'deadline/cancellation'} without a twice-failed level`]};
}

function createReport(runDir,state) {
  phaseStart(runDir,state,'report_copy');
  try {
    const stagesDoc = existsSync(join(runDir,'public/stages.json')) ? readJson(join(runDir,'public/stages.json')) : {stages:[]};
    let diagnosis = diagnosticClassification(stagesDoc.stages);
    if(state.terminalClassification)diagnosis={classification:state.terminalClassification,causes:state.terminalCauses||[]};
    if(existsSync(join(runDir,'public/traffic-error.json'))){
      const trafficError=readJson(join(runDir,'public/traffic-error.json'));
      const message=String(trafficError.error||trafficError.terminalReason||'traffic runtime failed');
      diagnosis=/database|deadlock|connection/i.test(message)?{classification:'database limit',causes:[message]}:/queue|barrier|drain/i.test(message)?{classification:'application limit',causes:[message]}:{classification:'harness limitation',causes:[message]};
    }
    if(!state.terminalClassification&&stagesDoc.stages.at(-1)?.classification?.kind==='pass'&&state.terminalReason)diagnosis={classification:'inconclusive',causes:[`run ended by ${state.terminalReason} after the highest passing level`]};
    if(state.plan.productionDeviations.some(value=>/non-comparable|not reproduced/i.test(value)))diagnosis={classification:'inconclusive',causes:[...diagnosis.causes,...state.plan.productionDeviations.filter(value=>/non-comparable|not reproduced/i.test(value))]};
    const measured = stagesDoc.stages.filter(stage => stage.summary);
    const observations = measured.flatMap(stage => stage.observations || []);
    const numbers = (selector) => observations.map(selector).map(Number).filter(Number.isFinite);
    const maximum = (selector) => Math.max(0,...numbers(selector));
    const total = (selector) => measured.reduce((sum,stage)=>sum+Number(selector(stage.summary)||0),0);
    const syncSubmissions = measured.reduce((sum,stage)=>sum+Number(stage.summary?.routes?.steps_sync_v2?.count||0),0);
    const jobsTouched = maximum(item=>item.queue?.v2?.jobsTouched||0);
    const firstGeneration=Number(observations[0]?.queue?.v2?.generationTotal||0);
    const generationDelta=Math.max(0,maximum(item=>item.queue?.v2?.generationTotal)-firstGeneration);
    const firstJobs=Number(observations[0]?.queue?.v2?.total||0);
    const newJobsCreated=Math.max(0,maximum(item=>item.queue?.v2?.total)-firstJobs);
    const workload=runWorkload(state);
    const measuredSeconds=measured.length*workload.measureSeconds;
    const finalDrainEvidence=existsSync(join(runDir,'public/final-drain.json'))?readJson(join(runDir,'public/final-drain.json')):null;
    const actualTopology=existsSync(join(runDir,'public/topology.json'))?readJson(join(runDir,'public/topology.json')):null;
    const drainTimes=measured.map(stage=>Number(stage.drain?.drainMs||0));
    if(Number.isFinite(Number(finalDrainEvidence?.drainMs)))drainTimes.push(Number(finalDrainEvidence.drainMs));
    const reportContext = readJson(join(runDir,'protected/context.json'));
    const backendErrorLines=measured.reduce((sum,stage)=>sum+Number(stage.logDelta?.backendErrors||0),0);
    const backendDatabaseErrorLines=measured.reduce((sum,stage)=>sum+Number(stage.logDelta?.databaseConnectionErrors||0),0);
    const nginxErrorLines=measured.reduce((sum,stage)=>sum+Number(stage.logDelta?.nginxErrors||0),0);
    const telemetry = {
      http:{requested:measured.reduce((sum,stage)=>sum+Number(stage.rps)*workload.measureSeconds,0),started:total(summary=>summary.requests),completed:total(summary=>summary.completedIterations),accepted:total(summary=>summary.accepted),rejected:total(summary=>summary.rejected),timedOut:total(summary=>summary.timedOut),dropped:total(summary=>summary.dropped)},
      queue:{stepSyncSubmissions:syncSubmissions,newJobsCreated,jobsTouched,generationDelta,processingRatePerSecond:measuredSeconds?generationDelta/measuredSeconds:null,coalescingRatio:jobsTouched?syncSubmissions/jobsTouched:null,peakPending:maximum(item=>item.pending),peakOldestAgeSeconds:maximum(item=>item.queue?.v2?.oldestAgeSeconds),generationTotalPeak:maximum(item=>item.queue?.v2?.generationTotal),retriesPeak:maximum(item=>Number(item.queue?.v1?.retries||0)+Number(item.queue?.v2?.retries||0)),failedPeak:Math.max(maximum(item=>Number(item.queue?.v1?.failed||0)+Number(item.queue?.v2?.failed||0)+Number(item.queue?.postTasks?.failed||0)+Number(item.queue?.deliveryIntents?.failed||0)),Number(finalDrainEvidence?.permanentFailureCount||finalDrainEvidence?.permanentFailures?.total||0)),finalPending:finalDrainEvidence?.drained===true?0:Number(finalDrainEvidence?.pending??(observations.at(-1)?.pending||0)),maximumDrainMs:Math.max(0,...drainTimes)},
      database:{peakConnections:maximum(item=>item.database?.connections?.total),peakActive:maximum(item=>item.database?.connections?.active),peakIdle:maximum(item=>item.database?.connections?.idle),peakWaiting:maximum(item=>item.database?.connections?.waiting),peakLockWaits:maximum(item=>item.database?.lockWaits),peakSlowQueries:maximum(item=>item.database?.slowQueries),deadlockDelta:observations.length?maximum(item=>item.database?.deadlocks)-Number(observations[0].database?.deadlocks||0):0,pooler:{enabled:observations.some(item=>item.pooler?.enabled===true),peakClientsWaiting:maximum(item=>item.pooler?.waits?.clientsWaiting),peakMaxWaitSeconds:maximum(item=>item.pooler?.waits?.maxWaitSeconds),saturated:observations.some(item=>item.pooler?.saturation?.saturated===true),nearSaturation:observations.some(item=>item.pooler?.saturation?.nearSaturation===true)}},
      workers:{peakCpuPercent:maximum(item=>Math.max(0,...(item.workers||[]).map(worker=>Number(worker.cpuPercent||0)))),peakMemoryBytes:maximum(item=>Math.max(0,...(item.workers||[]).map(worker=>Number(worker.memoryBytes||0)))),peakEventLoopLatencyMs:maximum(item=>Math.max(0,...(item.workers||[]).map(worker=>Number(worker.eventLoopLatencyMs||0)))),restartPeak:maximum(item=>Math.max(0,...(item.workers||[]).map(worker=>Number(worker.restarts||0)))),backendErrorLines,backendDatabaseErrorLines,nginxErrorLines},
    };
    if(backendDatabaseErrorLines>0&&diagnosis.classification==='application limit')diagnosis={classification:'database limit',causes:[...diagnosis.causes,`${backendDatabaseErrorLines} database/pool error log lines`]};
    const report = {
      schemaVersion:'stepv2-capacity-report-v1',runId:state.runId,createdAt:new Date().toISOString(),
      backendCommit:state.plan.backendCommit,environmentChecksum:state.phases.input_acquisition.postconditions.checksum,
      routeRegistrySha256:state.plan.routeRegistrySha256,
      topology:{expected:{app:state.plan.app,database:DB_SPEC},actual:actualTopology,workers:state.plan.workers,poolSize:state.plan.poolSize,databasePath:productionUsesPooler(state.plan.production)?'pgbouncer':'direct',targetPooler:state.plan.targetPooler||null,experimental:state.plan.experimental||null},seed:reportContext.seed,
      clientProfile:state.plan.clientProfile,
      databaseComparability:{settings:state.plan.databaseSettings||null,productionPoolerTelemetry:state.plan.production.dbRuntime?.poolerTelemetry||null,targetPoolerPlan:state.plan.targetPooler||null,targetPoolerReproduction:state.plan.pgbouncerReproduction||null,targetPoolerObserved:observations.some(item=>item.pooler?.enabled===true)},
      trafficInterval:state.plan.traffic.interval,coveragePercent:state.plan.traffic.coveragePercent,
      productionDeviations:state.plan.productionDeviations,
      highestPassingRps:state.highestPassingRps,terminalReason:state.terminalReason,diagnosis,telemetry,stages:stagesDoc.stages,
      comparisonLimits:['Lima CPU/storage/networking are not DigitalOcean shared CPU, managed storage, or managed networking','Cloudflare/edge TLS is omitted; requests still traverse nginx to PM2',productionUsesPooler(state.plan.production)?'The reproduced local PgBouncer path is capacity-validated and TLS-disabled inside a loopback-only SSH tunnel':'The direct app-to-PostgreSQL path is carried inside a loopback-only SSH tunnel','The capacity entrypoint intentionally schedules only race-resolution and resolution-post-task workers; unrelated production crons are absent','production PII existed only inside the disposable isolated database VM'],
    };
    atomicJson(join(runDir,'public/report.json'),report);
    const markdown = `# K6 capacity report: ${state.runId}\n\n- Backend: \`${report.backendCommit}\`\n- Rolling traffic window: ${report.trafficInterval.start} – ${report.trafficInterval.end} UTC (half-open)\n- Registry coverage: ${report.coveragePercent.toFixed(2)}%\n- Highest passing level: ${report.highestPassingRps === null ? 'none' : `${report.highestPassingRps} RPS`}\n- Termination: ${report.terminalReason || 'operator/error'}\n- Classification: ${diagnosis.classification}\n- Causes: ${diagnosis.causes.join('; ') || 'none recorded'}\n- Production-shape differences: ${report.productionDeviations.join('; ') || 'none observed'}\n- Cleanup policy: destroy both VMs and all protected inputs after this report is secured\n\nThe machine-readable stage, queue, HTTP, database, and worker evidence is in \`report.json\`.\n`;
    writeFileSync(join(runDir,'public/report.md'),markdown,{mode:0o600});
    phaseComplete(runDir,state,'report_copy',{json:true,markdown:true,diagnosis:diagnosis.classification});
  } catch (error) { phaseFailed(runDir,state,'report_copy',error); throw error; }
}

function cleanupRun(root,runDir,state,context,{force=false}={}) {
  phaseStart(runDir,state,'cleanup');
  const receiptPath=join(runDir,'public/cleanup-receipt.json');
  const receipt=existsSync(receiptPath)?readJson(receiptPath):{schemaVersion:'stepv2-capacity-cleanup-receipt-v1',runId:state.runId,startedAt:new Date().toISOString(),targets:[],complete:false};
  receipt.resumedAt=existsSync(receiptPath)?new Date().toISOString():undefined;
  receipt.error=null;atomicJson(receiptPath,receipt);
  try {
    stopRecordedLoad(runDir,state);
    if (!existsSync(join(runDir,'public/report.json')) && !force) throw new Error('report is not secured; use cleanup only after reviewing diagnostics (or K6_FORCE_CLEANUP=1)');
    const tunnelIdentityHash=shortHash(`${context.runId}:database-ssh-tunnel`);
    let tunnelTarget=receipt.targets.find(item=>item.kind==='host-tunnel'&&item.identityHash===tunnelIdentityHash);
    if(!tunnelTarget){tunnelTarget={kind:'host-tunnel',identityHash:tunnelIdentityHash,stopped:false};receipt.targets.push(tunnelTarget);atomicJson(receiptPath,receipt);}
    stopDbTunnel(context,state.plan.production);tunnelTarget.stopped=true;atomicJson(receiptPath,receipt);
    for (const vm of [context.appVm,context.dbVm]) {
      if (!/^stepv2-k6-[a-z0-9-]+-(app|db)$/.test(vm)) throw new Error(`refusing unsafe Lima target ${vm}`);
      const exists=limaExists(vm);
      const marker=exists&&markerValid(context,vm);
      const ownership=exists&&vmOwnershipValid(context,vm);
      if (exists&&!marker&&!ownership) throw new Error(`${vm} lacks both the exact run marker and a valid host operator ownership receipt; refusing delete`);
      const identityHash=shortHash(vm);
      let target=receipt.targets.find(item=>item.kind==='vm'&&item.identityHash===identityHash);
      if(!target){target={kind:'vm',identityHash,markerVerified:marker,ownershipVerified:ownership,deleted:false};receipt.targets.push(target);}
      if(marker)target.markerVerified=true;
      if(ownership)target.ownershipVerified=true;
      if(!exists)target.absentBefore=true;
      atomicJson(receiptPath,receipt);
      if(exists&&vm===context.appVm)lima(context,vm,['pm2','delete','stepv2-capacity'],{allowFailure:true});
      if (exists) run('limactl',['delete','--force',vm],{stdio:'inherit'});
      target.deleted=true;atomicJson(receiptPath,receipt);
    }
    const publicDir=join(runDir,'public');
    for(const name of existsSync(publicDir)?readdirSync(publicDir):[]){
      if(!/\.(?:stdout|stderr)\.log$/.test(name))continue;
      const path=join(publicDir,name);
      const target={kind:'raw-process-log',nameHash:shortHash(name),contentHash:sha256(path),deleted:false};
      receipt.targets.push(target);atomicJson(receiptPath,receipt);
      rmSync(path,{force:true});
      target.deleted=true;atomicJson(receiptPath,receipt);
    }
    for(const target of receipt.targets.filter(item=>item.kind==='raw-process-log'))target.deleted=true;
    const protectedDir=join(runDir,'protected');
    if (resolve(protectedDir)!==resolve(runDir,'protected')||!resolve(protectedDir).startsWith(resolve(root,'runs')+'/')) throw new Error('protected cleanup path escaped run root');
    if (existsSync(protectedDir)) {
      const pending=[];
      const visit=(directory,prefix='')=>{for(const entry of readdirSync(directory,{withFileTypes:true})){const relative=prefix?`${prefix}/${entry.name}`:entry.name;const path=join(directory,entry.name);if(entry.isDirectory()){visit(path,relative);continue;}const metadata=lstatSync(path);const nameHash=shortHash(relative);let target=receipt.targets.find(item=>item.kind==='secret-artifact'&&item.nameHash===nameHash);if(!target){target={kind:'secret-artifact',nameHash,entryType:entry.isSymbolicLink()?'symlink':'file',contentHash:entry.isFile()?sha256(path):null,bytes:metadata.size,deleted:false};receipt.targets.push(target);}pending.push(target);}};
      visit(protectedDir);
      atomicJson(receiptPath,receipt);
      rmSync(protectedDir,{recursive:true,force:true});
      for(const target of pending)target.deleted=true;
      atomicJson(receiptPath,receipt);
    }else{
      for(const target of receipt.targets.filter(item=>item.kind==='secret-artifact'))target.deleted=true;
    }
    receipt.complete=true;receipt.completedAt=new Date().toISOString();
    atomicJson(receiptPath,receipt);
    state.status='complete';
    phaseComplete(runDir,state,'cleanup',{complete:true,vmCount:2,secretsDeleted:true});
    clearActive(root,state.runId);
  } catch(error){receipt.error=String(error.message);receipt.completedAt=new Date().toISOString();atomicJson(receiptPath,receipt);phaseFailed(runDir,state,'cleanup',error);throw error;}
}

function cleanupOnlyContext(state){return {runId:state.runId,appVm:`${state.runId}-app`,dbVm:`${state.runId}-db`};}

function stopRecordedLoad(runDir,state){
  const pid=Number(state.activeLoad?.pid||0);
  if(!Number.isInteger(pid)||pid<1)return;
  const probe=run('ps',['-p',String(pid),'-o','command='],{allowFailure:true});
  if(probe.status!==0){state.activeLoad=null;saveState(runDir,state);return;}
  const command=String(probe.stdout||'');
  if(!command.includes('k6')||!command.includes('operator-load.js'))throw new Error(`recorded load pid ${pid} no longer belongs to this operator`);
  const alive=()=>run('ps',['-p',String(pid),'-o','command='],{allowFailure:true}).status===0;
  for(const [signal,waitMs] of [['SIGINT',10_000],['SIGTERM',10_000],['SIGKILL',5_000]]){if(!alive())break;try{process.kill(pid,signal);}catch(error){if(error?.code!=='ESRCH')throw error;}const deadline=Date.now()+waitMs;while(Date.now()<deadline&&alive())Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,250);}
  if(alive())throw new Error(`recorded k6 pid ${pid} survived bounded INT/TERM/KILL escalation`);
  state.activeLoad=null;saveState(runDir,state);
}

async function terminalizeEarly(root,runDir,state,context,reason){state.terminalReason=reason;state.terminalClassification='inconclusive';state.terminalCauses=[reason==='operator-cancelled'?'operator cancellation before a twice-failed level':'absolute eight-hour deadline expired before traffic completed'];if(state.phases.traffic.status!=='complete')phaseComplete(runDir,state,'traffic',{terminalReason:reason,stages:existsSync(join(runDir,'public/stages.json'))?readJson(join(runDir,'public/stages.json')).stages?.length||0:0,preTraffic:true});if(state.phases.drain.status!=='complete'){if(backendHealthy(context,state.plan.workers))finalDrain(runDir,state,context);else{atomicJson(join(runDir,'public/final-drain.json'),{ok:false,drained:false,skipped:true,reason:'backend was not safely available before terminalization'});phaseComplete(runDir,state,'drain',{drained:false,skipped:true});}}if(state.phases.report_copy.status!=='complete')createReport(runDir,state);if(state.phases.cleanup.status!=='complete')cleanupRun(root,runDir,state,context);}
function terminalizeBeforeApproval(root,runDir,state,context,reason){state.terminalReason=reason;state.terminalClassification='inconclusive';state.terminalCauses=['run ended safely before approval and before any production input or workload mutation'];atomicJson(join(runDir,'public/preapproval-terminal-receipt.json'),{schemaVersion:'stepv2-k6-preapproval-terminal-v1',runId:state.runId,reason,createdAt:new Date().toISOString(),productionMutated:false,loadStarted:false});saveState(runDir,state);cleanupRun(root,runDir,state,context,{force:true});}

async function continueRun(root,runDir,state) {
  assertApprovedPlanImmutable(state);
  const contextPath=join(runDir,'protected/context.json');
  if(!existsSync(contextPath)&&state.phases.report_copy.status!=='complete')throw new Error('protected run context is missing before report completion; refusing unsafe reconstruction');
  let context = existsSync(contextPath)?readJson(contextPath):cleanupOnlyContext(state);
  const phase = async (name, action, verify) => {
    const guarded=!['drain','report_copy','cleanup'].includes(name);
    let verified = !verify;
    if(verify){try{verified=Boolean(verify());}catch{verified=false;}}
    if (state.phases[name].status === 'complete' && verified) return;
    if(guarded&&(Date.now()>=absoluteDeadline(state)||cancellationRequested)){const error=new Error(cancellationRequested?`operator cancelled before ${name}`:`absolute eight-hour run deadline expired before ${name}`);error.code=cancellationRequested?'CAPACITY_CANCELLED':'CAPACITY_DEADLINE';throw error;}
    await (guarded?withinRunDeadline(state,name,action):action()); context = existsSync(join(runDir,'protected/context.json')) ? readJson(join(runDir,'protected/context.json')) : context;
  };
  try {
  await phase('provisioning',()=>provision(runDir,state,context),()=>provisionedTopologyValid(state,context));
  await phase('input_acquisition',()=>acquireInputs(runDir,state,context),()=>existsSync(join(runDir,'protected/production.env.evidence'))&&existsSync(join(runDir,'protected/effective.env'))&&sha256(join(runDir,'protected/production.env.evidence'))===state.phases.input_acquisition.postconditions.checksum&&sha256(join(runDir,'protected/effective.env'))===state.phases.input_acquisition.postconditions.effectiveChecksum&&(statSync(join(runDir,'protected/effective.env')).mode&0o077)===0);
  await phase('dump',()=>dumpProduction(runDir,state),()=>existsSync(join(runDir,'protected/production.dump'))&&sha256(join(runDir,'protected/production.dump'))===state.phases.dump.postconditions.checksum);
  await phase('restore',()=>restoreDatabase(runDir,state,context),()=>restoredMarkerValid(state,context));
  if(Date.now()>=absoluteDeadline(state)||cancellationRequested){const error=new Error('terminalization requested before private database tunnel validation');error.code=cancellationRequested?'CAPACITY_CANCELLED':'CAPACITY_DEADLINE';throw error;}
  await withinRunDeadline(state,'database_transport_validation',()=>ensureDbTunnel(runDir,state,context));
  if(Date.now()>=absoluteDeadline(state)||cancellationRequested){const error=new Error('terminalization requested before sanitization resume validation');error.code=cancellationRequested?'CAPACITY_CANCELLED':'CAPACITY_DEADLINE';throw error;}await withinRunDeadline(state,'sanitization_resume_validation',async()=>{if(state.phases.sanitization.status==='complete'){
    if(!backendCheckoutReady(context,state.plan.backendCommit))await prepareBackendCheckout(runDir,state,context,state.plan.backendCommit);
    ensureRuntimeArtifacts(runDir,context,{identities:state.phases.inflation.status==='complete'});
    const permanent=helper(context,['verify-sanitized','--scope','permanent','--run-id',context.runId,'--json']);
    if(permanent.ok!==true)throw new Error('permanent device/push sanitization invariant failed on resume; refusing to clear post-traffic queues or alter evidence');
  }else await sanitize(runDir,state,context);});
  await phase('inflation',()=>inflate(runDir,state,context),()=>existsSync(join(runDir,'protected/identities.ndjson'))&&sha256(join(runDir,'protected/identities.ndjson'))===state.phases.inflation.postconditions.identityChecksum&&helper(context,['verify-inflation','--run-id',context.runId,'--users',String(runWorkload(state).users),'--json']).ok===true);
  await phase('backend_startup',()=>startBackend(runDir,state,context),()=>backendHealthy(context,state.plan.workers)&&verifyBackendRuntime(runDir,state,context));
  await phase('traffic',()=>executeTraffic(runDir,state,context),()=>Boolean(state.terminalReason)&&(existsSync(join(runDir,'public/stages.json'))||existsSync(join(runDir,'public/traffic-error.json'))||state.terminalReason==='wall-clock-deadline'));
  await phase('drain',()=>finalDrain(runDir,state,context),()=>existsSync(join(runDir,'public/final-drain.json')));
  await phase('report_copy',()=>createReport(runDir,state),()=>existsSync(join(runDir,'public/report.json')));
  await phase('cleanup',()=>cleanupRun(root,runDir,state,context));
  }catch(error){if(['CAPACITY_DEADLINE','CAPACITY_CANCELLED'].includes(error.code)){await terminalizeEarly(root,runDir,state,context,error.code==='CAPACITY_CANCELLED'?'operator-cancelled':'wall-clock-deadline');return;}throw error;}
}

function availableLoopbackPort(preferred) {
  for (let port = preferred; port < preferred + 200; port += 1) {
    const probe = spawnSync(process.execPath, ['-e', "const n=require('node:net').createServer();n.once('error',()=>process.exit(1));n.listen(Number(process.argv[1]),'127.0.0.1',()=>n.close(()=>process.exit(0)))", String(port)]);
    if (probe.status === 0) return port;
  }
  throw new Error(`no free loopback port found from ${preferred} through ${preferred + 199}`);
}

function initialContext(runId) {
  const suffix=runId.replace(/^stepv2-k6-/,'').replace(/[^a-z0-9]/g,'').slice(-20);
  const requestedPort=Number(process.env.K6_APP_PORT||38080);
  if(!Number.isInteger(requestedPort)||requestedPort<1024||requestedPort>65000)throw new Error('K6_APP_PORT must be an unprivileged TCP port');
  return {runId,appVm:`${runId}-app`,dbVm:`${runId}-db`,appPort:availableLoopbackPort(requestedPort),appDbPort:15432,dbName:`stepv2_capacity_${suffix}`,dbPassword:randomBytes(24).toString('base64url'),authSecret:randomBytes(48).toString('base64url'),dbMarker:randomBytes(24).toString('hex'),seed:Number(process.env.K6_RUN_SEED||Math.floor(Math.random()*2_147_483_647)),topologyRevision:TOPOLOGY_REVISION,vmOwnership:{}};
}

async function commandRun(root) {
  const current=activeRun(root);
  if(current&&current.state.status!=='complete') throw new Error(`active run ${current.runId} exists; use status, resume, or cleanup`);
  const runId=makeRunId();
  const {runDir}=directories(root,runId);
  const context=initialContext(runId);
  atomicJson(join(runDir,'protected/context.json'),context);
  const state=newState({runId,root,plan:{}});saveState(runDir,state);setActive(root,runId);
  try{await withinRunDeadline(state,'discovery',()=>discover(runDir,state,context));}catch(error){if(error.code==='CAPACITY_DEADLINE'||cancellationRequested){terminalizeBeforeApproval(root,runDir,state,context,cancellationRequested?'operator-cancelled':'wall-clock-deadline');return;}throw error;}
  if(cancellationRequested||Date.now()>=absoluteDeadline(state)){await terminalizeEarly(root,runDir,state,context,cancellationRequested?'operator-cancelled':'wall-clock-deadline');return;}
  printPlan(state,context);
  phaseStart(runDir,state,'approval');
  if(!await confirm()){if(cancellationRequested){await terminalizeEarly(root,runDir,state,context,'operator-cancelled');return;}phaseFailed(runDir,state,'approval',new Error('operator declined plan'));cleanupRun(root,runDir,state,context,{force:true});throw new Error('plan not approved; discovery secrets were removed and no infrastructure or production inputs were mutated');}
  if(Date.now()>=absoluteDeadline(state)){await terminalizeEarly(root,runDir,state,context,'wall-clock-deadline');return;}
  completeApproval(runDir,state);
  await continueRun(root,runDir,state);
  process.stdout.write(`report: ${join(runDir,'public/report.md')}\ncleanup receipt: ${join(runDir,'public/cleanup-receipt.json')}\n`);
}

function discoveryArtifactsValid(runDir,state){
  const mix=join(runDir,'public/traffic-mix.json');
  const registry=join(runDir,'public/route-registry.v1.json');
  return state.phases.discovery.status==='complete'&&existsSync(mix)&&existsSync(registry)&&sha256(mix)===state.plan.trafficMixSha256&&sha256(registry)===state.plan.routeRegistrySha256&&approvalPlanFingerprint(state.plan)===state.plan.approvalFingerprint;
}

async function commandResume(root) {
  const current=activeRun(root);if(!current)throw new Error('no active k6 run');
  stopRecordedLoad(current.runDir,current.state);
  if(current.state.phases.discovery.status==='complete'&&!discoveryArtifactsValid(current.runDir,current.state))throw new Error('completed discovery artifacts no longer match their recorded checksums; start a fresh run rather than reusing an unconfirmed traffic mix');
  if(current.state.phases.approval.status!=='complete'){
    if(current.state.phases.discovery.status!=='complete'){try{await withinRunDeadline(current.state,'discovery',()=>discover(current.runDir,current.state,readJson(join(current.runDir,'protected/context.json'))));}catch(error){if(error.code==='CAPACITY_DEADLINE'||cancellationRequested){terminalizeBeforeApproval(root,current.runDir,current.state,readJson(join(current.runDir,'protected/context.json')),cancellationRequested?'operator-cancelled':'wall-clock-deadline');return;}throw error;}}
    const approvalContext=readJson(join(current.runDir,'protected/context.json'));
    if(cancellationRequested||Date.now()>=absoluteDeadline(current.state)){await terminalizeEarly(root,current.runDir,current.state,approvalContext,cancellationRequested?'operator-cancelled':'wall-clock-deadline');return;}
    printPlan(current.state,approvalContext);phaseStart(current.runDir,current.state,'approval');
    if(!await confirm()){if(cancellationRequested){await terminalizeEarly(root,current.runDir,current.state,approvalContext,'operator-cancelled');return;}phaseFailed(current.runDir,current.state,'approval',new Error('operator declined plan'));cleanupRun(root,current.runDir,current.state,approvalContext,{force:true});throw new Error('plan not approved; discovery secrets were removed');}
    if(Date.now()>=absoluteDeadline(current.state)){await terminalizeEarly(root,current.runDir,current.state,approvalContext,'wall-clock-deadline');return;}
    completeApproval(current.runDir,current.state);
  }
  await continueRun(root,current.runDir,current.state);
  process.stdout.write(`report: ${join(current.runDir,'public/report.md')}\ncleanup receipt: ${join(current.runDir,'public/cleanup-receipt.json')}\n`);
}

function commandStatus(root) {
  const current=activeRun(root);if(!current){process.stdout.write('No active k6 operator run.\n');return;}
  const phase=Object.entries(current.state.phases).find(([,v])=>v.status==='running'||v.status==='failed'||v.status==='pending');
  process.stdout.write(`Run: ${current.runId}\nStatus: ${current.state.status}\nCurrent phase: ${phase?.[0]||'complete'} (${phase?.[1].status||'complete'})\nHighest passing RPS: ${current.state.highestPassingRps??'none'}\nArtifacts: ${join(current.runDir,'public')}\n`);
  if(phase?.[1].error)process.stdout.write(`Error: ${phase[1].error}\n`);
}

function commandCleanup(root) {
  const current=activeRun(root);if(!current)throw new Error('no active k6 run');
  const contextPath=join(current.runDir,'protected/context.json');
  const context=existsSync(contextPath)?readJson(contextPath):cleanupOnlyContext(current.state);
  cleanupRun(root,current.runDir,current.state,context,{force:process.env.K6_FORCE_CLEANUP==='1'});
  process.stdout.write(`cleanup receipt: ${join(current.runDir,'public/cleanup-receipt.json')}\n`);
}

async function main() {
  const command=process.argv[2];
  if(!['run','status','resume','cleanup'].includes(command)){die('usage: k6/operator.zsh run|status|resume|cleanup');return;}
  const root=stateRoot();
  if(command==='status'){commandStatus(root);return;}
  const release=acquireLock(root);
  try{if(command==='run')await commandRun(root);else if(command==='resume')await commandResume(root);else commandCleanup(root);}
  catch(error){die(`k6 operator: ${error.message}`);}
  finally{release();}
}

await main();
