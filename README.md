# BoneCollector

A native **RuneScape 3 Lua plugin** that automatically considers every nearby
other player and counts bones you collect that can be conservatively matched
to their disappearance. Click **BoneCollector** in game to open rows such as
**"You have picked up 3 Alice bones"**. It uses the official developer API,
not Alt1, RuneLite, or VoragoSync.

**These are inferred bone collections, not confirmed deaths or bone ownership.**
The API exposes neither a player's death state nor the deceased person's name
on bones. Teleporting and leaving view also remove players. Bone removal can
mean another person collected it or it left view.

This is a focused **developer-beta prototype**, not a moderated live-game
release. Automated tests exercise the Lua implementation and mocked native
contracts; **it has not been verified in the RuneScape client**.

**0.2.1 is a diagnostic build, not a pickup fix.** A direct ground pickup was
reported not to count in 0.2.0. Its cause is still unknown. This build records
the evidence and rejection reasons without relaxing the counting rules.
**Area-loot rows and Loot All still do not count**; their native action mapping
and collection evidence need an in-client trace before support can be enabled.

## Install in the developer beta

1. Follow the official [developer environment setup](https://developer.runescape.com/rs/tutorial/1helloworld.html).
   Locate the beta cache containing `.jcache` files. On Windows the default is
   `C:\ProgramData\Jagex\RuneScape-BETA`.
2. Install **[PrettyUI](https://github.com/PrettyRS/prettyui), mod.io ID 6398181**
   through the native plugin system. Development commands do not automatically
   download dependencies. BoneCollector uses its SimpleView, Window and SimpleButton APIs;
   the optional diagnostic snapshot also needs Window's TextField support.
   no PrettyUI code or resources are bundled.
3. Create `dev_plugins\bonecollector` inside that cache. Copy **only** `main.lua`,
   `plugin.json`, and the `src` directory from this repository into it. The result
   should contain `dev_plugins\bonecollector\main.lua`, not another nested folder.
4. Open the beta console with **Alt + the key below Esc**, then run:

   ```text
   prf
   pon bonecollector
   ```

Use `prl bonecollector` after updating files, or `poff bonecollector` to disable.
The client needs only the Lua files and PrettyUI; **Node.js is not a runtime
requirement**.

Alternatively, developers can run `npm ci` and `npm run build`, then extract
`dist\BoneCollector-0.2.1.zip` into the same `dev_plugins\bonecollector` directory.
The ZIP has the runtime files at its root. It is a development install, not
evidence of moderation approval.

## Open and use

Monitoring starts automatically with **all nearby other players**, whether or
not they are friends. There is no name input, allowlist, or 20-name tracking
limit. The local player is excluded. Matching remains case-insensitive and
treats underscores as spaces; counters use each collected player's display name.
An unavailable or unresolvable name is skipped rather than assigned a fake identity.

Click the **BoneCollector** button near the upper-left of the in-game UI.
It opens a scrollable counts window with one row per counted player:

```text
You have picked up 3 Alice bones
You have picked up 1 Bob bones
```

Rows update after qualifying pickups and are sorted by name. Players with no
collected bones do not get a row. There is no fixed row limit; scroll to see
additional names. Close the window with its close button and reopen it with
**BoneCollector**. Repeated clicks raise the same window rather than opening
duplicates. Unlock RuneScape's interface to move or resize the window.

The same counts and diagnostics remain available through **Plugin Hub > Manage >
BoneCollector > Settings**, or the ribbon icon in the native **Plugins** window.
The obsolete tracked-name settings have been removed.

Wait at least three seconds with the other player visible. For a qualifying event,
they must have been stationary on their last tile for at least 0.6 seconds.
After they disappear and a single ordinary bone appears there, stand within
one tile, choose its ground **Take** action, and collect it individually.
The local pickup area must have no other observed players within one tile.
Credit appears only after the attribution window has settled (at least 2.4
seconds after the bone appears).

The current prototype intentionally supports **English `Take` / `OP_OBJ3` and
`config.Obj.BONES` only**. It does not count area loot, loot-interface actions,
multiple bones on one tile, noted bones, auto-loot, or other bone types.
Unsupported actions are skipped, not guessed. A full backpack or failed click
does not count.

Names and per-name counts are saved after each collection with `PersistentDB`.
Name changes are separate names, not automatically linked accounts. Storage
is local to the installation and client type, shared across characters; beta
and live data are separate. There is no service, upload, chat scraping, or
network permission. Avoid running this prototype in multiple clients at once:
the native database is shared and does not expose an atomic counter operation.

If saving fails, the panel says **NOT SAVED**. Changes remain in memory; use
**Retry save** before unloading. Invalid saved data stops startup rather than
silently overwriting history.

### Upgrading from 0.1.0 or 0.2.0

When ready to test, disable the plugin with `poff bonecollector`, copy all eight
runtime files from the 0.2.1 ZIP, then run `pon bonecollector`. The two new files
are `src\diagnostics.lua` and `src\loot_probe.lua`; copy them along with the six
existing files. **Do not clear the plugin's persistent database.** Version 0.2.0
totals use the same schema and are left unchanged by loading this build.
Version 0.1.0 totals are automatically migrated,
including totals for players no longer in the old allowlist. An old empty
allowlist no longer disables tracking.

The old list is used only to preserve existing display-name capitalization
during migration, not as a filter. Where the old version retained a total but
not the display name, its saved lowercase key is displayed until a new
qualifying collection supplies the current display case. Zero totals are
preserved but do not produce rows. If migration cannot be saved, old storage
is left intact, totals remain available in memory, and **Retry save** persists
the upgraded data.

## What qualifies, and what does not

A match requires all of these observations:

- One fresh, sufficiently observed **other player** disappears on the exact
  bone tile, including its level, within 1.2 seconds of the bone appearing.
  Both event orders are supported. Other recent occupants, additional candidate
  departures, reappearances, or multiple bone appearances reject the match.
- A **new single ordinary bone** appears after the scene baseline. Existing
  ground items are never retrospectively attributed. `isOwner` is used only
  to reject locally owned or unknown-ownership stacks, never to name the owner.
- A specific, supported **Take** selection resolves to that ground stack's
  single bone, with an unchanged backpack baseline and a nearby local player.
- Within two seconds of that selection, the exact ground bone disappears
  **and** the backpack gains exactly one ordinary bone, with no changes in
  other item totals, **in the same server packet**. `ServerLogic` closes the
  packet. Either inventory/ground callback order is accepted; split-packet
  evidence is deliberately rejected.

A disappearance, click, ground loss, or inventory gain **alone never increments
a counter**. Other menu selections, competing bone changes, movement away,
backpack loss, and timeouts invalidate pending evidence. Uncollected candidates
expire after 30 seconds. World/region changes and updates, game-state changes,
local identity/level changes, large local movement, inventory replacement, and
unresolved proxies clear transient state and establish a fresh baseline.
Malformed API data stops monitoring with a visible error.

Each disappearance can be consumed only once. Re-picking the same candidate,
re-dropping bones, or reloading with bones already on the ground does not create
a new death token. A backpack bone loss also suppresses new candidates for five
seconds. A second credit needs a **new, stably observed disappearance and new
collection evidence**.

**Residual uncertainty:** even all those signals cannot prove provenance. A
teleport plus a coincident bone drop, or an indistinguishable same-item inventory
gain coinciding with someone else's pickup, can look the same to this API.
There is no durable unique bone ID, so absolute deduplication across trading,
re-drops, reloads, and new disappearance events is impossible. This prototype
does not promise zero false positives and intentionally accepts false negatives.
Do not treat its counts as proof or use it for competitive/PvP tracking.

## Diagnose the direct ground pickup first

Diagnostics are **off by default**. They print to the client console and keep
a bounded in-memory snapshot: the latest 120 lines, at most 24,000 bytes, with
truncation reported. No trace is saved to PersistentDB or sent anywhere.
Turning diagnostics off freezes the capture. Enabling them again starts a new
capture; unloading/reloading loses it. Normal counting remains active and still
saves a count if all existing conditions pass.

When ready for a short test:

1. Enable **Diagnostics (this session)** in BoneCollector. Close the counts
   window and keep the area-loot interface closed for this first test. With a
   consenting player in a noncompetitive beta location that leaves bones,
   remain nearby for at least three seconds before the test death. Keep them
   stationary for the final 0.6 seconds.
2. Observe one disappearance and bone appearance. The count must not change
   yet. Stand within one tile of the bone, with a free backpack slot and no
   other player within one tile of it, and select the bone's direct ground
   **Take**. Wait three seconds; note whether it actually entered the backpack.
   Do not repeat clicks, hop worlds, or try area loot during this capture.
3. Reopen BoneCollector, turn diagnostics **off**, and click **Show diagnostic
   snapshot**. Click inside the snapshot field, use **Ctrl+A**, **Ctrl+C**,
   and paste into a local text file before reloading. The field is a copy;
   editing it cannot change counters or the retained trace. **Refresh snapshot**
   replaces its contents with the retained trace.

Native clipboard shortcuts and snapshot rendering still need a client check.
If copying is unavailable, open the client console with **Alt + the key below
Esc** and take screenshots of the relevant lines. There is no assumed automatic
log-file location or clipboard API. If the UI itself fails, capture the console
error instead; do not reset saved counters.

The capture uses anonymous player/stack handles, not display names or menu
subjects. It includes tile coordinates and object IDs, so keep it local and
review/redact it before sharing; do not export other players' information.

| Trace marker | What it establishes |
| --- | --- |
| `readiness`, `observed_player`, `thresholds` | Whether monitoring had a baseline and which observation limits applied. |
| `player_removed`, `departure` | Proxy validity/cache matching, last tile, name availability, scene/observation/stationary ages, and eligibility. |
| `player_cache_lost`, `reset`, `*_event_ignored` | A missing removal event, invalid proxy, lifecycle interruption, or monitoring not ready. |
| `ground_*`, `birth` | Actual object config ID/name, tile, ownership, bone counts, and whether a fresh candidate was created. |
| `bone_ground_op`, `menu`, `menu_target` | Available bone operations and the exact selected action type, verb, stack index, object, local tile, and cached target. |
| `pickup_block`, `skip` | The failed proximity, crowding, ambiguity, ownership, or other eligibility check. |
| `inventory`, `other_inventory_update`, `packet_evidence`, `server_boundary` | Actual backpack delta and whether ground loss and inventory gain arrived in the same packet. |
| `collection_evidence`, `count` | Collection evidence passed, then attribution settled and a counter increment was attempted. |

This is evidence gathering, not confirmation of a cause. Do not broaden timing
or proximity limits, or accept inventory gain alone, just to force a count.
After a real direct pickup is understood, negative controls should still reject
a disappearance alone, a failed/full-backpack click, another player's pickup,
ambiguous bones, re-dropped bones without a new disappearance, and a world hop.

### Area-loot investigation (still not supported)

The optional probe activates with diagnostics. It observes only the native
`TOPLEVEL_V2_LOOT` interface and its known item/Loot All component subtrees,
using named `ONCLICK`/`ONOP` listeners that return `true` and never send actions
or suppress existing listeners. It reports `MiniMenuEntrySelected` payloads
for that interface, visible component operation names, and snapshots of `LOOT`,
the backpack, and ground objects. It detaches on disable, lifecycle reset, UI
replacement or shutdown. Unavailable probe APIs are explicitly reported as
`area_probe_error`; they do not enable counting.

The known identifiers were cross-checked against the public API stub
[source CSV dump at revision 230702b](https://github.com/FriendlyDevelopment/runescape-api-stubs/tree/230702b372e83a40b4cfdde01f5a18c5266ec28c/csvs),
not inferred from a button label:

| Native identifier | Dump value |
| --- | --- |
| `id.Interface.TOPLEVEL_V2_LOOT` | 1622 |
| `config.Inv.LOOT` / `id.Inv.LOOT` | 773 |
| `id.Component.TOPLEVEL_V2_LOOT__SLOT_LAYER` | 106299402 (static component 10) |
| `id.Component.TOPLEVEL_V2_LOOT__ITEM_LAYER` | 106299403 (static component 11) |
| `id.Component.TOPLEVEL_V2_LOOT__LOOT_ALL_BUTTON_LAYER` | 106299407 (static component 15) |
| `id.Component.TOPLEVEL_V2_LOOT__LOOT_ALL_BUTTON_HIT_LAYER` | 106299411 (static component 19) |
| `id.Component.TOPLEVEL_V2_LOOT__LOOT_ALL_BUTTON_ACTIVE_LAYER` | 106299413 (static component 21) |

Runtime code uses the native named constants, not hardcoded numeric fallbacks.
These identify controls, **not** which operation collects an item. The documented
`componentData` gives `component`, `opIndex`, and optional `objConfig`, but no
ground entity/tile/stack index. Inventory slots contain `obj` and `count` only.
There is no verified row-to-ground mapping, Loot All callback shape, or
transaction identifier linking aggregate removals to local backpack gains.

After direct Take is diagnosed, separate short captures can test an individual
area-loot row and Loot All with ordinary bones plus another item, then a
partial/full-backpack outcome. Enable diagnostics, open the loot window and
wait a second for hooks, perform **one** action, then disable diagnostics and
save the snapshot. Include `area_menu`/`area_hook`, component/operation IDs,
`area_inventory_event` and packet ordering. An `area_probe_truncated` record
means the bounded capture was incomplete.

**No area-loot count is expected in 0.2.1.** Automated probe tests establish
observation and cleanup behavior, not actual client payloads, successful
aggregate attribution, or correctness of Loot All under partial outcomes.
Actual death drops, callback ordering, proxy comparisons, UI/clipboard behavior,
and the same-packet assumption all remain in-client verification items.

## Development

With Node.js 22 or newer (the initial checks used Node 24):

```powershell
npm ci
npm run check
npm run build
```

Tests run the actual Lua modules under **Lua 5.4 via Wasmoon**. The native client
uses Lua **5.4.8**; the test runtime is not the client. The suite covers matching,
false-positive controls, both event orders, invalid proxies, native payload
translation, all-player attribution, legacy-data migration, more than 20 rows,
the counts-window opener, persistence errors, UI teardown, and lifecycle resets. It also
builds the ZIP and reruns the same scenarios using its packaged Lua files.
Diagnostic tests cover bounded snapshots, direct rejection/packet traces,
strict loot-interface scoping, pass-through hooks, and cleanup/errors.

- `src\matcher.lua`: API-independent, bounded-time correlation state machine.
- `src\app.lua`: guarded native event adapter, copied snapshots and diagnostics.
- `src\store.lua`: persistent counters, display names and legacy-data migration.
- `src\view.lua`: in-game opener, counts window and native settings/content panels.
- `src\diagnostics.lua`: bounded, session-only trace snapshot.
- `src\loot_probe.lua`: read-only, opt-in area-loot contract investigation.

Official references: [events](https://developer.runescape.com/rs/core/events.html),
[MiniMenu](https://developer.runescape.com/rs/game/minimenu.html),
[players](https://developer.runescape.com/rs/game/entity/playerentity.html),
[ground objects](https://developer.runescape.com/rs/game/entity/objstackentity.html),
[inventory](https://developer.runescape.com/rs/game/inventory.html),
and [PersistentDB](https://developer.runescape.com/rs/core/persistentdb.html).
Current public [VoragoSync](https://github.com/fletchto99/VoragoSync) conventions
informed native lifecycle and test setup; this is a separate implementation.

Before any live-game distribution, review the official
[plugin guidelines](https://developer.runescape.com/rs/submission/guidelines.html)
and complete moderation. Information about other players is specifically
subject to review, and exporting it is prohibited. A public source repository
does not imply Jagex approval. A real author-selected `contactEmailAddress`
must also be supplied in `plugin.json` for submission; this prototype does not
invent or publish a contact address.
