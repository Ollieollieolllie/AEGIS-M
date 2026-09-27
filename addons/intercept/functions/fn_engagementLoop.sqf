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

    Two distinct paths depending on whether this System is networked
    (synced to an AEGISM_Module_Site):

    NETWORKED: the Site's own aegism_intercept_fnc_assignEngagements
    coordinator (run once per Site, across every member System, before this
    loop's own tick) has already decided which contact -- if any -- THIS
    System's THIS role should engage this tick, recorded as an assignment
    record in the Network's "AEGISM_claims" HashMap (keyed by contact netId,
    value an array of per-role assignment records). This loop just looks up
    whether any current assignment names this System+role, and if so
    executes it -- it does not call aegism_intercept_fnc_selectTarget at all,
    since picking WHICH contact this weapon takes is now assignEngagements'
    job, done with visibility across the whole Site rather than one System's
    own narrow view. A fired shot's outcome (hit/miss) is written back onto
    that same assignment record (lastShotAt/roundsFired) so assignEngagements
    can detect a failed shot next tick and re-decide (same System again, a
    different/better-fit weapon, or CIWS once any "last resort" gate allows
    it) rather than this loop blindly persisting its own salvo state forever.

    STANDALONE (no Network synced): falls back to the ORIGINAL per-System
    behaviour -- gathers this System's own pooled contacts, hands them to
    aegism_intercept_fnc_selectTarget to pick the doctrine-preferred in-
    envelope target, and tracks its own acquisition/salvo state locally
    ("AEGISM_engagementState_<role>"), since there's no Site coordinator to
    defer to and no sibling System to conflict with.

    Both paths share: which of this role's real weapons (aegism_system_fnc_
    discoverCapabilities's launcherWeapons/ciwsWeapons) currently has live
    ammo, the doctrine's minShotInterval (crew-modulated), a crew reaction-
    time hesitation window that restarts whenever the acquired target
    changes, a salvo cap (salvoSize) on repeat shots at the same target, the
    optional cost/value judgment gate, and a final LOS re-check right before
    firing.

    If the resolved Crew has "Enable Cost/Value Judgment" set, one further
    gate applies right before firing: the crew declines to engage the
    selected target if doing so would leave fewer rounds (summed live
    across this role's weapons) than there are currently-pooled contacts of
    strictly higher threat value (aegism_intercept_fnc_threatValue) than it
    -- i.e. it holds fire on a low-value contact to keep stock in reserve
    for higher-value ones it can already see, rather than greedily spending
    its last rounds on whatever it acquired first.

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

private _systemData = _system getVariable ["AEGISM_system", createHashMap];
private _engagementSettings = _system getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_engagementSettings") then { _engagementSettings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
private _crew = _system getVariable "AEGISM_resolvedCrew";
if (isNil "_crew") then { _crew = [_system] call aegism_system_fnc_resolveCrew; };
private _crewMods = [_crew] call aegism_intercept_fnc_applyCrewModulation;

private _weaponPool = _systemData get (["launcherWeapons", "ciwsWeapons"] select (_role == "ciws"));
private _weaponPos = AGLToASL (eyePos _system);
private _network = _system getVariable ["AEGISM_network", objNull];

if (!isNull _network) then {
    // --- NETWORKED: execute this Site's own assignment, don't re-decide ---
    // aegism_intercept_fnc_assignEngagements already picked which contact
    // (if any) this System+role should engage this tick, across the whole
    // Site rather than this System's own narrow view -- find it.
    private _claims = _network getVariable ["AEGISM_claims", createHashMap];
    private _target = objNull;
    private _record = objNull;
    {
        private _contactKey = _x;
        private _records = _claims get _contactKey;
        private _idx = _records findIf { (_x get "system") == _system && {(_x get "role") == _role} };
        if (_idx != -1) exitWith {
            _target = objectFromNetId _contactKey;
            _record = _records select _idx;
        };
    } forEach (keys _claims);

    if (isNull _target || {isNull _record}) exitWith {};
    if (!alive _target) exitWith {};

    private _weaponInfo = _record get "weaponInfo";
    _weaponInfo params ["_turretPath", "", "_magClass"];
    if ((_system magazineTurretAmmo [_magClass, _turretPath]) <= 0) exitWith {}; // depleted since assignment -- assignEngagements will hand this contact elsewhere next tick

    private _reactionTime = _crewMods get "reactionTime";
    if (_role == "ciws") then { _reactionTime = _reactionTime min AEGISM_CIWS_REACTION_CAP; };
    if (time < (_record get "assignedAt") + _reactionTime) exitWith {}; // crew still reacting to the assignment

    private _minShotInterval = (_engagementSettings getOrDefault ["minShotInterval", 4]) * (_crewMods get "shotIntervalMult");
    private _lastShotAt = _record get "lastShotAt";
    if (_lastShotAt >= 0 && {time < _lastShotAt + _minShotInterval}) exitWith {}; // still cooling down between shots

    private _salvoSize = _engagementSettings getOrDefault ["salvoSize", 1];
    if ((_record get "roundsFired") >= _salvoSize) exitWith {}; // salvo policy already spent on this assignment (assignEngagements will judge success/failure and re-decide)

    private _targetPos = getPosASL _target;
    private _losClear = (lineIntersectsSurfaces [_weaponPos, _targetPos, _system, _target, true, 1]) isEqualTo [];
    if (!_losClear) exitWith {
        diag_log text format ["[AEGIS-M] LOS-BLOCKED: %1 (role=%2) cannot see assigned contact %3 -- staying assigned, retrying next tick.", _system, _role, _target];
    }; // masked right now -- stay assigned, re-check next tick

    [_system, _target, _weaponInfo, (_crewMods get "reliability")] call aegism_intercept_fnc_fireWeapon;

    _record set ["lastShotAt", time];
    _record set ["roundsFired", (_record get "roundsFired") + 1];
} else {
    // --- STANDALONE: original per-System selection, no Site to defer to ---
    private _stateKey = format ["AEGISM_engagementState_%1", _role];

    private _readyWeapons = _weaponPool select {
        _x params ["_turretPath", "", "_magClass"];
        (_system magazineTurretAmmo [_magClass, _turretPath]) > 0
    };
    if (_readyWeapons isEqualTo []) exitWith {}; // out of ammo on every weapon for this role -- rearm is the game's problem, not ours

    private _pool = _system getVariable ["AEGISM_pooledContacts", createHashMap];
    private _candidates = (values _pool) apply { [_x get "object", _x get "class"] };
    if (_candidates isEqualTo []) exitWith {};

    private _target = [_weaponPos, _candidates, _engagementSettings] call aegism_intercept_fnc_selectTarget;

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
    // that were never going to fire anyway.
    private _targetPos = getPosASL _target;
    private _losClear = (lineIntersectsSurfaces [_weaponPos, _targetPos, _system, _target, true, 1]) isEqualTo [];
    if (!_losClear) exitWith {}; // masked right now (e.g. a terrain-following threat behind cover) -- stay acquired, re-check next tick

    [_system, _target, (_readyWeapons select 0), (_crewMods get "reliability")] call aegism_intercept_fnc_fireWeapon;

    _state set ["lastShotTime", time];
    _state set ["roundsFiredThisEngagement", (_state get "roundsFiredThisEngagement") + 1];
    _system setVariable [_stateKey, _state, false];
};
