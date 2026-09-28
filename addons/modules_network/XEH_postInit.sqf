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
