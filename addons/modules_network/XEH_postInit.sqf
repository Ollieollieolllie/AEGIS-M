// Periodic fallback scan for a placed AEGISM_Module_Site whose own Eden/
// Preview module activation never fired -- see aegism_network_fnc_
// scanForUninitSites' own doc comment for the real, observed Preview-mode
// gap this works around. 2-second interval matches aegism_system_fnc_
// scanForRoles' own reasoning (a mission-setup-time concern, not something
// that needs per-frame responsiveness); the function's own isNil guard
// means a Site whose real activation DID fire is simply skipped every tick
// at near-zero cost, so this never fights or double-initializes a Site that
// works correctly on its own. Never removed -- runs for the life of the
// mission on every machine, matching scanForRoles.
[{
    [] call aegism_network_fnc_scanForUninitSites;
}, 2, []] call CBA_fnc_addPerFrameHandler;

// Zeus: a Game Master only lists modules from addons activated for it, and
// the Game Master module's default ("All official addons") excludes mods --
// so the Site wasn't placeable from Zeus. Activate this addon for every
// curator, including ones created later (retroactive class init handler).
// addCuratorAddons is server-only.
if (isServer) then {
    ["ModuleCurator_F", "Init", {
        params ["_curator"];
        _curator addCuratorAddons ["aegism_modules_network"];
    }, true, [], true] call CBA_fnc_addClassEventHandler;
};

// Editing Site settings and vehicle overrides from Zeus (needs Zeus Enhanced
// for the dialogs) -- see aegism_network_fnc_zeusInit.
[] call aegism_network_fnc_zeusInit;

// Site alarms: the server publishes each Site's alarm (aegism_network_fnc_
// siteAlarm), every machine with a player plays it for itself, every frame
// (aegism_network_fnc_alarmPlayer). Only the Sites' alarm states and the
// camera are read between changes.
if (hasInterface) then {
    [{
        [] call aegism_network_fnc_alarmPlayer;
    }, 0, []] call CBA_fnc_addPerFrameHandler;
};
