# Transmog - manual (English)

Short overview, install and status: [README.md](../README.md). The full reference (protocol, code layout, saved
data, release notes) is the German [MANUAL.de.md](MANUAL.de.md); the in-game test list is
[CHECKLIST.de.md](CHECKLIST.de.md). This page covers everything a player needs.

## 1. What it is, what it needs

A wardrobe window for **World of Warcraft 3.3.5a (Interface 30300)** on an **AzerothCore** server that runs the
module **mod-transmog-plus**. It replaces the module's gossip menu with a flat dark window: a large 3D preview of
your character, a grid of the appearances you have collected, filters, outfits and a cost display.

```
server module -> what   collected appearances (account-wide), rules, price, applying
this addon     -> how    choosing, preview, filters, outfits, cost, controls
you            -> whether   nothing is applied until you press Apply
```

The addon only sends requests; the server checks the collection, the rules and your money. The server does **not**
check your distance to the transmogrifier NPC, so since version 2.1 you can transmog anywhere (`/transmog`).

| Requirement | Notes |
|---|---|
| Client 3.3.5a | `## Interface: 30300` |
| mod-transmog-plus on the server | without it nothing answers (the addon says so after 8 s) |
| Transmogrifier NPC | **not needed** since 2.1; talking to it still opens the window (module README: `.npc add 190012`) |
| Folder `Interface/AddOns/Transmog` | the folder must be named exactly `Transmog` |

The module ships an older addon of the same name in `addon/Transmog`; this one replaces it (never install both).

### Install

Copy the folder to `World of Warcraft/Interface/AddOns/Transmog/` (from a GitHub ZIP, rename `Transmog-main` to
`Transmog`; `tests/` and `docs/` are not needed to play). Replace an old 1.x version instead of copying over it.
**Restart the game** (a `/reload` does not pick up new files). On login a chat line "Transmog 2.1 ... /transmog"
appears.

## 2. Using it

Open the window with `/transmog` (or `/xmog`, or a key you bind under Esc > Key Bindings > Transmog). Talking to the
transmogrifier opens it too (it then closes when you walk away). Esc or the `x` button closes it; an open menu or
dialog takes the first Esc.

1. Pick a slot (left click). Right click on a slot discards a pending change, or marks the applied appearance for
   removal.
2. Pick a tile in the grid: the preview and the cost update at once and the slot gets a yellow border. You can
   queue several slots.
3. Press **Apply** (its tooltip lists the changes per slot). **Discard** drops all pending changes, **Remove all**
   (asks first) removes every applied appearance.

Changes are sent one after another; the status line shows progress and a failure names the slot and keeps your
selection. After a success a stock client sound (a coin sound) plays; the option can be switched off.

### Slots

All **14** slots stand in two columns around the preview (left: head, shoulder, back, chest, shirt, tabard,
wrists; right: hands, waist, legs, feet, main hand, off hand, ranged). Border colours: blue = selected, yellow with
`*` = change pending, pink = applied, red with `!` = inactive (the equipped item changed and the stored appearance no
longer fits; the server still keeps it). The number at the bottom right is the count of available appearances.
Never transmoggable (server rule): neck, rings, trinkets, relics, ammo, quivers, bags. "Hidden" is allowed in 11
slots (all but main hand, off hand, ranged) and costs nothing; so does "Original" (remove).

### Preview

Your character, dressed with the wanted appearance of every slot. Drag left to rotate, drag right to move, mouse
wheel to zoom, `<` `>` buttons and "Reset". A one-hand weapon chosen for the off hand can only be shown in the main
hand (a limit of the 3.3.5 try-on); the server still applies it correctly.

### Grid, filters, search

* One tile per appearance (3D model, name in quality colour, star = favourite, pink border = applied, blue = selected,
  "NEW" = collected this session). Mouse wheel pages. Tile size: Options (small / medium / large / very large).
* Search: words separated by spaces, **all** must match (name or localized type); `#1234` or a bare number searches
  the item id.
* Sort: quality (default), name, item level. Quality chips hide or show a quality. The "Filter" menu has "Hide
  duplicates" (an approximation: same icon, type and slot), "Favourites only", "New only" and the list of item types.
  The `x` button resets all filters.
* Filters, sort, favourites and outfits are stored **per character**.

### Outfits

The **Outfits** tab saves the current look under a name (max. 50 per character, names up to 32 characters). Loading
only queues the parts that are available for your equipped items; **nothing is applied until you press Apply**.
Overwrite, rename and delete (with confirmation) are available.

### Tooltips and notifications

Item tooltips get a pink line "Appearance not collected" for gear whose appearance you have not collected, and your
equipped items show "Transmogrified to: ..." (red "inactive" if it no longer fits). Both can be switched off.
New appearances pop up as small cards at the top centre (max. 3 at a time, a summary card for bursts, none in the
first 10 s after login); move them with `/transmog toast`.

### Window, scale, languages

Default size 880 x 600 (minimum 740 x 520); drag the title bar to move, the corner grip to resize. Scale "Auto" or
60-150 %. Eight interface languages: English, German, French, Spanish, Russian, Korean, Simplified and Traditional
Chinese ("Auto" follows the game client; change in Options or `/transmog lang <code>`, no `/reload` needed). Item,
slot and type names always come from the game client.

### Transmog anywhere (since 2.1) and preview mode

Since 2.1 applying works anywhere. The option "Allow applying without a transmogrifier" (Options) is on by default;
switch it off to get the old *preview mode*: `/transmog` then shows a yellow bar, you can browse, try on, see costs and
manage outfits, but Apply / Remove all only work at the NPC. Installations from 2.0 are switched to "on" once. If a
customised server does check the distance and refuses, switch the option off.

## 3. Commands and options

| Command | Effect |
|---|---|
| `/transmog`, `/xmog` | toggle the window |
| `/transmog options` | open the options window (also the `*` button in the title bar) |
| `/transmog reset` | reset window position and size |
| `/transmog toast` | show the notification anchor (drag it; right click = default position) |
| `/transmog lang [code]` | show or set the language: `auto enUS deDE frFR esES ruRU koKR zhCN zhTW` (short forms `en de fr es ru ko`) |
| `/transmog debug` | toggle diagnostics (version, server state, pending queries, missing texts) |
| `/transmog help` | list the commands |

Options: language, window scale, tile size, reset position/size, sound on apply, new-appearance notifications, the
two tooltip lines, "Allow applying without a transmogrifier", and buttons for moving/testing the notification.

## 4. Which appearances can I use?

The **server** decides; the addon shows what it delivers. The collection is **account-wide**. An appearance is
collected when the item enters your inventory (loot, quest, vendor, crafting, mail, trade), when equipped, and for
everything you own at login. A slot offers only collected appearances that the server rules allow for the item you
currently wear (armour type, weapon type, quality switches, class, race, ... see the module's
`conf/mod_transmog_plus.conf.dist`); the worn item itself and items with an identical look are not listed. Applying
costs a flat price per applied appearance (1000 copper in the default config); Hidden and Original are free.

## 5. Troubleshooting and known limits

| Observation | Cause / remedy |
|---|---|
| red bar "The server module does not answer" | module missing or disabled (`Transmog.Enable = 0`), or not loaded yet; it recovers by itself when answers arrive |
| Apply is grey | the button tooltip names the reason: nothing changed, running, cost being calculated, not enough money, server silent, (no NPC only if the "anywhere" option is off) |
| empty list | slot empty, item never transmoggable, or nothing collected yet that fits the worn item; check the filters ("Reset filters") |
| "Loading appearances..." for long | item data comes from the server; 3.3.5a has no item-info event, so the first load is slow and cached afterwards (`/transmog debug` shows open queries) |
| texts show as keys (`GRID_NO_SLOT`) | mixed installation; replace the whole folder |
| squares instead of letters (ruRU, koKR, zh) | the client font lacks those characters; set the language to "Auto" |
| window off-screen after a resolution change | `/transmog reset` |

Known limits: "Hide duplicates" is an approximation; the type filter relies on the client's auction-house class lists
(fallback tables are verified for enUS and deDE only); "NEW" is per session; the server shows a hidden slot's icon as
invisible and a wrong set count in the character sheet after transmogging set items (display only).

## 6. Status

Written with the help of Claude (Anthropic's AI assistant) for a private AzerothCore server. The author has used
version 2.1 in the real game and confirmed that **applying without the NPC works with the live server**. The rest of
the in-game check list ([CHECKLIST.de.md](CHECKLIST.de.md)) was only partly checked; there was no systematic
in-game test. The automated tests run against a strict mock of the 3.3.5a client API, not a real client, so the
look and feel (models, camera framing, fonts in other languages, the sound) are not covered by them.

Run the tests (needs [LuaJIT](https://luajit.org/); `xmllint` or `python3` for the XML check):

```
bash tests/check.sh --strict --smoke
luajit tests/render_ui.lua --list     # window layouts as SVG without a game client (output in tests/out/)
```

## 7. Licence and origin

GNU AGPL v3 (`LICENSE`, `NOTICE`), Copyright (C) 2026 nexartgroup. The addon was rewritten from scratch (version 2.0)
but takes the camera calibration numbers of `UI/Cameras.lua` and the Spanish item-class names from the older addon
bundled with mod-transmog-plus (AGPL-3.0; a port by malinmr of flekz-games/cmangos-transmog, GPL-3.0 according to its
GitHub page), which is why the repository is AGPL-3.0. No media files are included; the apply sound is a stock client
sound. Details: [MANUAL.de.md](MANUAL.de.md), section 11.
