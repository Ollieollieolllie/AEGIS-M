#include "perf.hpp"

[
    "aegism_main_scaleMode",
    "LIST",
    ["AEGIS-M Range Scale", "Whether real-world-sourced ranges are used as-is or compressed for Arma-sized maps"],
    ["AEGIS-M", "General"],
    [[0, 1, 2], ["Arma Scale (half real-world)", "Real World Scale", "Custom Multiplier"], 0],
    1
] call CBA_fnc_addSetting;

[
    "aegism_main_scaleCustomMultiplier",
    "SLIDER",
    ["Custom Range Multiplier", "Only used when Range Scale is set to Custom Multiplier"],
    ["AEGIS-M", "General"],
    [0.1, 3, 1, 2],
    1
] call CBA_fnc_addSetting;

// Global (isGlobal=1): every machine must agree on which vehicles are
// Systems, since discovery runs on every machine. See aegism_system_fnc_
// moduleInit's adoption policy.
[
    "aegism_main_standaloneAdoption",
    "CHECKBOX",
    ["Standalone Air Defence", "Adopt UNSYNCED self-contained AA vehicles (a sensor of their own -- radar, IR or visual -- plus their own AA weapons, e.g. Cheetah, Tigris, Spartan) as standalone AEGIS-M Systems. Vehicles synced to an AEGIS-M Site are always adopted regardless. Aircraft and infantry are never adopted."],
    ["AEGIS-M", "General"],
    true,
    1
] call CBA_fnc_addSetting;

// Client-side (isForce=0) and NOT saved to the server's exported settings --
// this is a per-player visualisation toggle, not a mission rule, so each
// machine watching the battery picks it independently. See aegism_fnc_debugDraw.
[
    "aegism_main_debugDraw",
    "CHECKBOX",
    ["Enable Debug 3D Draw", "Draws pooled contacts, claims, engagement envelopes, and each System's acquired target/LOS check. Client-side only, no effect on gameplay."],
    ["AEGIS-M", "Debug"],
    false,
    0
] call CBA_fnc_addSetting;

// Server-side RPT summary of AEGIS-M's own work, see aegism_fnc_perfLog.
[
    "aegism_main_perfLog",
    "CHECKBOX",
    ["RPT Performance Summary", "Every 10s, while AEGIS-M is doing anything, the server writes one PERF line to its RPT: coordinator time, aim solves, CIWS rounds tracked, munition tracker work and server FPS. Silent while idle."],
    ["AEGIS-M", "Debug"],
    true,
    1
] call CBA_fnc_addSetting;

// Counters behind the PERF line (perf.hpp). Created everywhere so an
// increment on any machine never hits nil; only the server logs them.
AEGISM_perfCounts = [];
AEGISM_perfCounts resize [PERF_COUNT, 0];

// Client-side, like the 3D draw. See aegism_fnc_debugHint.
[
    "aegism_main_debugHint",
    "CHECKBOX",
    ["Site Status Hint", "Live status board in the hint box: the nearest Site's vehicles (roles, colour-coded status, target, ammo) and contacts, other Sites and standalone Systems in summary. Shows data only where AEGIS-M runs its engagement logic: singleplayer, Eden Preview, or a hosted game's host."],
    ["AEGIS-M", "Debug"],
    false,
    0
] call CBA_fnc_addSetting;
