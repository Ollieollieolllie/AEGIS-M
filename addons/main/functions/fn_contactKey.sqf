/* ----------------------------------------------------------------------------
Function: aegism_fnc_contactKey

Description:
    The key a contact is stored under in every pool and claims HashMap.

        munition - the id the munition tracker gave it when tracking started
            ("AEGISM_contactKey", aegism_detect_fnc_trackMunition): "m<n>"
        anything else (aircraft) - its netId

    Munitions don't use netId: the server's copy of a projectile fired on
    another machine isn't a network object, and netId isn't guaranteed to
    tell such local objects apart -- two shells sharing one key would share
    one pool entry, and the Site would engage them one at a time.

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
