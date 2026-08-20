#!/usr/bin/env node

import {readFileSync} from 'node:fs';

const USERS = 10_000;
const DEADLINE_SECONDS = 28_800;
const MIN_PASSING_LEVEL_SECONDS = 30 + 180;
const MAX_DB_INTEGER = 2_147_483_647;

export function logicalSpan(rps, seconds) {
  if (!Number.isInteger(rps) || rps < 1 || !Number.isInteger(seconds) || seconds < 1) throw new Error('logical window requires positive integer rate and duration');
  return Math.ceil((rps * seconds + 2) / USERS) + 1;
}

export function validateEightHourEnvelope() {
  const levels = Math.ceil(DEADLINE_SECONDS / MIN_PASSING_LEVEL_SECONDS);
  let nextBase = 1;
  let maximumRps = 0;
  for (let level = 0; level < levels; level += 1) {
    const rps = 50 + level * 10;
    maximumRps = rps;
    // Warm-up, measured stage, and the single permitted retry. This deliberately
    // over-allocates because all three cannot occur at every level in eight hours.
    for (const seconds of [30, 180, 180]) nextBase += logicalSpan(rps, seconds) + 1;
  }
  const maximumSampleSteps = 20 + nextBase;
  const maximumTotalSteps = 100_000 + nextBase * 100;
  if (!Number.isSafeInteger(nextBase) || maximumTotalSteps > MAX_DB_INTEGER) throw new Error('eight-hour monotonic step envelope exceeds the database integer representation');
  return {schemaVersion:'stepv2-capacity-self-validation-v1',deadlineSeconds:DEADLINE_SECONDS,levels,maximumRps,nextLogicalBase:nextBase,maximumSampleSteps,maximumTotalSteps,databaseIntegerMaximum:MAX_DB_INTEGER,valid:true};
}

export function validateDeadlineContract(){const source=readFileSync(new URL('./operator.mjs',import.meta.url),'utf8');const required=['CAPACITY_DEADLINE','withinRunDeadline(state,\'sanitization_resume_validation\'','terminalizeBeforeApproval','terminalizeEarly','deadlineBound','k6 child reached the absolute eight-hour deadline'];const missing=required.filter(fragment=>!source.includes(fragment));if(missing.length)throw new Error(`operator deadline contract is incomplete: ${missing.join(', ')}`);return {valid:true,requiredFragments:required.length};}

if (process.argv[1] && new URL(import.meta.url).pathname === process.argv[1]) process.stdout.write(`${JSON.stringify({...validateEightHourEnvelope(),deadlineContract:validateDeadlineContract()}, null, 2)}\n`);
