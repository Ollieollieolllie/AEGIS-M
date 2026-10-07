/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_blastMunitions

Description:
    Destroys every tracked munition whose body is within the radius of a
    blast AEGIS-M set off.
    Full notes: docs/functions/detection.md

Parameters:
    _centre - where the blast went off, ASL <ARRAY>
    _radius - its radius, m (CfgAmmo indirectHitRange) <NUMBER>
    _by - what went off, for the log <STRING>
    _spare - munitions to leave out (the one just intercepted) <ARRAY, default []>

Returns:
    How many it destroyed <NUMBER>

Examples:
    [getPosASL _missile, 40, "M_MIMPAC3_AA", [_rocket]] call aegism_detect_fnc_blastMunitions;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_centre", "_radius", "_by", ["_spare", []]];

if (_radius <= 0) exitWith { 0 };

private _caught = [];
{
    private _munition = _x select 0;
    if (!isNull _munition && {alive _munition} && {!(_munition in _spare)} && {!(_munition getVariable ["AEGISM_fromSystem", false])}) then {
        private _rel = _centre vectorDiff (getPosWorldVisual _munition);
        private _miss = [_munition, _rel, _rel, _radius] call aegism_intercept_fnc_bodyPass;
        if (_miss <= _radius) then { _caught pushBack [_munition, _x select 3, _miss]; };
    };
} forEach (missionNamespace getVariable ["AEGISM_trackedMunitions", []]);

{
    _x params ["_munition", "_key", "_miss"];
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " BLAST-KILL: %1 (%2) destroyed by the blast of %3, %4m from its body (blast radius %5m).",
        typeOf _munition, _key, _by, _miss toFixed 1, _radius];
    [_munition] call aegism_detect_fnc_destroyMunition;
} forEach _caught;
count _caught
