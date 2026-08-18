#!/usr/bin/env node

import fs from "node:fs";

import { validateFixture } from "./harness-contract.mjs";

const path = process.argv[2] || "k6/users.json";
let fixture;
try {
  fixture = JSON.parse(fs.readFileSync(path, "utf8"));
} catch (error) {
  console.error(`cannot read fixture ${path}: ${error.message}`);
  process.exit(1);
}

const result = validateFixture(fixture);
if (!result.ok) {
  console.error(`invalid capacity fixture ${path}:`);
  for (const error of result.errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`valid capacity fixture: ${path}`);
console.log(`revision: ${fixture.metadata.fixtureRevision}`);
console.log(`counts: ${JSON.stringify(fixture.metadata.counts)}`);
console.log(`strata: ${JSON.stringify(fixture.metadata.raceStrata)}`);
