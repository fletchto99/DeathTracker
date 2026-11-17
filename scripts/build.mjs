import { mkdir, readFile, writeFile } from "node:fs/promises";
import { zipSync } from "fflate";

export async function runtimeFiles() {
  return ["main.lua", "plugin.json", "src/deathtracker.lua", "src/group_capture.lua", "src/names.lua"];
}

export async function build() {
  const manifest = JSON.parse(await readFile("plugin.json", "utf8"));
  const files = await runtimeFiles();
  const entries = Object.fromEntries(await Promise.all(
    files.map(async (name) => [name, [new Uint8Array(await readFile(name)), { mtime: new Date("2026-01-01T00:00:00Z") }]]),
  ));
  const output = `dist/DeathTracker-${manifest.version}.zip`;
  await mkdir("dist", { recursive: true });
  await writeFile(output, zipSync(entries));
  return output;
}

if (process.argv[1] && import.meta.url === (await import("node:url")).pathToFileURL(process.argv[1]).href) {
  console.log(await build());
}
