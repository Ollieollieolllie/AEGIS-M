/* ----------------------------------------------------------------------------
Function: aegism_fnc_siteName

Description:
    A Site's name, the same in the RPT, the status board, the 3D overlay and
    the terminals: its Eden variable name, else "Site N" by the order the
    Sites were set up.
    Full notes: docs/functions/main.md

Parameters:
    _site - the Site logic <OBJECT>
    _withGrid - add its map grid, "Site 2 (grid 045123)" <BOOLEAN, default false>

Returns:
    Its name <STRING>

Examples:
    [_site] call aegism_fnc_siteName;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_site", objNull], ["_withGrid", false]];

if (isNull _site) exitWith { "no Site" };

private _name = vehicleVarName _site;
if (_name == "") then {
    private _sites = (missionNamespace getVariable ["AEGISM_allPoolOwners", []]) select { !isNull _x && {!isNil { _x getVariable "AEGISM_networkMembers" }} };
    private _index = _sites find _site;
    _name = if (_index < 0) then { "Site" } else { format ["Site %1", _index + 1] };
};
if (_withGrid) then { _name = format ["%1 (grid %2)", _name, mapGridPosition _site]; };
_name
