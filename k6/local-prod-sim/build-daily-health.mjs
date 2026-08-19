#!/usr/bin/env node
import fs from "node:fs";

const argument = (name, fallback = null) => {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
};
const lines = (path) => fs.existsSync(path)
  ? fs.readFileSync(path, "utf8").split("\n").filter(Boolean)
  : [];
const json = (path) => JSON.parse(fs.readFileSync(path, "utf8"));
const write = (document) => {
  const output = argument("--output");
  const temporary = `${output}.tmp.${process.pid}`;
  fs.writeFileSync(temporary, `${JSON.stringify(document, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, output);
};

if (process.argv[2] === "server") {
  const memorySamples = lines(argument("--memory-samples")).map((line) => {
    const [timestamp, kib] = line.split(" ");
    return { timestamp, availableBytes: Number(kib) * 1024 };
  }).filter((sample) => Number.isFinite(Date.parse(sample.timestamp)) && Number.isFinite(sample.availableBytes));
  const pre = json(argument("--pm2-pre"));
  const post = json(argument("--pm2-post"));
  const logs = fs.readFileSync(argument("--logs"), "utf8");
  const count = (regex) => [...logs.matchAll(regex)].length;
  write({
    schemaVersion: "server-health-v1",
    collectorVersion: 1,
    startedAt: argument("--started-at"),
    endedAt: argument("--ended-at"),
    parseStatus: memorySamples.length > 0 ? "ok" : "missing-memory-samples",
    windowComplete: argument("--window-complete") === "true",
    memorySamples,
    deadlockDelta: Number(argument("--deadlocks-post")) - Number(argument("--deadlocks-pre")),
    classifiedLogCounts: {
      p2028: count(/\bP2028\b/g),
      poolTimeout: count(/(?:pool timeout|Timed out fetching a new connection)/gi),
      deadlock: count(/(?:deadlock detected|\b40P01\b)/gi),
      oom: count(/(?:heap out of memory|allocation failed|fatal process out of memory)/gi),
    },
    pm2: { pre, post },
    resolution: {
      samples: Number(argument("--resolution-samples")),
      maxLagMs: Number(argument("--resolution-max-lag")),
      failures: Number(argument("--resolution-failures")),
      dedicatedDrainSeconds: Number(argument("--dedicated-drain-seconds")),
      globalDrainSeconds: Number(argument("--global-drain-seconds")),
      consecutiveZeroSamples: Number(argument("--consecutive-zero-samples")),
      dedicatedDrained: argument("--dedicated-drained") === "true",
      globalDrained: argument("--global-drained") === "true",
    },
    kernelOomParseStatus: argument("--kernel-oom-parse-status", "missing"),
    kernelOomKills: Number(argument("--kernel-oom-kills", "0")),
  });
} else {
  throw new Error("build-daily-health requires server");
}
