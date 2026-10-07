/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalScan

Description:
    One pass of the server's scan for terminals synced to a single AEGIS-M
    vehicle instead of a Site: each gets its action on every machine, and
    loses it once the sync is gone.
    Full notes: docs/functions/modules_network.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_network_fnc_terminalScan;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

if (!isServer) exitWith {};

// Terminal's netId -> [terminal, vehicle], as of the last pass.
private _known = missionNamespace getVariable ["AEGISM_vehicleTerminals", createHashMap];
private _seen = createHashMap;
{
    private _vehicle = _x;
    if (!isNil { _vehicle getVariable "AEGISM_system" } || {_vehicle getVariable ["AEGISM_systemDeferred", false]}) then {
        {
            // One synced to a Site as well is that Site's (aegism_network_fnc_
            // moduleInit), and reaches this vehicle through it or beside it.
            if ([_x] call aegism_network_fnc_isTerminal && {((synchronizedObjects _x) findIf { _x isKindOf "AEGISM_Module_Site" }) == -1}) then {
                private _id = netId _x;
                if !(_id in _seen) then {
                    _seen set [_id, [_x, _vehicle]];
                    if !(_id in _known) then { [_x, _vehicle] remoteExec ["aegism_network_fnc_terminalAction", 0, _x]; };
                };
            };
        } forEach (synchronizedObjects _vehicle);
    };
} forEach vehicles;

{
    _y params ["_terminal"];
    if (!(_x in _seen) && {!isNull _terminal} && {((synchronizedObjects _terminal) findIf { _x isKindOf "AEGISM_Module_Site" }) == -1}) then {
        [_terminal, objNull] remoteExec ["aegism_network_fnc_terminalAction", 0, _terminal];
    };
} forEach _known;
missionNamespace setVariable ["AEGISM_vehicleTerminals", _seen];
