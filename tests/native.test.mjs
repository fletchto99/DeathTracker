import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { LuaFactory } from "wasmoon";
import { unzipSync } from "fflate";
import { build, runtimeFiles } from "../scripts/build.mjs";

const runtime = await runtimeFiles();

async function runSuite(t, archive, suite = "deathtracker_test.lua") {
  const factory = new LuaFactory();
  for (const file of runtime.filter((name) => name.endsWith(".lua"))) {
    const contents = archive ? Buffer.from(archive[file]).toString("utf8") : await readFile(file, "utf8");
    await factory.mountFile(file, contents);
  }
  if (suite === "group_capture_test.lua") {
    await factory.mountFile("src/group_capture.lua", await readFile("src/group_capture.lua", "utf8"));
  }
  const lua = await factory.createEngine();
  t.after(() => lua.global.close());
  await lua.doString('assert(_VERSION == "Lua 5.4"); package.path = "./?.lua;" .. package.path');
  const cases = await lua.doString(await readFile(`tests/${suite}`, "utf8"));
  assert.ok(cases > 0);
  t.diagnostic(`${cases} Lua scenarios passed`);
}

test("Lua 5.4: Death Tracker", (t) => runSuite(t));
test("Deferred group capture (source only)", (t) => runSuite(t, undefined, "group_capture_test.lua"));

test("packaged Death Tracker runs the entrypoint scenarios", async (t) => {
  const metadata = JSON.parse(await readFile("package.json", "utf8"));
  const lockfile = JSON.parse(await readFile("package-lock.json", "utf8"));
  const output = await build();
  assert.equal(output, `dist/DeathTracker-${metadata.version}.zip`);
  const archive = unzipSync(await readFile(output));
  assert.deepEqual(Object.keys(archive).sort(), [...runtime].sort());
  assert.deepEqual(Object.keys(archive).sort(), [
    "main.lua", "plugin.json", "src/deaths.lua", "src/deathtracker.lua", "src/names.lua",
  ]);
  assert.equal(metadata.name, "deathtracker");
  assert.equal(lockfile.name, "deathtracker");
  assert.equal(lockfile.packages[""].name, "deathtracker");
  assert.equal(metadata.repository.url, "https://github.com/fletchto99/DeathTracker.git");
  assert.equal(metadata.homepage, "https://github.com/fletchto99/DeathTracker");
  const manifest = JSON.parse(Buffer.from(archive["plugin.json"]).toString("utf8"));
  assert.equal(manifest.name, "Death Tracker");
  assert.equal(manifest.hasRibbonIcon, true);
  assert.equal(manifest.hasSettingsIcon, true);
  assert.deepEqual(manifest.requiredDependencies, {});
  assert.deepEqual(manifest.optionalDependencies, {});
  assert.deepEqual(manifest.requiredPermissions, ["chatAccess"]);
  assert.deepEqual(manifest.optionalPermissions, []);
  assert.equal(manifest.version, metadata.version);
  assert.equal(lockfile.version, metadata.version);
  assert.equal(lockfile.packages[""].version, metadata.version);
  for (const contents of Object.values(archive)) {
    assert.doesNotMatch(Buffer.from(contents).toString("utf8"), /prettyui|GetTrackingID|trackingAccess|group_capture|FRIENDS2|GROUP_CHILD/);
  }
  await runSuite(t, archive);
});
