import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const bridge = resolve(root, "bridge", "render.mjs");

const result = spawnSync(process.execPath, [bridge], {
  input: JSON.stringify(["flowchart LR\n  A[Start] --> B[Finish]", "not Mermaid"]),
  encoding: "utf8",
});

assert.equal(result.status, 0, result.stderr);
const diagrams = JSON.parse(result.stdout);
assert.equal(diagrams.length, 2);
assert.ok(Array.isArray(diagrams[0]));
assert.match(diagrams[0].flat().map((span) => span.text).join(""), /Start/);
assert.equal(diagrams[1], false);

const invalid = spawnSync(process.execPath, [bridge], { input: "{}", encoding: "utf8" });
assert.notEqual(invalid.status, 0);
assert.match(invalid.stderr, /JSON array/);

console.log("bridge contract passed");
