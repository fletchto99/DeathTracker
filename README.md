# Death Tracker

Native **RuneScape 3 Lua** plugin development in
[fletchto99/DeathTracker](https://github.com/fletchto99/DeathTracker).
The intended tracker counts deaths of **friends in your group**,
with a separate **Your Death Count**. It does not use Alt1 or RuneLite.

## Current status: 0.3.3 validation build

The display name is **Death Tracker**, the development/plugin identifier is
**`deathtracker`**, and release archives use **`DeathTracker`**. This build
includes the fix for the reported native permission argument error: runtime
checks use `PluginPermissions.chatAccess` / `PluginPermissions.trackingAccess`
objects, not the strings used in the JSON manifest. It does not enable counting.

**Automatic death counting is NOT enabled.** The user reports a game message
like `"Player xyz has died"`, but its exact native `ChatType`, formatting,
sender fields, and delivery/deduplication behavior have not been verified.
This build captures one narrowly matched candidate to establish that contract.
It must not be presented as a working death counter.

The interface says **Your Death Count: unavailable (validation mode)** and
**Friend death counts: unavailable (validation mode)**, rather than inventing
zeroes. Self capture is limited to the same
group-message example; **solo deaths are not implemented**.

Detection research uses only group notifications, not a disappearance or
zero-health fallback. The build never accesses `PersistentDB`, imports prior
statistics, or writes new counters. There is no migration or database-purge code.

## Install for beta validation

1. Follow the [official developer-beta setup](https://developer.runescape.com/rs/tutorial/1helloworld.html).
   On Windows the default cache is `C:\ProgramData\Jagex\RuneScape-BETA`.
2. Install **PrettyUI (mod.io 6398181)** through the native plugin system.
   Window/TextField, SimpleButton and SimpleView support is required.
3. Open the beta console with **Alt + the key below Esc**. For a clean
   dev-plugins directory, create the destination in the next step.
4. Extract all files from `dist\DeathTracker-0.3.3.zip` into
   `C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\deathtracker` (or
   `dev_plugins\deathtracker` under your actual beta cache). Its five runtime
   files are `main.lua`, `plugin.json`, `src\deathtracker.lua`,
   `src\group_capture.lua`, and `src\names.lua`.
5. After copying finishes, run `prf`, then `pon deathtracker` for a new
   installation or `prl deathtracker` if it is already enabled.
   The UI shows **Death Tracker**.

`chatAccess` is a **required** native permission. `trackingAccess` is declared
optional so the UI can explain its absence, but is required to arm this
character-bound validation capture. Review/grant these in the native plugin
permission UI; the beta also provides `ppr deathtracker` to request declared
permissions. If denied chat access prevents the client from enabling the plugin,
resolve the native permission prompt first. A running plugin checks permissions
again before capture and shows a disabled status if they are missing/revoked.
No HTTP permission, service, or external upload is used.

Only the Lua files and PrettyUI are needed in game. **Node.js is development
tooling only.** Reload updates with `prl deathtracker`; disable with
`poff deathtracker`.

## Capture one real group death notification

This is the next required evidence, not an instruction to type the message.
Typing the same sentence in public/private/friends/group chat is not accepted.

1. Join a normal PvM group with a consenting player who is actually on your
   in-game **Friends list**. Keep **Friends** and **Group** panels open, with
   their name and your own group row visible. The current diagnostic roster
   layout is based on the normal group panel, not Group Ironman's separate UI.
2. Click the **Death Tracker** button near the upper-left of the game UI.
   The same controls are in **Plugin Hub > Manage > Death Tracker > Settings**
   and its native Plugins ribbon panel.
3. Click **Capture one group death notice**. It arms for 60 seconds. Have the
   consenting friend perform one beta test death that produces the real game
   notification. No other game action is required.
4. Open **Show captured notice**. If captured, click the field, **Ctrl+A**,
   **Ctrl+C**, then paste locally. The player name and character tracking ID
   are not included. Native text-field copying is still unverified in client;
   if it fails, take a screenshot of this capture window.
5. If nothing is captured, record the displayed status and the exact visible
   game notification, redacting names in screenshots. Do **not** substitute a
   player-authored sentence. A different template/category or unavailable
   roster is evidence to investigate, not a reason to broaden the filter blindly.

A second, separately armed test can capture your own grouped notification.
It is marked `subject=local character`; you do not need to be on your own
friends list. A genuine death message for a **non-friend group member** is not
retained. Keep this evidence local and review it before sharing.

Captures are in memory only. They are cleared on game/scene lifecycle changes,
permission revocation, missing character identity, character switch or reload.
Such a transition may clear a self-death capture; record that observation rather
than interpreting the missing result as a count. Repeated notifications cannot
append to an already completed one-shot capture. **Stop capture** disarms it
without changing data. Arming again starts a fresh capture.

## Exactly what the validation build does

- Reads the visible game's **Friends list**, not a manually configured name list
  and not friends-chat/clan membership. Names must resolve to 1-12 ASCII letters,
  digits, spaces or underscores. Matching is case-insensitive.
- Reads normal group name rows from the visible native roster. Your own row and
  at least one other member must be observed. Missing/closed/changed rosters
  suspend capture; there is no "track everyone" fallback.
- Resolves the local character through `Player.GetTrackingID()` and the local
  entity's display name. A missing ID is not treated as an anonymous shared
  account. The ID is used only in transient memory and is never logged.
- While armed, accepts only the user's exact example shape,
  `Player <name> has died`, with an optional final period and supported colour/
  shadow tags. It records no unrelated chat.
- The candidate must have all three sender fields empty and be in one of the
  **possible system categories** `GENERAL`, `ENGINE`, `GROUPCHAT_NOTIFICATION`
  or `GROUP_IRONMAN_NOTIFICATION`. These are a bounded capture search, **not an
  assertion that any of them authenticates a death**. Ordinary/player/plugin
  chat categories are excluded even when their text is identical.
- Immediately re-reads current friend/group UI observations for the candidate.
  The subject must be in the observed group and either a currently observed
  friend or the local character. Changed membership invalidates the armed
  capture rather than using a previously cached allowlist.
- Displays the numeric chat category, timestamp, empty-sender status, role,
  observed roster sizes, and the name-redacted raw template. It neither edits
  chat events nor sends any game actions.

## Remaining contract questions

**Friends UI freshness is not yet proven.** Open, visible rows are a conservative
diagnostic prerequisite, not a documented membership freshness guarantee.
Filters, scrolling/clipping, add/remove operations, closing/reopening and relogs
need validation. In particular, `ONFRIENDTRANSMIT` reports that friends data
changed but supplies only the component, not a friend list. The probe does not
claim this hook solves roster completeness or stale data.

**The notification is not yet authenticated as a death event.** The native
`ChatMessage` payload has text, chat type, three sender-name strings and a
seconds-resolution timestamp, but no unique death/message ID or group ID.
The supplied sentence has not been independently mapped to a category.
Before enabling counters we must verify real payloads, current group context,
duplicates, rapid separate deaths, and local-player notification behavior.
Capture tests use synthetic examples and do not establish native provenance.

**Observation is limited.** No off-screen, other-world or non-group friend deaths
are promised. The API does not expose a generic friend's HP/death field.
Future verified counters must be persisted per character. This validation
build implements neither persistent
death totals nor a manual increment workaround.

## Sources

- [Official ChatMessage payload and permission](https://developer.runescape.com/rs/core/events.html#chatmessage)
  and [ChatType enumeration](https://developer.runescape.com/rs/game/chat.html).
  Local `Chat.AddMessage` messages are explicitly `ChatType.PLUGIN`.
- [Native permission checks](https://developer.runescape.com/rs/core/plugin.html#haspermission),
  [character tracking ID](https://developer.runescape.com/rs/game/player.html#gettrackingid),
  and [shared-per-device PersistentDB scope](https://developer.runescape.com/rs/core/persistentdb.html).
- [Official dynamic component traversal](https://developer.runescape.com/rs/ui/component_collection.html),
  [visibility/relationship hooks](https://developer.runescape.com/rs/ui/component.html),
  and [text components](https://developer.runescape.com/rs/ui/decorative_components/text.html).
- [Native config dump](https://github.com/FriendlyDevelopment/runescape-api-stubs/blob/230702b372e83a40b4cfdde01f5a18c5266ec28c/csvs/Component.csv):
  `FRIENDS2__FRIEND_NAME_LAYER = 36044807` (550:7),
  `GROUP_CHILD__BUILD_AREA = 99549187` (1519:3). Runtime uses named constants.
- [RuneUI reference adapter](https://github.com/JeremyDwayne/RuneUI/blob/34e4914a52ea5b1cf6eef23961d48285c595a74f/src/adapter.lua)
  and [group row layout](https://github.com/JeremyDwayne/RuneUI/blob/34e4914a52ea5b1cf6eef23961d48285c595a74f/src/interfaces.lua):
  category 0, name-row dynamic IDs `1 + 23*n`. The reference notes that closed
  group rows freeze. This is prior art requiring validation, not an official
  stable roster/death contract.

## Development

With Node.js 22 or newer:

```powershell
npm ci
npm run check
npm run build
```

Tests execute actual Lua modules through Wasmoon's Lua 5.4. The client uses
Lua 5.4.8 and is not exercised by these checks. The current entrypoint tests
run again against the built ZIP, and fail if the
validation build accesses PersistentDB. They cover candidate filtering,
spoofed ordinary chat, friend/group/self exclusions, duplicate capture,
permissions, identity and lifecycle failures, UI opening and storage isolation.
Permission mocks require opaque userdata and reject strings, covering the
reported startup error as well as revocation, regrant and explicit rearming.
Manifest permission names and `OptionalPermissionChanged.permissionName`
remain strings, as required by those separate contracts.

The public repository is not Jagex approval. Before live distribution, follow
the [plugin guidelines and moderation process](https://developer.runescape.com/rs/submission/guidelines.html).
Other-player information is subject to review; no export service is included.
A real author-selected `contactEmailAddress` is still required for submission.
