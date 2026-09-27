/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_selectTarget

Description:
    Pure target-selection function: given a System's weapon position and its
    resolved Engagement Settings, filters a list of candidate contacts down
    to the engagement envelope (range/altitude/target-class allowlist -- the
    allowlist is re-checked here rather than trusted from the pool, since a
    networked System reads its Network's shared pool, which may contain
    contacts allowlisted for other member Systems' own overriding doctrine
    but not this one) and picks the single best target per the doctrine's
    targetPriority rule.

    Network target deconfliction: a candidate already claimed by a
    different, still-live System within AEGISM_CLAIM_TIMEOUT seconds is
    excluded outright, so two Systems sharing a Network's pool don't both
    converge on and empty their magazines into the same single contact
    while everything else goes unengaged. A candidate this System already
    claims itself remains selectable (so it keeps re-acquiring its own
    in-progress target). Claims are read-only here; the engagement loop
    that receives the returned target is what actually renews the claim
    every tick it keeps pursuing it.

    Does not read or write any pool, ammo, or engagement-state variable --
    callers (the engagement loop) decide what to do with the returned
    target.

Parameters:
    _weaponPos - ASL position to range/envelope-check candidates against
        <ARRAY (PositionASL)>
    _candidates - contact entries from one or more pooled-contact HashMaps
        (see aegism_detect_fnc_addContact), as an array of
        [object, class, confidence] <ARRAY of ARRAY>
    _engagementSettings - resolved doctrine, from aegism_system_fnc_
        resolveEngagementSettings <HASHMAP>
    _system - the System selecting a target, for comparing against a
        candidate's claimant <OBJECT>
    _claims - the Network's deconfliction ledger (contact netId -> [claiming
        System, claim time]), or an empty HashMap if this System has no
        Network to deconflict against <HASHMAP>

Returns:
    The selected target object, or objNull if no candidate is in envelope
    <OBJECT>

Examples:
    [_weaponPos, _candidates, _engagementSettings, _system, _claims] call aegism_intercept_fnc_selectTarget;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_CLAIM_TIMEOUT 3

params ["_weaponPos", "_candidates", "_engagementSettings", "_system", "_claims"];

private _minRange = [_engagementSettings getOrDefault ["minRange", 500]] call aegism_fnc_scaledRange;
private _maxRange = [_engagementSettings getOrDefault ["maxRange", 8000]] call aegism_fnc_scaledRange;
private _minAltitude = _engagementSettings getOrDefault ["minAltitude", 0];
private _maxAltitude = _engagementSettings getOrDefault ["maxAltitude", 6000];
private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
private _priority = _engagementSettings getOrDefault ["targetPriority", "nearest"];

private _inEnvelope = _candidates select {
    _x params ["_object", "_class"];

    if (isNull _object || {!alive _object} || {!(_class in _allowlist)}) exitWith { false };

    private _claim = _claims getOrDefault [str (netId _object), []];
    if (count _claim > 0) then {
        _claim params ["_claimant", "_claimedAt"];
        if (_claimant != _system && {(time - _claimedAt) < AEGISM_CLAIM_TIMEOUT}) exitWith { false };
    };

    private _targetPos = getPosASL _object;
    private _dist = _weaponPos distance _targetPos;
    private _altitude = _targetPos select 2;

    (_dist >= _minRange) && {_dist <= _maxRange} && {_altitude >= _minAltitude} && {_altitude <= _maxAltitude}
};

if (_inEnvelope isEqualTo []) exitWith { objNull };

// Score every in-envelope candidate per the doctrine's priority rule (higher
// score = more preferred), then pick the object paired with the max score --
// SQF's selectMax only works on a flat array of numbers, so scores and
// objects are tracked as parallel arrays rather than a single array of pairs.
private _objects = _inEnvelope apply { _x select 0 };
private _scores = switch (_priority) do {
    case "fastestClosing": {
        // Closing speed: component of target velocity opposite the
        // line-of-sight from the weapon, i.e. how fast the range is
        // shrinking. Higher (more positive) = closing faster.
        _inEnvelope apply {
            _x params ["_object"];
            private _los = vectorNormalized (getPosASL _object vectorDiff _weaponPos);
            -(velocity _object vectorDotProduct _los)
        };
    };
    case "highestValue": {
        _inEnvelope apply {
            _x params ["_object", "_class"];
            [_class] call aegism_intercept_fnc_threatValue
        };
    };
    default { // "nearest" -- negate distance so the closest target has the highest score
        _inEnvelope apply {
            _x params ["_object"];
            -(_weaponPos distance (getPosASL _object))
        };
    };
};

_objects select (_scores find (selectMax _scores))
