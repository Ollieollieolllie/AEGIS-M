// Periodic discovery scan for vehicles with an AEGIS-M role checked on
// their own Attributes -- see aegism_system_fnc_scanForRoles. A 2-second
// interval is plenty responsive for a mission-setup-time concern (checking
// a role box, or Zeus spawning/configuring a new vehicle) without scanning
// `vehicles` needlessly often. Never removed -- this runs for the life of
// the mission on every machine, matching aegism_system_fnc_scanForRoles'
// own doc comment on why it isn't isServer-gated.
[{
    [] call aegism_system_fnc_scanForRoles;
}, 2, []] call CBA_fnc_addPerFrameHandler;
