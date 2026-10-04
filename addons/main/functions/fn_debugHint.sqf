/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugHint

Description:
    Live status board in the hint box, refreshed once a second while the
    CBA setting "AEGIS-M > Debug > Site Status Hint" is on: the Site nearest
    the camera in detail, and everything else in summary (aegism_fnc_
    statusBoard, which says what's on it). The hint box cuts a long board,
    so only the nearest AEGISM_HINT_MAX_CONTACTS contacts are listed.

    Reads the same server-side variables the engagement pipeline runs on,
    so it only has data where that pipeline runs: singleplayer, Eden
    Preview, or the host of a hosted game (not a client of a dedicated
    server -- a Site's status terminal, aegism_network_fnc_terminalOpen,
    works there).

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
