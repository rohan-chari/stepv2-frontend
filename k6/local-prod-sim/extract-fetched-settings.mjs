#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { PERFORMANCE_REGISTRY_V1 } from "./daily-capacity-contract.mjs";

const index = process.argv.indexOf("--artifact-dir");
const artifactDir = index >= 0 ? process.argv[index + 1] : null;
const outputIndex = process.argv.indexOf("--output");
const output = outputIndex >= 0 ? process.argv[outputIndex + 1] : null;
if (!artifactDir || !output) throw new Error("missing --artifact-dir or --output");
process.chdir(artifactDir);
const artifactRequire = createRequire(path.join(path.resolve(artifactDir), "package.json"));
const { KNOWN_FLAGS } = artifactRequire("./src/shared/config/appSettings.js");
const { readPerformanceFlags } = artifactRequire("./src/shared/config/performanceFlags.js");
const accessedEnvironmentKeys = new Set();
const defaults = readPerformanceFlags(new Proxy({}, {
  get(_target, property) {
    accessedEnvironmentKeys.add(String(property));
    return undefined;
  },
}));
const inferredRegistry = {};
for (const env of accessedEnvironmentKeys) {
  const booleanProbe = readPerformanceFlags({ [env]: "true" });
  const integerHighProbe = readPerformanceFlags({ [env]: "999999999" });
  const changed = Object.keys(defaults).filter((semantic) =>
    booleanProbe[semantic] !== defaults[semantic] || integerHighProbe[semantic] !== defaults[semantic]);
  if (changed.length !== 1) throw new Error(`cannot infer fetched-main performance mapping for ${env}`);
  const semantic = changed[0];
  if (typeof defaults[semantic] === "boolean" && booleanProbe[semantic] === true) {
    inferredRegistry[semantic] = { env, type: "boolean", default: defaults[semantic] };
  } else if (Number.isInteger(defaults[semantic]) && Number.isInteger(integerHighProbe[semantic])) {
    const low = readPerformanceFlags({ [env]: "-999999999" })[semantic];
    inferredRegistry[semantic] = { env, type: "integer", default: defaults[semantic], min: low, max: integerHighProbe[semantic] };
  } else {
    throw new Error(`unsupported fetched-main performance mapping for ${semantic}`);
  }
}
for (const [semantic, mapping] of Object.entries(PERFORMANCE_REGISTRY_V1)) {
  if (!(semantic in defaults) || defaults[semantic] !== mapping.default) {
    throw new Error(`fetched-main performance default drift for ${semantic}`);
  }
  const probeValue = mapping.type === "boolean" ? "true" : String(mapping.max);
  const probed = readPerformanceFlags({ [mapping.env]: probeValue });
  if (probed[semantic] !== (mapping.type === "boolean" ? true : mapping.max)) {
    throw new Error(`fetched-main performance environment mapping drift for ${semantic}`);
  }
  for (const other of Object.keys(PERFORMANCE_REGISTRY_V1)) {
    if (other !== semantic && probed[other] !== defaults[other]) {
      throw new Error(`fetched-main performance environment mapping collision for ${semantic}`);
    }
  }
  if (JSON.stringify(inferredRegistry[semantic]) !== JSON.stringify(mapping)) {
    throw new Error(`fetched-main performance registry v1 drift for ${semantic}`);
  }
}
const document = {
  schemaVersion: "daily-k6-fetched-defaults-v1",
  dbDefaults: KNOWN_FLAGS,
  performanceRegistry: inferredRegistry,
};
fs.writeFileSync(output, `${JSON.stringify(document)}\n`, { mode: 0o600 });
