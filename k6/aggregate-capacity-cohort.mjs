#!/usr/bin/env node

import fs from "node:fs";

import { ENDPOINTS } from "./harness-contract.mjs";
import { aggregateCapacityCohort } from "./cohort-aggregator.mjs";

const summaries = [];
const rawPaths = [];
const evidencePaths = [];
let outputPath = null;
for (let index = 2; index < process.argv.length; index += 1) {
  const argument = process.argv[index];
  if (argument === "--summary") summaries.push(process.argv[++index]);
  else if (argument === "--raw") rawPaths.push(process.argv[++index]);
  else if (argument === "--evidence") evidencePaths.push(process.argv[++index]);
  else if (argument === "--out") outputPath = process.argv[++index];
  else throw new Error(`unknown argument: ${argument}`);
}

function readRaw(path) {
  return fs
    .readFileSync(path, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        throw new Error(`${path}:${index + 1}: ${error.message}`);
      }
    });
}

const result = aggregateCapacityCohort({
  summaries: summaries.map((path) => JSON.parse(fs.readFileSync(path, "utf8"))),
  rawRuns: rawPaths.map(readRaw),
  evidences: evidencePaths.map((path) =>
    JSON.parse(fs.readFileSync(path, "utf8")),
  ),
  configuredEndpoints: ENDPOINTS.map((endpoint) => endpoint.key),
});
const encoded = `${JSON.stringify(result, null, 2)}\n`;
if (outputPath) fs.writeFileSync(outputPath, encoded);
process.stdout.write(encoded);
if (!result.valid) process.exitCode = 1;
