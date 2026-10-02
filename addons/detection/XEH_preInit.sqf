// Every threat munition fired starts being tracked here: a fired CfgAmmo
// projectile is not itself a valid getSensorTargets result (it has none of
// the radarTargetSize/irTargetSize/visualTargetSize properties that make a
// CfgVehicles object sensor-visible), so each incoming missile/rocket/
// shell/bomb gets a sensor proxy the game's sensors can see (see aegism_
// detect_fnc_firedEventHandler, aegism_detect_fnc_trackMunition).
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
};
