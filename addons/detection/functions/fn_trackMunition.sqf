/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_trackMunition

Description:
    Starts tracking a freshly-fired, already-classified munition -- the
    munition half of AEGIS-M's hybrid detection model (a fired CfgAmmo
    projectile is not a getSensorTargets result, so radars can't report it
    themselves).

    Gives the munition its own contact key ("AEGISM_contactKey" = "m<n>", see
    aegism_fnc_contactKey) and adds it to the list the single munition
    tracker works through (aegism_detect_fnc_munitionTracker: every tracked
    munition checked every AEGISM_TRACK_INTERVAL s, spread over frames by
    fire time). It used to be one per-frame handler per munition.

    What a check does (radar range/arc/LOS, IFF, whether it threatens a
    Site): aegism_detect_fnc_munitionCheck.

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
// [projectile, class, shooter side, key, pools it's in, next check at, radar
// LOS memory (radar netId -> last clear), flags (HashMap)]
_tracked pushBack [_projectile, _class, _shooterSide, _key, [], time, createHashMap, createHashMap];

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
