#!/usr/bin/env node
import fs from "node:fs";

const argument = (name) => {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
};
const db = argument("--capacity-db");
if (!/^stepv2_capacity_[A-Za-z0-9_]+$/.test(db)) throw new Error("capacity DB name invalid");
const pgbouncer = fs.readFileSync(argument("--pgbouncer"), "utf8");
const mappings = [];
let inDatabases = false;
for (const rawLine of pgbouncer.split("\n")) {
  const line = rawLine.replace(/;.*/, "").trim();
  if (/^\[.*\]$/.test(line)) { inDatabases = line === "[databases]"; continue; }
  if (inDatabases && line) {
    const match = /^([^=\s]+)\s*=\s*(.+)$/.exec(line);
    if (!match) throw new Error("PgBouncer database mapping is malformed");
    mappings.push({ key: match[1], value: match[2] });
  }
}
const duplicateKeys = mappings.filter((mapping, index) => mappings.findIndex((candidate) => candidate.key === mapping.key) !== index);
if (duplicateKeys.length) throw new Error("PgBouncer database mapping is ambiguous");
const exactMappings = mappings.filter((mapping) => mapping.key === db);
const wildcardMappings = mappings.filter((mapping) => mapping.key === "*");
const mapping = exactMappings[0] || wildcardMappings[0];
if (!mapping || exactMappings.length > 1 || (!exactMappings.length && wildcardMappings.length !== 1) ||
    !/\bhost=127\.0\.0\.1\b/.test(mapping.value) || !/\bport=55432\b/.test(mapping.value) ||
    (/\bdbname=/.test(mapping.value) && !new RegExp(`\\bdbname=${db}\\b`).test(mapping.value))) {
  throw new Error("PgBouncer database mapping does not target the dedicated local DB");
}
const cpu = Number(argument("--guest-cpu"));
const memoryBytes = Number(argument("--guest-memory-bytes"));
const arch = argument("--guest-arch");
if (cpu !== 2 || memoryBytes < 1.8 * 1024 ** 3 || memoryBytes > 2.2 * 1024 ** 3 || !/^(?:aarch64|arm64)$/.test(arch)) {
  throw new Error("Lima CPU/memory/architecture drift");
}
const nginx = fs.readFileSync(argument("--nginx-config"), "utf8");
const upstreams = new Map();
for (const match of nginx.matchAll(/\bupstream\s+([A-Za-z0-9._-]+)\s*\{([\s\S]*?)\}/g)) {
  if (upstreams.has(match[1])) throw new Error("nginx upstream is ambiguous");
  const servers = [...match[2].matchAll(/\bserver\s+([^;\s]+)\s*;/g)].map((server) => server[1]);
  upstreams.set(match[1], servers);
}
const isLocalWorkerTarget = (target) => {
  if (/^(?:127\.0\.0\.1|localhost):3002$/.test(target)) return true;
  const named = upstreams.get(target);
  return named?.length === 1 && /^(?:127\.0\.0\.1|localhost):3002$/.test(named[0]);
};
const effective8080Servers = nginx.split(/(?=\bserver\s*\{)/)
  .filter((section) => /\blisten\s+(?:[^;\n]*:)?8080(?:\s|;)/.test(section));
const routedServersValid = effective8080Servers.length > 0 && effective8080Servers.every((section) => {
  const proxyTargets = [...section.matchAll(/\bproxy_pass\s+([^;\s]+)\s*;/g)].map((match) => match[1]);
  if (proxyTargets.length !== 1 || !proxyTargets[0].startsWith("http://")) return false;
  const target = proxyTargets[0].slice("http://".length).replace(/\/$/, "");
  return isLocalWorkerTarget(target);
});
if (!routedServersValid) {
  throw new Error("nginx listener/upstream drift");
}
const routeMatch = argument("--route-match");
if (argument("--host-port-listener") !== "true" || !["true", "deferred"].includes(routeMatch)) {
  throw new Error("Lima 3302→8080→3002 routing proof failed");
}
const document = {
  schemaVersion: "daily-k6-topology-v1",
  limaCpu: cpu,
  limaMemoryBytes: memoryBytes,
  guestArch: arch,
  portForward: "127.0.0.1:3302->guest:8080",
  routingVerified: routeMatch === "true",
  nginxUpstream: "guest:8080->127.0.0.1:3002",
  pgbouncerMapping: `${db}->127.0.0.1:55432/${db}`,
};
const output = argument("--output");
const temporary = `${output}.tmp.${process.pid}`;
fs.writeFileSync(temporary, `${JSON.stringify(document, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(temporary, output);
