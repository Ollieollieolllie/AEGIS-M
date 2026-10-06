// Periodic discovery scan for vehicles with real AEGIS-M-qualifying
// capability (a native radar sensor, or guided-missile/high-ROF-gun
// magazines) -- see aegism_system_fnc_scanForRoles. A 2-second interval is
// plenty responsive for a mission-setup-time concern (a vehicle spawning,
// or Zeus placing a new one) without scanning `vehicles` needlessly often.
// Never removed -- this runs for the life of the mission on every machine,
// matching aegism_system_fnc_scanForRoles' own doc comment on why it isn't
// isServer-gated.
// The same tick keeps what AEGIS-M set on its vehicles set against other
// mods' scripts (aegism_system_fnc_guardSystems).
[{
    [] call aegism_system_fnc_scanForRoles;
    [] call aegism_system_fnc_guardSystems;
}, 2, []] call CBA_fnc_addPerFrameHandler;
