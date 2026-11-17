# Death Tracker

Native **RuneScape 3 Lua** plugin in
[fletchto99/DeathTracker](https://github.com/fletchto99/DeathTracker).
The product goal is **Your Death Count** plus **friends-only group death counts**.
Version **0.4.0 starts with a functional self-death counter** for the first
in-client test. Friends' deaths remain the next step, not a removed feature goal.

The self counter automatically increments for the incoming general game message:

```text
Oh dear, you are dead!
```

It does not require arming capture, a group, open friends/group panels, health
polling, or a tracking ID. Typing the sentence in player chat does not count.
Friend counting is not active yet. This is native Lua, not Alt1 or RuneLite.

## Install or update in the developer beta

1. Follow the [official developer-beta setup](https://developer.runescape.com/rs/tutorial/1helloworld.html).
   On Windows the default cache is `C:\ProgramData\Jagex\RuneScape-BETA`.
2. Install **PrettyUI (mod.io 6398181)** through the native plugin system.
   The plugin uses its Window, SimpleButton and SimpleView APIs.
3. Extract all files from `dist\DeathTracker-0.4.0.zip` into
   `C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\deathtracker`, or
   `dev_plugins\deathtracker` under your actual beta cache.
4. Once copying finishes, open the beta console with **Alt + the key below Esc**,
   then run `prf` and `pon deathtracker` for a new installation, or
   `prf` and `prl deathtracker` for an already enabled plugin.

The ZIP has five runtime files: `main.lua`, `plugin.json`,
`src\deathtracker.lua`, `src\deaths.lua`, and `src\names.lua`.
An older installed `src\group_capture.lua` is not loaded by this entrypoint.
Only Lua and PrettyUI are needed in game; Node.js is development tooling only.

**Only `chatAccess` is requested.** Review/grant it in the native plugin permission
UI; the beta also provides `ppr deathtracker`. No `trackingAccess`, HTTP permission
or external service is used. If required chat access is denied, the client may
prevent activation; if revoked while running, the interface shows counting
disabled and messages are ignored. Runtime checks use the native
`PluginPermissions.chatAccess` object, not a manifest string.

## Use

Click **Death Tracker** near the upper-left of the game UI. The interface shows:

```text
Your Death Count: 0
Character: Your name
```

The count updates automatically and is saved immediately when an accepted
self-death notification arrives. You can also view it through **Plugin Hub >
Manage > Death Tracker > Settings** or the native Plugins ribbon panel.
No manual arm/start action is needed. The count survives plugin reloads.

Status text shows whether monitoring is active, chat access is missing, the
character has not yet been observed, or storage/monitoring failed. **NOT SAVED**
means the displayed count is only in memory. Use **Retry save** before reloading
or closing the client. A failed storage read or invalid saved format suspends
counting rather than silently resetting the total; resolve the storage problem
and reload. There is no reset, import, migration or database-purge operation.

## Message and identity rules

- Accept only `ChatType.GENERAL` (0), the general game-message channel, with
  **all three documented sender-name fields empty**. Public, private, friends,
  group, broadcast, engine and plugin-message categories are not accepted.
  `Chat.AddMessage` always produces `ChatType.PLUGIN`, so plugin-generated
  lookalikes do not increment the count.
- Match the complete sentence exactly, including case and punctuation. Native
  `<col=...>` / `</col>` colour tags are removed; extra words, whitespace,
  other markup and approximate text are rejected.
- Use the current local display name, case-insensitively with underscores
  normalized to spaces, to separate character totals. Once a valid local name
  is observed, keep it through loading, reconnecting and death/respawn entity
  gaps. Clear it on the login screen, lobby or account/startup states; replace
  it when a different local character is observed. A message received before
  any local identity is known cannot safely be counted and produces a status.
- Save fresh per-character counters under the plugin's `selfDeaths.v1` key in
  local `PersistentDB`. A display-name change creates a separate name-keyed
  counter; case changes do not. This modest limitation avoids requesting a
  stable tracking ID.
- Use the documented notification timestamp to suppress repeated delivery:
  the last 16 accepted timestamps are stored **per character**, including
  across reloads. No time-based cooldown blocks a later message with a different
  timestamp. Since the API provides seconds, not a unique death/event ID,
  identical notifications for the same character within the same second cannot
  be distinguished and are treated as one. Very old replays beyond the bounded
  history are not guaranteed to be recognized.

No unrelated chat is logged or saved. The database is local to the device and
client type; beta/live data are separate. Use one client writing these counters
at a time: the native database is shared and does not expose an atomic increment.

## First in-client test

The source and packaged Lua pass automated tests, **not an in-client test**.
The exact sentence is user-observed. The initial supported path is the native
general game-message category; real delivery metadata still needs confirmation
in the beta.

1. After installing/reloading, open Death Tracker and confirm the current
   character, numeric count, and monitoring status. No group or friends panel
   is needed.
2. Perform one appropriate self-death test in the developer beta. When the game
   emits **Oh dear, you are dead!**, the count should increase once.
3. Reload with `prl deathtracker`; the count should remain. A subsequent death
   should add another count without requiring a manual arm.
4. Typing that sentence in ordinary chat or receiving unrelated game text must
   not increment it.

If a real death does not count, record the displayed status and the exact game
message/console error. Do not broaden to arbitrary chat types or remove sender
checks just to force a count. The tracker counts observed notifications, not
historical deaths or deaths while the plugin is disabled. Localized messages or
death modes that do not emit this exact notification are outside this first test.

## Friends-only group tracking: next step

Friends' death tracking is still planned. The earlier narrow group-notification
capture implementation is retained in `src\group_capture.lua` with focused
source-only tests. It is **not packaged, loaded, or required** by the self counter,
so its roster and identity research cannot block this test.

Before enabling friends' counters, verify the real group-death message's native
category, template, sender metadata, current group context and fresh in-game
friends membership. Ordinary chat must never become death evidence, and
non-friend group members must remain excluded. No off-screen/other-world
coverage or authenticated group-death event is currently promised.

## Development

With Node.js 22 or newer:

```powershell
npm ci
npm run check
npm run build
```

Tests execute actual Lua modules through Wasmoon's Lua 5.4. The client uses Lua
5.4.8 and is not exercised by these checks. Self-counter scenarios run against
both source and the actual ZIP: message filtering, persistence/reload, duplicate
evidence, character separation, transient entity loss, logout, denied/revoked
permissions, read/write failures and UI lifecycle. Permission mocks require
userdata, preserving the regression for the earlier native argument error.
Package tests ensure no tracking-ID or group/friends prerequisites ship in this
self-test build. The deferred group capture has a separate source-only suite.

## References and distribution

- [Official ChatMessage payload](https://developer.runescape.com/rs/core/events.html#chatmessage),
  [ChatType enumeration and plugin-generated messages](https://developer.runescape.com/rs/game/chat.html),
  and [native permission checks](https://developer.runescape.com/rs/core/plugin.html#haspermission).
- [Player availability and entity access](https://developer.runescape.com/rs/game/player.html),
  [entity validity](https://developer.runescape.com/rs/game/entity/playerentity.html),
  [game-state events](https://developer.runescape.com/rs/core/events.html#gamestatechanged),
  and [PersistentDB](https://developer.runescape.com/rs/core/persistentdb.html).
- [Native-plugin game/player chat classification reference](https://github.com/GrynjolfLabs/rs3-Watchdog/blob/811d75df5c4531507e2499c54430b6d358e002e1/src/chat_types.lua)
  identifies `GENERAL` as game messages, separate from player chat. This does
  not substitute for testing the actual self-death payload in the client.

The public repository is not Jagex approval. Before live distribution, follow
the [plugin guidelines and moderation process](https://developer.runescape.com/rs/submission/guidelines.html).
A real author-selected `contactEmailAddress` is still required for submission.
