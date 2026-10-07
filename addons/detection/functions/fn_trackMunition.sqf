/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_trackMunition

Description:
    Starts tracking a freshly-fired, already-classified munition.
    Full notes: docs/functions/detection.md

Parameters:
    _projectile - the fired munition object <OBJECT>
    _class - pre-classified target class, from aegism_detect_fnc_
        classifyTarget <STRING>
    _shooterSide - side of the unit/vehicle that fired it <SIDE>

Returns:
    Nothing

Examples:
    [_projectile, "missile", east] call aegism_detect_fnc_trackMunition;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_class", ["_shooterSide", sideUnknown]];

private _sequence = (missionNamespace getVariable ["AEGISM_munitionSeq", 0]) + 1;
missionNamespace setVariable ["AEGISM_munitionSeq", _sequence];
private _key = "m" + str _sequence;
_projectile setVariable ["AEGISM_contactKey", _key];

private _tracked = missionNamespace getVariable "AEGISM_trackedMunitions";
if (isNil "_tracked") then {
    _tracked = [];
    missionNamespace setVariable ["AEGISM_trackedMunitions", _tracked];
};

private _watched = !(_projectile getVariable ["AEGISM_fromSystem", false]) || {
    ((missionNamespace getVariable ["AEGISM_allPoolOwners", []]) findIf {
        !isNil { _x getVariable "AEGISM_system" } && {[side _x, _shooterSide] call aegism_detect_fnc_isHostile}
    }) != -1
};

// [projectile, class, shooter side, key, pools it's in, next check at, clear
// lines of sight (HashMap: sensor vehicle -> when it last had one, aegism_
// detect_fnc_munitionSeen), flags (HashMap)].
// Flags "firedAt": when it was fired; "ammo": its class; "watched": sensors
// look for it (above); "arm": an anti-radiation missile's last known state
// (aegism_detect_fnc_munitionCheck, logged as ARM-END when it's gone).
private _entry = [_projectile, _class, _shooterSide, _key, [], CBA_missionTime, createHashMap,
    createHashMapFromArray [["firedAt", CBA_missionTime], ["ammo", typeOf _projectile], ["watched", _watched]]];
_tracked pushBack _entry;

if !(missionNamespace getVariable ["AEGISM_munitionTrackerRunning", false]) then {
    missionNamespace setVariable ["AEGISM_munitionTrackerRunning", true];
    [{
        params ["", "_pfhHandle"];
        if !([] call aegism_detect_fnc_munitionTracker) then {
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
            missionNamespace setVariable ["AEGISM_munitionTrackerRunning", false];
        };
    }, 0, []] call CBA_fnc_addPerFrameHandler;
};
