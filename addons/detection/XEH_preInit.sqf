// "All" (not "AllVehicles") is required to also catch infantry-fired
// small arms/launchers, not just vehicle-mounted weapons -- confirmed via
// CBA's own addClassEventHandler documentation.
["All", "Fired", {
    _this call aegism_detect_fnc_firedEventHandler;
}] call CBA_fnc_addClassEventHandler;
