# HudToggle.AphelionsPatch

A tiny separate addon, not a modification of either HudToggle or Aphelion's Frontier Overhaul
themselves. It exists only because both of those mods ship their own full override of
`scripts/vscripts/client/cl_player.nut`, and R1Delta's addon system resolves a same-path file
conflict by last-loaded-wins, with no merging - whichever addon is lower in the load order
completely replaces the other's copy of that file, silently dropping its changes.

## What's actually different between the two mods' copies

Diffed Aphelion's Frontier Overhaul's `client/cl_player.nut` against a clean CORE copy (as of
the 2026-11-24 upload of the mod): kill-shot-sound skipped for holograms, plus dogfighter
drones/gunship turrets/gunship mover; `mp_weapon_throwing_knife`/`mp_ability_deployable_cover`
added to a weapon-switch-sound exception list; a couple of whitespace/formatting touch-ups.
None of it touches `DamageIndicators()`.

(An earlier version of Aphelion's Frontier Overhaul had `mp_weapon_deployable_cover` instead
of `mp_ability_deployable_cover` in that same exception list, and didn't yet skip the
kill-shot sound for dogfighter drones/gunship parts - this patch was rebuilt from that
mod's current file rather than just carrying the old diff forward.)

HudToggle's own copy changes exactly one thing: an early `return` at the top of
`DamageIndicators()`, permanently removing the incoming-damage direction indicator (the
screen-edge arrow for pilots / cockpit panel flash for titans).

Since the two mods change different parts of the same file, they merge cleanly - this addon
ships Aphelion's copy of `cl_player.nut` with HudToggle's `DamageIndicators()` change
re-applied on top of it.

## Install

Place this folder in `Titanfall/`, alongside HudToggle and Aphelion's Frontier Overhaul.
**Load order matters**: this addon must be ordered *after* (below) Aphelion's Frontier
Overhaul in the in-game addons list, so its copy of `client/cl_player.nut` is the one that
wins. Load order relative to HudToggle itself doesn't matter, since HudToggle doesn't ship
`client/cl_player.nut` twice here - only this patch and Aphelion's do.

Does nothing on its own - only makes sense with both HudToggle and Aphelion's Frontier
Overhaul also enabled.

## If Aphelion's Frontier Overhaul updates its own `cl_player.nut` later

This patch will go stale (it's a copy, not a live reference) and may need re-diffing against
whatever changes that update makes, the same way this one was built.
