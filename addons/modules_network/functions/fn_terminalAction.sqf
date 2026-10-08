/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalAction

Description:
    Makes an object a terminal, on this machine: the action "AEGIS-M: Site
    Terminal" (within 3 m), which opens its screen (aegism_network_fnc_
    terminalOpen).
    Full notes: docs/functions/modules_network.md

Parameters:
    _terminal - the laptop <OBJECT>
    _anchor - the Site or vehicle it's synced to, or objNull to take the
        action away <OBJECT>

Returns:
    Nothing

Examples:
    [_laptop, _site] remoteExec ["aegism_network_fnc_terminalAction", 0, _laptop];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_terminal", "_anchor"];

if (!hasInterface || {isNull _terminal}) exitWith {};

private _previous = _terminal getVariable ["AEGISM_terminalAction", -1];
if (_previous >= 0) then {
    _terminal removeAction _previous;
    _terminal setVariable ["AEGISM_terminalAction", nil];
};
// One fixed in place can't be opened or taken from (lockInventory is each
// machine's own); it's unlocked again if that's switched off.
private _lock = !isNull _anchor && {_terminal getVariable ["AEGISM_terminalFixed", false]};
if (_lock || {_terminal getVariable ["AEGISM_terminalLocked", false]}) then {
    _terminal lockInventory _lock;
    _terminal setVariable ["AEGISM_terminalLocked", _lock];
};
if (isNull _anchor) exitWith {};

_terminal setVariable ["AEGISM_terminalAction", _terminal addAction [
    "<t color='#4FC3F7'>AEGIS-M: Site Terminal</t>",
    {
        params ["_terminal", "", "", "_anchor"];
        [_anchor, _terminal] call aegism_network_fnc_terminalOpen;
    },
    _anchor, 1.5, true, true, "", "true", 3
]];
