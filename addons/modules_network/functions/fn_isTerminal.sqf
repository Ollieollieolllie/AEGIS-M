/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_isTerminal

Description:
    Whether an object synced to a Site is one of its status terminals (a
    laptop) rather than an alarm speaker.
    Full notes: docs/functions/modules_network.md

Parameters:
    _object - the synced object <OBJECT>

Returns:
    Whether it's a terminal <BOOLEAN>

Examples:
    [_object] call aegism_network_fnc_isTerminal;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_object"];

((toLower typeOf _object) find "laptop") >= 0
