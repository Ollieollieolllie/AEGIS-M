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

    Every add/refresh stamps "lastSeen" (time). Pools are pruned by EXPIRY
    (aegism_detect_fnc_pruneStaleContacts), not by any single sensor
    deciding it can no longer see something -- a Site pool is fed by
    several radars plus the munition tracker, and one radar losing sight of
    a contact another radar still holds must not delete it (that used to
    delete the contact's engagement assignment every second, restarting the
    crew reaction timer so the launcher never fired). "isMunition" marks
    Fired-pipeline contacts, which a radar's getSensorTargets never reports.

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

private _pool = _poolOwner getVariable ["AEGISM_pooledContacts", createHashMap];
// netId is already a string -- wrapping it in str would add literal quote
// characters, and objectFromNetId on such a key returns objNull.
private _key = netId _contactObject;

if (_key in _pool) then {
    private _existing = _pool get _key;
    _existing set ["class", _contactClass];
    _existing set ["confidence", _confidence];
    _existing set ["lastSeen", time];
} else {
    _pool set [_key, createHashMapFromArray [
        ["object", _contactObject],
        ["class", _contactClass],
        ["confidence", _confidence],
        ["firstSeen", time],
        ["lastSeen", time],
        ["isMunition", _contactClass in ["missile", "rocket", "bomb", "artilleryShell"]]
    ]];
};

_poolOwner setVariable ["AEGISM_pooledContacts", _pool, false];

true
