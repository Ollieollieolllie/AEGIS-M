/* ----------------------------------------------------------------------------
Function: aegism_fnc_contactKey

Description:
    The key a contact is stored under in every pool and claims HashMap.
    Full notes: docs/functions/main.md

Parameters:
    _object - the contact <OBJECT>

Returns:
    Key <STRING>

Examples:
    [_shell] call aegism_fnc_contactKey;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_object"];

private _key = _object getVariable "AEGISM_contactKey";
if (isNil "_key") then { _key = netId _object; };
_key
