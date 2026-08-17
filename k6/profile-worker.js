// Attaches to a Node inspector port and captures a CPU profile.
// pm2's `profile:cpu` profiles the pm2 God daemon, not the app worker, so we
// drive the worker's own inspector directly. Node 24 has a global WebSocket,
// so this needs no dependencies.
const durationMs = Number(process.argv[2] || 30000);
const out = process.argv[3] || "/tmp/worker.cpuprofile";

async function main() {
  const list = await fetch("http://127.0.0.1:9229/json/list").then((r) => r.json());
  const target = list[0];
  if (!target) throw new Error("no inspector target — did SIGUSR1 land?");
  console.log("attaching to:", target.title || target.id);

  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();
  const send = (method, params) =>
    new Promise((resolve, reject) => {
      const msgId = ++id;
      pending.set(msgId, { resolve, reject });
      ws.send(JSON.stringify({ id: msgId, method, params }));
    });

  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
    }
  });

  await new Promise((r) => ws.addEventListener("open", r));
  await send("Profiler.enable");
  // 100us sampling: fine enough to attribute short handlers without
  // meaningfully perturbing a process that is already CPU-saturated.
  await send("Profiler.setSamplingInterval", { interval: 100 });
  await send("Profiler.start");
  console.log(`profiling ${durationMs}ms...`);
  await new Promise((r) => setTimeout(r, durationMs));
  const { profile } = await send("Profiler.stop");
  require("fs").writeFileSync(out, JSON.stringify(profile));
  console.log("wrote", out, "samples:", profile.samples.length);
  ws.close();
}

main().catch((e) => {
  console.error("FAILED:", e.message);
  process.exit(1);
});
