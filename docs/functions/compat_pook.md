# compat_pook: function notes

What each function does and why, in full: the descriptions that used to sit in each
function's header, moved out of the code on 2026-10-07. Each header keeps a short
description with its parameters, return value and examples. Change a function's
behaviour and its notes here change with it. This folder is not packed into the mod.

## (every POOK function this addon switches off)

`addons/compat_pook/functions/fn_blocked.sqf`

```text
Does nothing, in place of one of POOK's scripts that would aim, fire or
fuse a vehicle's weapons itself (this addon's config.cpp points POOK's
own CfgFunctions entries at this file). POOK's script isn't run,
compiled or called from here: it simply no longer exists as a function,
on any vehicle, while this addon is loaded.

Logged once per function (COMPAT), so the RPT shows what's switched off.
```
