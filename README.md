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

## Install in the developer beta

1. Follow the official [developer environment setup](https://developer.runescape.com/rs/tutorial/1helloworld.html).
   Locate the beta cache containing `.jcache` files. On Windows the default is
   `C:\ProgramData\Jagex\RuneScape-BETA`.
2. Install **[PrettyUI](https://github.com/PrettyRS/prettyui), mod.io ID 6398181**
   through the native plugin system. Development commands do not automatically
   download dependencies. BoneCollector uses its SimpleView, Window and SimpleButton APIs;
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
`dist\BoneCollector-0.2.0.zip` into the same `dev_plugins\bonecollector` directory.
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

### Upgrading from 0.1.0

Disable the plugin with `poff bonecollector`, replace the six runtime files
with the contents of the 0.2.0 ZIP, then run `pon bonecollector`. **Do not clear
the plugin's persistent database.** Existing totals are automatically migrated,
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

## First in-game diagnostic check

Diagnostics are **off by default**, session-only, and print to the local client
console. They include a sequence number, client logic tick, packet number,
anonymous player/stack handles, tile coordinates, object config IDs, ownership,
menu action/verb/index, backpack totals/deltas, and decision reasons. Player
display names and menu subjects are not deliberately logged. Review any trace
before sharing it; do not export other players' information.

1. In the developer beta, click **BoneCollector** and enable **Diagnostics
   (this session)**. With a consenting player in a noncompetitive test location
   that actually leaves ordinary bones, remain nearby and wait three seconds.
   No name configuration is needed, including for someone the plugin has
   never seen before.
2. Have them test one death while you remain in the same scene. Confirm that
   `player_removed` and `ground_added` (or `ground_changed`) identify the same
   tile and that the object ID is the reported ordinary `BONES` config.
   **The counter must still be unchanged.**
3. Move within one tile and Take that bone with an empty backpack slot.
   Look for `menu`, `intent`, the exact ground removal, and `inventory` delta
   `1` with `other_changed false`, followed by `server_boundary`.
   `collection_evidence` and, after settling, `count` should occur exactly once.
   Confirm a row reads **"You have picked up 1 \<name\> bones"** (or that an
   existing count increased by one). Close and reopen the interface, then
   reload the plugin and confirm the saved count remains.
4. Repeat negative controls: a disappearance without a pickup; a teleport
   without new bones; an attempted Take with a full backpack; another player taking the bones;
   two possible players on the same tile; dropped/re-dropped bones without a
   new disappearance; and a world hop during an attempted pickup. None should
   increment a counter.
5. If a real collection is skipped, read the `skip`/`reset` reason. Record event
   ordering, config IDs, counts, validity, and packet boundaries locally. In
   particular, check whether the beta emits ground and backpack updates in
   **different packets**. Do not broaden the matching window or accept inventory
   gain alone to make a test pass. Turn diagnostics off when finished.

Actual death drops, client callback ordering, proxy comparison, UI behavior,
and the same-packet assumption require this in-game check. The automated tests
cannot establish those facts.

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

- `src\matcher.lua`: API-independent, bounded-time correlation state machine.
- `src\app.lua`: guarded native event adapter, copied snapshots and diagnostics.
- `src\store.lua`: persistent counters, display names and legacy-data migration.
- `src\view.lua`: in-game opener, counts window and native settings/content panels.

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
