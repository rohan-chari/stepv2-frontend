import {chmodSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {homedir} from 'node:os';
import {join, resolve} from 'node:path';

export const PHASES = [
  'discovery', 'approval', 'provisioning', 'input_acquisition', 'dump',
  'restore', 'sanitization', 'inflation', 'backend_startup', 'traffic',
  'drain', 'report_copy', 'cleanup',
];

export function stateRoot(environment = process.env) {
  return resolve(environment.K6_OPERATOR_STATE_ROOT || join(homedir(), '.stepv2-k6-operator'));
}

export function atomicJson(path, value, mode = 0o600) {
  mkdirSync(resolve(path, '..'), {recursive: true, mode: 0o700});
  const temporary = `${path}.tmp-${process.pid}-${Date.now()}`;
  writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, {mode});
  chmodSync(temporary, mode);
  renameSync(temporary, path);
}

export function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

export function newState({runId, root, plan}) {
  return {
    schemaVersion: 'stepv2-k6-operator-state-v1',
    runId,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    status: 'active',
    plan,
    phases: Object.fromEntries(PHASES.map(phase => [phase, {
      status: 'pending', attempts: 0, updatedAt: null, postconditions: {}, error: null,
    }])),
    highestPassingRps: null,
    terminalReason: null,
  };
}

export function saveState(runDir, state) {
  state.updatedAt = new Date().toISOString();
  atomicJson(join(runDir, 'state.json'), state);
}

export function phaseStart(runDir, state, phase) {
  const record = state.phases[phase];
  if (!record) throw new Error(`unknown phase ${phase}`);
  record.status = 'running';
  record.attempts += 1;
  record.updatedAt = new Date().toISOString();
  record.error = null;
  saveState(runDir, state);
}

export function phaseComplete(runDir, state, phase, postconditions = {}) {
  const record = state.phases[phase];
  record.status = 'complete';
  record.updatedAt = new Date().toISOString();
  record.postconditions = postconditions;
  record.error = null;
  saveState(runDir, state);
}

export function phaseFailed(runDir, state, phase, error) {
  const record = state.phases[phase];
  record.status = 'failed';
  record.updatedAt = new Date().toISOString();
  record.error = String(error?.message || error);
  saveState(runDir, state);
}

export function acquireLock(root) {
  mkdirSync(root, {recursive: true, mode: 0o700});
  chmodSync(root,0o700);
  const lock = join(root, '.lock');
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      mkdirSync(lock, {mode: 0o700});
      writeFileSync(join(lock, 'owner'), `${process.pid}\n`, {mode: 0o600});
      return () => rmSync(lock, {recursive: true, force: true});
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const ownerPath = join(lock, 'owner');
      const owner = existsSync(ownerPath) ? Number(readFileSync(ownerPath, 'utf8').trim()) : NaN;
      if (!Number.isInteger(owner) || owner < 1) throw new Error(`operator lock owner is invalid at ${lock}; inspect it manually`);
      try {
        process.kill(owner, 0);
        throw new Error(`another k6 operator command (pid ${owner}) owns ${lock}`);
      } catch (probe) {
        if (probe?.code !== 'ESRCH') throw probe;
      }
      rmSync(lock, {recursive: true, force: true});
    }
  }
  throw new Error(`could not acquire operator lock at ${lock}`);
}

export function activeRun(root) {
  const path = join(root, 'active-run');
  if (!existsSync(path)) return null;
  const runId = readFileSync(path, 'utf8').trim();
  if (!runId) return null;
  if (!/^stepv2-k6-[a-z0-9-]+$/.test(runId)) throw new Error('active-run contains an unsafe run ID');
  const runDir = join(root, 'runs', runId);
  if (!existsSync(join(runDir, 'state.json'))) return null;
  return {runId, runDir, state: readJson(join(runDir, 'state.json'))};
}

export function setActive(root, runId) {
  const temporary = join(root, `active-run.tmp-${process.pid}`);
  writeFileSync(temporary, `${runId}\n`, {mode: 0o600});
  renameSync(temporary, join(root, 'active-run'));
}

export function clearActive(root, runId) {
  const path = join(root, 'active-run');
  if (existsSync(path) && readFileSync(path, 'utf8').trim() === runId) rmSync(path, {force: true});
}
