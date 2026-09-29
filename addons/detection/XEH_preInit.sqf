// The munition half of AEGIS-M's hybrid detection model: a fired CfgAmmo
// projectile is not itself a valid getSensorTargets result (it has none of
// the radarTargetSize/irTargetSize/visualTargetSize properties that make a
// CfgVehicles object sensor-visible), so incoming missiles/rockets/shells/
// bombs are picked up from the Fired event instead (see aegism_detect_fnc_
// firedEventHandler).
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
