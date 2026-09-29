/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_addContact

Description:
    Adds a candidate contact to a System's or Network's tracked-contact
    list, gated by that object's resolved Doctrine target-class allowlist
    (aegism_system_fnc_resolveEngagementSettings). A contact whose class is
    not on the allowlist is never added.

    Contacts are stored as a HashMap keyed by the contact's key (aegism_fnc_
    contactKey: a munition's own tracker id, an aircraft's netId), with value
    ["confidence" -> Number, "class" -> String, "object" -> Object,
    "firstSeen" -> Number (time), "lastSeen" -> Number, "isMunition" ->
    Boolean]. Stored on the pool owner (System or Network) as
    "AEGISM_pooledContacts". "confidence" is always 1 (the engine's own
    sensors decide detected-or-not); the field is kept for the entry's shape.

    Re-adding an already-pooled contact updates it in place, so "firstSeen"
    stays accurate across refreshes. Every add/refresh stamps "lastSeen".
    Pools are pruned by EXPIRY (aegism_detect_fnc_pruneStaleContacts), not by
    any single sensor deciding it can no longer see something -- one radar
    losing sight of a contact another radar still holds must not delete it.
    "isMunition" marks Fired-pipeline contacts.

Parameters:
    _poolOwner - the System vehicle or Network logic holding the pool <OBJECT>
    _contactObject - the munition or platform to add <OBJECT>
    _contactClass - pre-classified target class, from aegism_detect_fnc_
        classifyTarget <STRING>
    _confidence - always 1 in current callers <NUMBER>

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

// A Site pool holds its own allowlist plus any class a member's per-vehicle
// override adds ("AEGISM_contactAllowlist", kept current by aegism_
// intercept_fnc_assignEngagements); a System's own pool uses its own resolved
// settings (Site + its overrides).
private _allowlist = _poolOwner getVariable "AEGISM_contactAllowlist";
if (isNil "_allowlist") then {
    private _engagementSettings = _poolOwner getVariable "AEGISM_resolvedEngagementSettings";
    if (isNil "_engagementSettings") then { _engagementSettings = [_poolOwner] call aegism_system_fnc_resolveEngagementSettings; };
    _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
};
if !(_contactClass in _allowlist) exitWith { false };

private _pool = _poolOwner getVariable "AEGISM_pooledContacts";
if (isNil "_pool") then {
    _pool = createHashMap;
    _poolOwner setVariable ["AEGISM_pooledContacts", _pool, false];
};
private _key = [_contactObject] call aegism_fnc_contactKey;

private _existing = _pool get _key;
if (isNil "_existing") then {
    _pool set [_key, createHashMapFromArray [
        ["object", _contactObject],
        ["class", _contactClass],
        ["confidence", _confidence],
        ["firstSeen", time],
        ["lastSeen", time],
        ["isMunition", _contactClass in ["missile", "rocket", "bomb", "artilleryShell"]]
    ]];
} else {
    _existing set ["class", _contactClass];
    _existing set ["confidence", _confidence];
    _existing set ["lastSeen", time];
};

true
