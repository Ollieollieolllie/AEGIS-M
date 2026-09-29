/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_removeContact

Description:
    Removes a contact from a System's or Network's tracked-contact pool
    (e.g. once a tracked munition is destroyed or lands). Companion to
    aegism_detect_fnc_addContact. Takes the contact's key (aegism_fnc_
    contactKey) or the object: a munition is usually already deleted when
    this is called, and a deleted object no longer tells you its key.

Parameters:
    _poolOwner - the System vehicle or Network logic holding the pool <OBJECT>
    _contact - the contact's key, or the object <STRING, OBJECT>

Returns:
    Nothing

Examples:
    [_site, "m42"] call aegism_detect_fnc_removeContact;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_poolOwner", "_contact"];

if (isNull _poolOwner) exitWith {};
private _pool = _poolOwner getVariable "AEGISM_pooledContacts";
if (isNil "_pool") exitWith {};

// if/else, not [a, b] select: both elements of an array literal are
// evaluated, and a key string isn't an object.
_pool deleteAt (if (_contact isEqualType "") then { _contact } else { [_contact] call aegism_fnc_contactKey });
