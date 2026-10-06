// Every threat munition fired starts being tracked here: a fired CfgAmmo
// projectile is not itself a valid getSensorTargets result (it has none of
// the radarTargetSize/irTargetSize/visualTargetSize properties that make a
// CfgVehicles object sensor-visible), so each incoming missile/rocket/
// shell/bomb is tracked by AEGIS-M, which judges for itself which sensors
// see it (see aegism_detect_fnc_firedEventHandler, aegism_detect_fnc_
// trackMunition, aegism_detect_fnc_munitionSeen).
//
// "All" (not "AllVehicles") also catches infantry-fired launchers. Server
// only: every other machine would call it for every bullet fired in the
// mission just to return -- the pools and engagement loops it feeds exist
// only on the server. (Fired is a global event: the server sees shots fired
// on every machine.)
if (isServer) then {
    ["All", "Fired", {
        _this call aegism_detect_fnc_firedEventHandler;
    }] call CBA_fnc_addClassEventHandler;
    // ...and munitions nothing reported fired: spawned by a script, or from a
    // shooter whose Fired event handlers another mod removed (aegism_detect_
    // fnc_projectileCreated). Put back if removed (aegism_system_fnc_
    // guardSystems).
    missionNamespace setVariable ["AEGISM_projectileCreatedEH", addMissionEventHandler ["ProjectileCreated", {
        _this call aegism_detect_fnc_projectileCreated;
    }]];
};
