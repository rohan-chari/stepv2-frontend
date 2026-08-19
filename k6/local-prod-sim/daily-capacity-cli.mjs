#!/usr/bin/env node
import fs from "node:fs";
import {
  appendDailyRecord,
  buildCompatibilityFingerprint,
  canonicalJson,
  canonicalSnapshotHash,
  classifyCheckpoint,
  parseDailyLog,
  reconcileSnapshot,
  renderDailyRecord,
  replaceDailyRecord,
  selectCheckpoint,
  sha256,
} from "./daily-capacity-contract.mjs";

const command = process.argv[2];
const argument = (name, fallback = null) => {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
};
const json = (path) => JSON.parse(fs.readFileSync(path, "utf8"));
const write = (path, value) => {
  const temporary = `${path}.tmp.${process.pid}`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, path);
};
const writeText = (path, value) => {
  const temporary = `${path}.tmp.${process.pid}`;
  fs.writeFileSync(temporary, value, { mode: 0o600 });
  fs.renameSync(temporary, path);
};

if (command === "fingerprint") {
  process.stdout.write(`${buildCompatibilityFingerprint(json(argument("--input")))}\n`);
} else if (command === "select") {
  const readmePath = argument("--readme");
  const markdown = fs.readFileSync(readmePath, "utf8");
  const records = parseDailyLog(markdown);
  const override = argument("--override");
  write(argument("--output"), {
    ...selectCheckpoint(records, argument("--fingerprint"), override == null ? null : Number(override)),
    day: records.reduce((maximum, record) => Math.max(maximum, record.day), 0) + 1,
    readmeHash: sha256(markdown),
  });
} else if (command === "reconcile") {
  const snapshot = json(argument("--snapshot"));
  const defaults = json(argument("--defaults"));
  const reconciled = reconcileSnapshot(snapshot, defaults.performanceRegistry, defaults.dbDefaults);
  const ignored = [
    ...reconciled.ignoredProductionOnlyKeys.map((key) => `db:${key}`),
    ...reconciled.ignoredProductionOnlyPerformanceKeys.map((key) => `performance:${key}`),
  ].sort();
  write(argument("--output"), {
    ...reconciled,
    snapshotHash: canonicalSnapshotHash({ ...snapshot, ignoredProductionOnlyKeys: ignored }),
  });
} else if (command === "settings-hash") {
  const settings = json(argument("--settings"));
  process.stdout.write(`${sha256(canonicalJson({
    ...settings.localDbSettings,
    [settings.localOverride.key]: settings.localOverride.value,
  }))}\n`);
} else if (command === "classify") {
  write(argument("--output"), classifyCheckpoint({
    summary: json(argument("--summary")),
    raw: json(argument("--raw")),
    loadGenerator: json(argument("--load-health")),
    server: json(argument("--server-health")),
    k6Exit: Number(argument("--k6-exit")),
  }));
} else if (command === "append") {
  appendDailyRecord(argument("--readme"), argument("--expected-hash"), json(argument("--record")));
} else if (command === "correct") {
  const record = json(argument("--record"));
  replaceDailyRecord(argument("--readme"), record.runId, record);
} else if (command === "render") {
  writeText(argument("--output"), renderDailyRecord(json(argument("--record"))));
} else {
  throw new Error("unknown daily-capacity-cli command");
}
