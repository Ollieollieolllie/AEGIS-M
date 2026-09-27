/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_addContact

Description:
    Adds a candidate contact to a System's or Network's tracked-contact
    list, gated by that object's resolved Engagement Settings target-class
    allowlist (aegism_system_fnc_resolveEngagementSettings). A contact whose
    class is not on the allowlist is never added, per the AEGIS-M
    architecture plan (section 2) target-class filter requirement.

    Contacts are stored as a HashMap keyed by the contact object's netId
    (stable across the object's lifetime, safe as a HashMap key), with
    value ["confidence" -> Number 0-1, "class" -> String, "object" -> Object,
    "firstSeen" -> Number (time)]. Stored on the pool owner (System or
    Network) as "AEGISM_pooledContacts".

Parameters:
    _poolOwner - the System vehicle or Network logic holding the pool <OBJECT>
    _contactObject - the munition or platform to add <OBJECT>
    _contactClass - pre-classified target class, from aegism_detect_fnc_
        classifyTarget <STRING>
    _confidence - initial detection confidence, 0-1 (munitions are added at
        1 since they were directly observed being fired) <NUMBER>

Returns:
    True if the contact was added (class was allowlisted), false if it was
    rejected by the allowlist or already null <BOOLEAN>

Examples:
    [_system, _missile, "missile", 1] call aegism_detect_fnc_addContact;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_poolOwner", "_contactObject", "_contactClass", "_confidence"];

if (isNull _contactObject || {_contactClass == ""}) exitWith { false };

private _engagementSettings = [_poolOwner] call aegism_system_fnc_resolveEngagementSettings;
private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
if !(_contactClass in _allowlist) exitWith { false };

private _pool = _poolOwner getVariable ["AEGISM_pooledContacts", createHashMap];
private _key = str (netId _contactObject);

_pool set [_key, createHashMapFromArray [
    ["object", _contactObject],
    ["class", _contactClass],
    ["confidence", _confidence],
    ["firstSeen", time]
]];

_poolOwner setVariable ["AEGISM_pooledContacts", _pool, false];

true
