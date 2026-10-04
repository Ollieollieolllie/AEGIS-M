/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_isTerminal

Description:
    Whether an object synced to a Site is one of its status terminals
    (aegism_network_fnc_terminalAction) rather than an alarm speaker: a
    laptop -- any object whose class name has "laptop" in it (vanilla's
    Land_Laptop_F, Land_Laptop_unfolded_F, Land_Laptop_device_F,
    Land_Laptop_02_unfolded_F...).

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
