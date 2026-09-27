/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_addContact

Description:
    Adds a candidate contact to a System's or Network's tracked-contact
    list, gated by that object's resolved Doctrine target-class allowlist
    (aegism_system_fnc_resolveEngagementSettings). A contact whose class is
    not on the allowlist is never added, per the AEGIS-M architecture plan
    (section 2) target-class filter requirement.

    Contacts are stored as a HashMap keyed by the contact object's netId
    (stable across the object's lifetime, safe as a HashMap key), with
    value ["confidence" -> Number, "class" -> String, "object" -> Object,
    "firstSeen" -> Number (time)]. Stored on the pool owner (System or
    Network) as "AEGISM_pooledContacts". "confidence" is always 1 now that
    detection is sourced from getSensorTargets (see aegism_detect_fnc_
    confidenceLoop) -- the engine already decided detected-or-not using its
    own sensor simulation, so there's no gradient left for AEGIS-M to
    layer a probabilistic score on top of; the field is kept only so
    callers that pattern-match a contact entry's shape don't need to change.

    Re-adding an already-pooled contact (e.g. the confidence loop
    refreshing a platform's presence every tick) updates its class in
    place rather than replacing the whole entry, so "firstSeen" stays
    accurate across refreshes.

Parameters:
    _poolOwner - the System vehicle or Network logic holding the pool <OBJECT>
    _contactObject - the munition or platform to add <OBJECT>
    _contactClass - pre-classified target class, from aegism_detect_fnc_
        classifyTarget <STRING>
    _confidence - always 1 in current callers (kept for the pool entry's
        shape, see above) <NUMBER>

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

if (_key in _pool) then {
    private _existing = _pool get _key;
    _existing set ["class", _contactClass];
    _existing set ["confidence", _confidence];
} else {
    _pool set [_key, createHashMapFromArray [
        ["object", _contactObject],
        ["class", _contactClass],
        ["confidence", _confidence],
        ["firstSeen", time]
    ]];
};

_poolOwner setVariable ["AEGISM_pooledContacts", _pool, false];

true
