/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugHint

Description:
    Live status board in the hint box, refreshed once a second while the CBA
    setting Site Status Hint is on.
    Full notes: docs/functions/main.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_fnc_debugHint;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_HINT_MAX_CONTACTS 6

if !("aegism_main_debugHint" call CBA_settings_fnc_get) exitWith {
    if (missionNamespace getVariable ["AEGISM_debugHintShown", false]) then {
        missionNamespace setVariable ["AEGISM_debugHintShown", false];
        hintSilent "";
    };
};
missionNamespace setVariable ["AEGISM_debugHintShown", true];

private _sites = (missionNamespace getVariable ["AEGISM_allPoolOwners", []]) select { !isNull _x && {!isNil {_x getVariable "AEGISM_networkMembers"}} };
private _camera = positionCameraToWorld [0, 0, 0];
private _nearest = objNull;
{
    if (isNull _nearest || {(_camera distance2D _x) < (_camera distance2D _nearest)}) then { _nearest = _x; };
} forEach _sites;

hintSilent parseText ([_nearest, true, AEGISM_HINT_MAX_CONTACTS] call aegism_fnc_statusBoard);
