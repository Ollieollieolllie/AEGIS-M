/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_removeContact

Description:
    Removes a contact from a System's or Network's tracked-contact pool
    (e.g. once a tracked munition is destroyed/impacts, or a passively-
    tracked platform's confidence has decayed to zero). Companion to
    aegism_detect_fnc_addContact.

Parameters:
    _poolOwner - the System vehicle or Network logic holding the pool <OBJECT>
    _contactObject - the object to remove <OBJECT>

Returns:
    Nothing

Examples:
    [_system, _missile] call aegism_detect_fnc_removeContact;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_poolOwner", "_contactObject"];

private _pool = _poolOwner getVariable "AEGISM_pooledContacts";
if (isNil "_pool") exitWith {};

private _key = netId _contactObject;
_pool deleteAt _key;

_poolOwner setVariable ["AEGISM_pooledContacts", _pool, false];
