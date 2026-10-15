/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugRequest

Description:
    Server side of the debug views on a client, asked for once a second
    while either is on: the Site Status Hint's board, sent back at once,
    and the 3D overlay, sent every half second while asked for
    (aegism_fnc_debugPublish).
    Full notes: docs/functions/main.md

Parameters:
    _camera - where the client's camera is <ARRAY>
    _hint - Site Status Hint is on there <BOOLEAN>
    _draw - Enable Debug 3D Draw is on there <BOOLEAN>

Returns:
    Nothing

Examples:
    [positionCameraToWorld [0, 0, 0], true, false] remoteExecCall ["aegism_fnc_debugRequest", 2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_camera", [0, 0, 0]], ["_hint", false], ["_draw", false]];

if (!isServer) exitWith {};
private _owner = remoteExecutedOwner;
// Asked from this machine: its own views read the pipeline directly.
if (!isMultiplayer || {_owner in [0, clientOwner]}) exitWith {};

private _subscribers = missionNamespace getVariable "AEGISM_debugSubscribers";
if (isNil "_subscribers") then {
    _subscribers = createHashMap;
    missionNamespace setVariable ["AEGISM_debugSubscribers", _subscribers];
};

([_owner] call aegism_fnc_debugAllowed) params ["_allowed", "_why"];

// Said once per machine, and again if that changes.
private _logged = missionNamespace getVariable ["AEGISM_debugClientsLogged", createHashMap];
if ((_logged getOrDefault [_owner, -1]) != ([0, 1] select _allowed)) then {
    _logged set [_owner, [0, 1] select _allowed];
    missionNamespace setVariable ["AEGISM_debugClientsLogged", _logged];
    private _player = (allPlayers select { owner _x == _owner }) param [0, objNull];
    private _views = (([["Site Status Hint", _hint], ["3D draw", _draw]] select { _x select 1 }) apply { _x select 0 }) joinString ", ";
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DEBUG-VIEWS: %1 (client %2) asked for the debug views (%3) -- %4",
        if (isNull _player) then { "a machine with no player" } else { name _player }, _owner, _views,
        ["refused. " + _why, "sending them."] select _allowed];
};

if (!_allowed) exitWith {
    _subscribers deleteAt _owner;
    ["denied", _why] remoteExecCall ["aegism_fnc_debugReceive", _owner];
};

if (_draw) then { _subscribers set [_owner, CBA_missionTime]; } else { _subscribers deleteAt _owner; };
if (_hint) then {
    ["hint", [_camera] call aegism_fnc_debugBoard] remoteExecCall ["aegism_fnc_debugReceive", _owner];
};
