/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalData

Description:
    What a terminal may do and what it's connected to: a laptop where it
    stands, or a unit carrying a laptop or an AEGIS-M tablet.
    Full notes: docs/functions/modules_network.md

Parameters:
    _terminal - the laptop, or the unit carrying one or a tablet <OBJECT>
    _node - optional: the Site or vehicle it's about to be used on. A unit's
        rights differ by what it reaches a Site with <OBJECT, default objNull>

Returns:
    [access "status" or "control" <STRING>, manual interception <BOOLEAN>,
     surface strike <BOOLEAN>, the Sites and vehicles it's connected to
     <ARRAY>]

Examples:
    ([_laptop] call aegism_network_fnc_terminalData) params ["_access", "_engage", "_surface", "_link"];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_terminal", objNull], ["_node", objNull]];

if (isNull _terminal) exitWith { ["status", false, false, []] };

if !(_terminal isKindOf "CAManBase") exitWith {
    [
        _terminal getVariable ["AEGISM_terminalAccess", "status"],
        _terminal getVariable ["AEGISM_terminalEngage", false],
        _terminal getVariable ["AEGISM_terminalSurface", false],
        (_terminal getVariable ["AEGISM_terminalLink", []]) select { !isNull _x }
    ]
};
if (!alive _terminal) exitWith { ["status", false, false, []] };

// Carried: the first of the unit's laptops that it still has on it.
private _held = ((items _terminal) + (magazines _terminal)) apply { toLower _x };
private _carried = (_terminal getVariable ["AEGISM_terminalCarried", []]) select { (toLower (_x select 0)) in _held };
private _laptop = ["status", false, false, []];
if (_carried isNotEqualTo []) then {
    (_carried select 0) params ["", ["_link", []], ["_access", "status"], ["_engage", false], ["_surface", false]];
    _laptop = [_access, _engage, _surface, _link select { !isNull _x }];
};

// A tablet: every Site of the unit's side that allows remote connections,
// each with the rights that Site gives. (Listed once a second.)
private _remote = [];
if ("aegism_tablet" in _held) then {
    (missionNamespace getVariable ["AEGISM_remoteSites", [-1, []]]) params ["_at", "_sites"];
    if (CBA_missionTime - _at > 1 || {_at < 0}) then {
        _sites = (entities "AEGISM_Module_Site") select { (_x getVariable ["remoteAccess", "off"]) != "off" };
        missionNamespace setVariable ["AEGISM_remoteSites", [CBA_missionTime, _sites]];
    };
    private _side = side group _terminal;
    _remote = _sites select {
        !isNull _x && {(((_x getVariable ["AEGISM_networkMembers", []]) select { !isNull _x }) findIf { (side _x) == _side }) != -1}
    };
};
private _fnRemote = {
    switch (_this getVariable ["remoteAccess", "off"]) do {
        case "engage": { ["status", true, false] };
        case "control": { ["control", true, false] };
        case "strike": { ["control", true, true] };
        default { ["status", false, false] };
    }
};

private _link = +(_laptop select 3);
{ _link pushBackUnique _x; } forEach _remote;

// For one Site or vehicle: the laptop's rights where the laptop reaches it,
// else what its Site gives a tablet.
if (!isNull _node) exitWith {
    private _site = if (_node isKindOf "AEGISM_Module_Site") then { _node } else { _node getVariable ["AEGISM_network", objNull] };
    private _reach = +(_laptop select 3);
    { if (_x isKindOf "AEGISM_Module_Site") then { { _reach pushBackUnique _x; } forEach (_x getVariable ["AEGISM_linkSites", []]); }; } forEach (_laptop select 3);
    if (_node in _reach || {_site in _reach}) exitWith { [_laptop select 0, _laptop select 1, _laptop select 2, _link] };
    if (_site in _remote) exitWith { (_site call _fnRemote) + [_link] };
    ["status", false, false, _link]
};

// For the screen: the most any of them gives.
private _access = _laptop select 0;
private _engage = _laptop select 1;
private _surface = _laptop select 2;
{
    (_x call _fnRemote) params ["_siteAccess", "_siteEngage", "_siteSurface"];
    if (_siteAccess == "control") then { _access = "control"; };
    _engage = _engage || {_siteEngage};
    _surface = _surface || {_siteSurface};
} forEach _remote;
[_access, _engage, _surface, _link]
