/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_engagementLoop

Description:
    Interval-based (not true per-frame, for performance) engagement decision
    loop run once per Launcher- or CIWS-capable System (registered directly
    from aegism_system_fnc_moduleInit, one registration per capability a
    vehicle's own loadout was found to have) so a self-contained Tigris/
    ZSU-style vehicle with both missiles and a gun runs its SAM and CIWS/
    CRAM decision loops independently, each with its own target-acquisition
    state -- but no ammo tracking of its own: ammo is read live from the
    vehicle's actual magazines (magazineTurretAmmo) every tick, since
    AEGIS-M never spawns or counts its own rounds.

    Each tick: gathers candidate contacts from every contact source resolved
    for this System (own radar pool and/or Network pool, per aegism_
    system_fnc_resolveContactSource), hands them to aegism_intercept_fnc_
    selectTarget to pick the doctrine-preferred in-envelope target, then
    gates firing on: which of this role's real weapons (aegism_system_fnc_
    discoverCapabilities's launcherWeapons/ciwsWeapons) currently has live
    ammo, the doctrine's minShotInterval (crew-modulated), and a crew
    reaction-time hesitation window that restarts whenever the acquired
    target changes. A salvo stops re-engaging the same target once
    salvoSize fire commands have been sent its way, per the doctrine's
    salvo policy, and resumes if the pool hands back a different target
    (e.g. the first was destroyed or lost).

    If the resolved Crew has "Enable Cost/Value Judgment" set, one further
    gate applies right before firing: the crew declines to engage the
    selected target if doing so would leave fewer rounds (summed live
    across this role's weapons) than there are currently-pooled contacts of
    strictly higher threat value (aegism_intercept_fnc_threatValue) than it
    -- i.e. it holds fire on a low-value contact to keep stock in reserve
    for higher-value ones it can already see, rather than greedily spending
    its last rounds on whatever it acquired first.

    Network deconfliction: if synced to a Network, this System reads and
    renews its pick against that Network's shared "AEGISM_claims" ledger
    (see aegism_intercept_fnc_selectTarget) every tick it keeps pursuing a
    target, so a sibling System's engagement loop sees the claim and skips
    that contact rather than also emptying its own magazine into it.

    Line-of-sight is re-checked from THIS System's own weapon position
    right before firing, independently of how the target reached the
    candidate pool -- a contact read from a Network's shared pool was
    detected by a sibling System's own sensor, which says nothing about
    whether this System can currently see it too (a different vantage
    point, or a low/terrain-following threat that ducked behind cover in
    the interval since the detecting System's last tick). A blocked LOS
    just skips firing this tick without touching acquisition/salvo state,
    since a real fire-control radar doesn't drop a track over a brief
    terrain-masking gap -- the System stays "acquired" and tries again
    next tick as the geometry changes.

    CIWS/CRAM reacts distinctly from a Launcher/SAM: its reaction time is
    capped at AEGISM_CIWS_REACTION_CAP regardless of crew skill (an
    automated fire-control slew reacts far faster than a human SAM-launch
    decision) -- both closer to how point defense actually engages a fast,
    short-lived inbound threat than a single deliberate SAM decision cycle
    could be. Firing itself is a single aegism_intercept_fnc_fireWeapon
    command either way; a CIWS-classified gun's own real CfgWeapons fire
    mode (typically full-auto/burst for an autocannon) produces the actual
    sustained-fire feel, not a script-managed burst loop.

Parameters:
    _system - the System vehicle to run this role's engagement loop for <OBJECT>
    _role - "launcher" or "ciws" -- selects which weapon pool and
        engagement-state variables this loop instance owns <STRING>

Returns:
    Nothing (intended to be wrapped in a CBA_fnc_addPerFrameHandler by the
    caller, which supplies the recurring interval)

Examples:
    [_tigris, "launcher"] call aegism_intercept_fnc_engagementLoop;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_CIWS_REACTION_CAP 1

params ["_system", "_role"];

if (isNull _system || {!alive _system}) exitWith {};

private _stateKey = format ["AEGISM_engagementState_%1", _role];

private _systemData = _system getVariable ["AEGISM_system", createHashMap];
private _engagementSettings = _system getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_engagementSettings") then { _engagementSettings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
private _crew = _system getVariable "AEGISM_resolvedCrew";
if (isNil "_crew") then { _crew = [_system] call aegism_system_fnc_resolveCrew; };
private _crewMods = [_crew] call aegism_intercept_fnc_applyCrewModulation;

// --- Live ammo: which of this role's real weapons currently has rounds ---
private _weaponPool = _systemData get (["launcherWeapons", "ciwsWeapons"] select (_role == "ciws"));
private _readyWeapons = _weaponPool select {
    _x params ["_turretPath", "", "_magClass"];
    (_system magazineTurretAmmo [_magClass, _turretPath]) > 0
};
if (_readyWeapons isEqualTo []) exitWith {}; // out of ammo on every weapon for this role -- rearm is the game's problem, not ours

// --- Gather candidates from every resolved contact source ---
// Deduplicated by netId into a HashMap first: a System with its own radar
// that's also networked can see the exact same physical contact in both
// its own pool and its Network's shared pool (aegism_detect_fnc_
// confidenceLoop populates both), and counting one contact twice would
// corrupt the cost/value judgment gate below (it compares candidate counts
// against remaining ammo).
private _network = _system getVariable ["AEGISM_network", objNull];
private _contactSource = _system getVariable ["AEGISM_resolvedContactSource", []];
private _candidateMap = createHashMap;
if ("ownRadar" in _contactSource) then {
    private _pool = _system getVariable ["AEGISM_pooledContacts", createHashMap];
    { _candidateMap set [str (netId (_x get "object")), [_x get "object", _x get "class"]] } forEach (values _pool);
};
if ("network" in _contactSource && {!isNull _network}) then {
    private _pool = _network getVariable ["AEGISM_pooledContacts", createHashMap];
    { _candidateMap set [str (netId (_x get "object")), [_x get "object", _x get "class"]] } forEach (values _pool);
};
private _candidates = values _candidateMap;
if (_candidates isEqualTo []) exitWith {};

// _claims is fetched by reference, not by value -- HashMaps are reference
// types in SQF, so mutating it below (renewing this System's claim) is
// visible immediately to every other System reading the same Network's
// AEGISM_claims on this same machine, with no setVariable write-back
// needed. This only holds because it's read fresh via getVariable every
// tick rather than cached; don't hold onto a _claims reference across
// ticks expecting it to reflect the current Network.
private _claims = if (isNull _network) then { createHashMap } else { _network getVariable ["AEGISM_claims", createHashMap] };

private _weaponPos = AGLToASL (eyePos _system);
private _target = [_weaponPos, _candidates, _engagementSettings, _system, _claims] call aegism_intercept_fnc_selectTarget;

// --- Target-acquisition / salvo state ---
private _state = _system getVariable [_stateKey, createHashMapFromArray [
    ["targetNetId", ""], ["acquiredAt", -1], ["lastShotTime", -1], ["roundsFiredThisEngagement", 0]
]];

if (isNull _target) exitWith {
    _state set ["targetNetId", ""];
    _system setVariable [_stateKey, _state, false];
};

private _targetNetId = str (netId _target);
if (_targetNetId != (_state get "targetNetId")) then {
    _state set ["targetNetId", _targetNetId];
    _state set ["acquiredAt", time];
    _state set ["roundsFiredThisEngagement", 0];
};
_system setVariable [_stateKey, _state, false];

// Renew this System's claim on the acquired target every tick it keeps
// pursuing it (not just on ticks it actually fires) -- a slower-firing
// SAM's minShotInterval can comfortably exceed AEGISM_CLAIM_TIMEOUT, so
// the claim must be kept alive independently of the firing cadence or a
// sibling System would see it lapse mid-engagement.
if (!isNull _network) then {
    _claims set [_targetNetId, [_system, time]];
};

private _salvoSize = _engagementSettings getOrDefault ["salvoSize", 1];
if ((_state get "roundsFiredThisEngagement") >= _salvoSize) exitWith {}; // salvo policy already spent on this target

private _reactionTime = _crewMods get "reactionTime";
if (_role == "ciws") then { _reactionTime = _reactionTime min AEGISM_CIWS_REACTION_CAP; };
if (time < (_state get "acquiredAt") + _reactionTime) exitWith {}; // crew still reacting to the acquisition

private _minShotInterval = (_engagementSettings getOrDefault ["minShotInterval", 4]) * (_crewMods get "shotIntervalMult");
private _lastShotTime = _state get "lastShotTime";
if (_lastShotTime >= 0 && {time < _lastShotTime + _minShotInterval}) exitWith {}; // still cooling down between shots

private _declineForCostValue = false;
if (_crew getOrDefault ["costValueJudgment", false]) then {
    private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;
    private _targetValue = [_targetClass] call aegism_intercept_fnc_threatValue;
    private _moreValuableCount = {
        ([(_x select 1)] call aegism_intercept_fnc_threatValue) > _targetValue
    } count _candidates;

    private _totalAmmo = 0;
    { _x params ["_turretPath", "", "_magClass"]; _totalAmmo = _totalAmmo + (_system magazineTurretAmmo [_magClass, _turretPath]); } forEach _weaponPool;

    _declineForCostValue = _moreValuableCount >= _totalAmmo;
};
if (_declineForCostValue) exitWith {}; // save remaining stock for higher-value threats

// Last gate, checked only once everything cheaper has already passed --
// lineIntersectsSurfaces is a real raycast, not worth paying for on ticks
// that were never going to fire anyway. Re-verifies LOS from THIS System's
// own weapon position: a candidate from a Network's shared pool was only
// ever LOS-checked from the DETECTING sibling's position (see aegism_
// detect_fnc_confidenceLoop/trackMunition), which says nothing about
// whether this System's own vantage point can see it too.
private _targetPos = getPosASL _target;
private _losClear = (lineIntersectsSurfaces [_weaponPos, _targetPos, _system, _target, true, 1]) isEqualTo [];
if (!_losClear) exitWith {}; // masked right now (e.g. a terrain-following threat behind cover) -- stay acquired, re-check next tick

[_system, _target, (_readyWeapons select 0), (_crewMods get "reliability")] call aegism_intercept_fnc_fireWeapon;

_state set ["lastShotTime", time];
_state set ["roundsFiredThisEngagement", (_state get "roundsFiredThisEngagement") + 1];
_system setVariable [_stateKey, _state, false];
