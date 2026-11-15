import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { test } from "node:test";
import { LuaFactory } from "wasmoon";
import { unzipSync } from "fflate";
import { build, runtimeFiles } from "../scripts/build.mjs";

const runtime = await runtimeFiles();
const suites = (await readdir("tests")).filter((name) => name.endsWith("_test.lua"));

async function runSuite(t, suite, archive) {
  const factory = new LuaFactory();
  for (const file of runtime.filter((name) => name.endsWith(".lua"))) {
    const source = archive ? Buffer.from(archive[file]).toString("utf8") : await readFile(file, "utf8");
    await factory.mountFile(file, source);
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

test("packaged runtime passes the same Lua scenarios and contains only plugin files", async (t) => {
  const archive = unzipSync(await readFile(await build()));
  assert.deepEqual(Object.keys(archive).sort(), [...runtime].sort());
  const manifest = JSON.parse(Buffer.from(archive["plugin.json"]).toString("utf8"));
  assert.equal(manifest.name, "BoneCollector");
  assert.deepEqual(manifest.requiredPermissions, []);
  assert.deepEqual(manifest.optionalPermissions, []);
  assert.equal(manifest.version, JSON.parse(await readFile("package.json", "utf8")).version);
  for (const suite of suites) {
    await t.test(suite, (child) => runSuite(child, suite, archive));
  }
});
