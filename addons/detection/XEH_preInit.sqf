// "All" (not "AllVehicles") is required to also catch infantry-fired
// small arms/launchers, not just vehicle-mounted weapons -- confirmed via
// CBA's own addClassEventHandler documentation.
//
// This is the munition half of AEGIS-M's hybrid detection model: a fired
// CfgAmmo projectile is not itself a valid getSensorTargets result (it has
// none of the radarTargetSize/irTargetSize/visualTargetSize properties
// that make a CfgVehicles object sensor-visible -- confirmed against
// vanilla CfgAmmo, which never defines them either), so incoming
// missiles/rockets/shells/bombs need
// this dedicated Fired-event pipeline instead of the platform pipeline's
// getSensorTargets call (see aegism_detect_fnc_confidenceLoop).
["All", "Fired", {
    _this call aegism_detect_fnc_firedEventHandler;
}] call CBA_fnc_addClassEventHandler;
