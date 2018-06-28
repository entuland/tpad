# tpad
A teleporter-pads mod for Minetest

Developed and tested on Minetest 0.4.16 - try in other versions at your own risk :)

WIP mod forum discussion: https://forum.minetest.net/viewtopic.php?f=9&t=20081

**Table of Contents**
- [Recipe](#recipe)
- [Features](#features)
- [Appearance](#appearance)
- [Pad types](#pad-types)
- [Pad interaction](#pad-interaction)
- [Closest pad waypoint](#closest-pad-waypoint)
- [Pad admin](#pad-admin)
- [Screenshots](#screenshots)

## Recipe
The recipe can be customized altering the file `custom.recipes.lua`, created in the mod's folder on first run and never overwritten.

    W = any wood planks
    B = bronze ingot

    WBW
    BWB
    WBW

![Crafting](/screenshots/crafting.png)

## Features

With these pads players can build their own Local Network and collaborate to build a Global Network shared among all players.

Pads are sorted by name in the lists, the Global Network list groups them by owner name first.

## Appearance

This is how a pad looks like when placed against a wall or on the floor (they can be placed under the ceiling as well):

![Pads](/screenshots/pads.png)

## Pad types

Each pad can be set as one of these three types:
- `Private` (default): only accessible to its owner or by an admin
- `Public`: accessible to anyone from any Public pad of the owner's Local Network
- `Global`: accessible to anyone from any Public pad

A pad can be edited and destroyed only by its owner or by an admin.

## Pad interaction

- place a pad down, it will be immediately active and set as "Private"
- right click a pad edit its name/type and to access the Networks
- select a pad from a list and hit "Teleport", or doubleclick on the list item
- delete any remote pad by selecting it on the Local Network list and clicking "Delete"

## Closest pad waypoint

Issue `/tpad` on the chat to get a waypoint to the closest of your pads.
Issue `/tpad off` to remove the waypoint from the HUD - it will also be removed when you teleport from any pad.

## Pad admin

A `tpad_admin` privilege is available, players with such privilege can access, alter and destroy any pad, they can set the max number of total / global pads a player can create and they can also place any amount of pads regardless of those limits.

Limits can be edited by admins directly in the admin interface (reachable from the "Global Network" dialog of any pad); limits get stored on a per-world basis in the file `/mod_storage/tpad.custom.conf`. By default a player can place up to 100 pads, and of these, only 4 can appear in the Global Network.

## Screenshots

A public pad's interface seen by a visitor:

![Local Network Visitor](/screenshots/local-network-visitor.png)

The same interface seen by its owner or by an admin (notice the highlighted "private" pad, which was hidden in the previous interface):

![Local Network](/screenshots/local-network.png)

The Global Network interface seen by a non-admin:

![Global Network](/screenshots/global-network.png)

Same as above, but the admins can see an "Admin" button:

![Global Network Admin](/screenshots/global-network-admin.png)

Admin settings interface:

![Admin Settings](/screenshots/admin-settings.png)
