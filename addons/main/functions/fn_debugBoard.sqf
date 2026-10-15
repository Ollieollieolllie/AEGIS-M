/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugBoard

Description:
    The Site Status Hint's board: the Site nearest a camera in detail, and
    everything else in summary (aegism_fnc_statusBoard). Server only.
    Full notes: docs/functions/main.md

Parameters:
    _camera - where the camera is <ARRAY>

Returns:
    Structured text, for parseText <STRING>

Examples:
    hintSilent parseText ([positionCameraToWorld [0, 0, 0]] call aegism_fnc_debugBoard);

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_HINT_MAX_CONTACTS 6

params ["_camera"];

private _sites = (missionNamespace getVariable ["AEGISM_allPoolOwners", []]) select { !isNull _x && {!isNil {_x getVariable "AEGISM_networkMembers"}} };
private _nearest = objNull;
{
    if (isNull _nearest || {(_camera distance2D _x) < (_camera distance2D _nearest)}) then { _nearest = _x; };
} forEach _sites;

[_nearest, true, AEGISM_HINT_MAX_CONTACTS] call aegism_fnc_statusBoard
