/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_selectTarget

Description:
    Pure target-selection function: given a System's weapon position and its
    resolved Engagement Settings, filters a list of candidate contacts down
    to the engagement envelope (range/altitude/target-class allowlist) and
    picks the single best target per the doctrine's targetPriority rule.

    Only ever called by a STANDALONE System's own engagementLoop path (no
    Network synced, per aegism_system_fnc_resolveContactSource) -- a
    networked System instead reads its Site's own assignment decision
    directly from AEGISM_claims, written by aegism_intercept_fnc_
    assignEngagements, which coordinates ACROSS every member System so two
    Systems sharing a Network's pool don't both converge on the same
    contact; that cross-System deconfliction problem doesn't exist for a
    standalone System (it's the only one that can ever see or engage its
    own pool), so this function has no claims/deconfliction concept of its
    own to worry about.

    Does not read or write any pool, ammo, or engagement-state variable --
    callers (the engagement loop) decide what to do with the returned
    target.

Parameters:
    _weaponPos - ASL position to range/envelope-check candidates against
        <ARRAY (PositionASL)>
    _candidates - contact entries from this System's own pooled-contact
        HashMap (see aegism_detect_fnc_addContact), as an array of
        [object, class, confidence] <ARRAY of ARRAY>
    _engagementSettings - resolved doctrine, from aegism_system_fnc_
        resolveEngagementSettings <HASHMAP>

Returns:
    The selected target object, or objNull if no candidate is in envelope
    <OBJECT>

Examples:
    [_weaponPos, _candidates, _engagementSettings] call aegism_intercept_fnc_selectTarget;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_weaponPos", "_candidates", "_engagementSettings"];

private _minRange = [_engagementSettings getOrDefault ["minRange", 500]] call aegism_fnc_scaledRange;
private _maxRange = [_engagementSettings getOrDefault ["maxRange", 8000]] call aegism_fnc_scaledRange;
private _minAltitude = _engagementSettings getOrDefault ["minAltitude", 0];
private _maxAltitude = _engagementSettings getOrDefault ["maxAltitude", 6000];
private _allowlist = _engagementSettings getOrDefault ["targetClassAllowlist", []];
private _priority = _engagementSettings getOrDefault ["targetPriority", "nearest"];

private _inEnvelope = _candidates select {
    _x params ["_object", "_class"];

    if (isNull _object || {!alive _object} || {!(_class in _allowlist)}) exitWith { false };

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
