import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { test } from "node:test";
import { LuaFactory } from "wasmoon";
import { unzipSync } from "fflate";
import { build, runtimeFiles } from "../scripts/build.mjs";

const runtime = await runtimeFiles();
const source = ["main.lua", ...(await readdir("src")).filter((name) => name.endsWith(".lua")).map((name) => `src/${name}`)];
const suites = (await readdir("tests")).filter((name) => name.endsWith("_test.lua"));

async function runSuite(t, suite, archive) {
  const factory = new LuaFactory();
  for (const file of (archive ? runtime : source).filter((name) => name.endsWith(".lua"))) {
    const contents = archive ? Buffer.from(archive[file]).toString("utf8") : await readFile(file, "utf8");
    await factory.mountFile(file, contents);
  }
  const lua = await factory.createEngine();
  t.after(() => lua.global.close());
  await lua.doString('assert(_VERSION == "Lua 5.4"); package.path = "./?.lua;" .. package.path');
  const cases = await lua.doString(await readFile(`tests/${suite}`, "utf8"));
  assert.ok(cases > 0);
  t.diagnostic(`${cases} Lua scenarios passed`);
}

for (const suite of suites) {
  test(`Lua 5.4: ${suite}`, (t) => runSuite(t, suite));
}

test("packaged Death Tracker runs the entrypoint scenarios without legacy pickup code", async (t) => {
  const archive = unzipSync(await readFile(await build()));
  assert.deepEqual(Object.keys(archive).sort(), [...runtime].sort());
  const manifest = JSON.parse(Buffer.from(archive["plugin.json"]).toString("utf8"));
  assert.equal(manifest.name, "Death Tracker");
  assert.deepEqual(manifest.requiredPermissions, ["chatAccess"]);
  assert.deepEqual(manifest.optionalPermissions, ["trackingAccess"]);
  assert.equal(manifest.version, JSON.parse(await readFile("package.json", "utf8")).version);
  for (const suite of ["death_tracker_test.lua"]) {
    await t.test(suite, (child) => runSuite(child, suite, archive));
  }
});
