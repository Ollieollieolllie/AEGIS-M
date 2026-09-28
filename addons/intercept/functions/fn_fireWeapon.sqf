/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_fireWeapon

Description:
    Commands a System's own real weapon to engage a target via fireAtTarget
    -- AEGIS-M never spawns its own projectile or steers it: the vehicle's
    actual loaded ammo, its real ballistics/guidance (CfgAmmo's own
    Guidance config), and the resulting damage are entirely the game's own
    simulation, exactly as if the vehicle's crew had fired it themselves.

    Crew reliability is rolled once here, gating whether the crew gets a
    clean shot off THIS cycle at all -- if the roll fails, no fireAtTarget
    command is issued and the engagement loop will simply try again next
    tick (subject to its own minShotInterval cooldown). This is different
    from AEGIS-M's earlier custom-guidance design, where reliability instead
    decided whether a self-guided round was steered to a deliberate near-
    miss: now that firing uses the vehicle's own real weapon, there is no
    scripted flight path left to deliberately spoil, so reliability governs
    the crew's shot discipline (do they loose a clean shot this cycle) and
    leaves the actual hit-or-miss outcome entirely to the game's own AI
    skill/ammo accuracy/guidance simulation.

    ACE missileguidance handoff: fireAtTarget is a pure vanilla command and
    has no interaction whatsoever with ace_missileguidance -- ACE's onFired
    handler resolves its guidance target from "ace_missileguidance_target"
    (or, for a vanilla/tab-locked fallback, missileTarget, which fireAtTarget
    also never sets) read off the SHOOTER unit at the instant of firing, not
    from fireAtTarget's own target argument. Left alone, a magazine with a
    real ACE Missileguidance config would fire genuinely unguided/ballistic
    -- no error, it just flies straight and misses anything that moves,
    which would look like a reliability/accuracy problem rather than what
    it actually is. So: if the loaded ammo declares an explicit (non-
    inherited) "ace_missileguidance" config class with enabled=1, the target
    is written to that variable on the specific turret's crewman
    (turretUnit, not the vehicle) immediately before firing. This is a no-op
    read/write on any vehicle without ACE loaded (isNil guards it) or on
    plain vanilla-guided/unguided ammo (no such config class to find).

    This does NOT, by itself, guarantee ACE actually homes the round: ACE's
    own onFired also requires its missile guidance system setting
    (GVAR(enabled), the "Missile Guidance" module/CBA setting) to allow
    AI-fired shots (level 2, "AI and Player"; level 1 is player-only and
    silently drops every AI/scripted shot back to ballistic, level 0 is
    fully off) -- that's a mission/server-side ACE setting AEGIS-M doesn't
    own or override, so a mission using this framework with AI-crewed
    Systems needs that setting at level 2 for guided interceptors to
    actually guide.

    Proximity fuse: Arma's damage system has no real projectile-vs-
    projectile hit concept, so a launcher's shot at a munition target could
    guide perfectly and still never register a kill through real collision
    alone. If the fired ammo has a real blast radius (indirectHitRange > 0,
    i.e. it's a launcher's guided munition, not a CIWS gun round -- a CIWS
    engagement relies on real collision/rate of fire and has no use for
    this), a short-lived "Fired" event handler is registered on the exact
    turret's gunner immediately before firing, to capture the REAL resulting
    projectile object (fireAtTarget doesn't return one) and hand it to
    aegism_intercept_fnc_interceptorPFH -- see that function's own doc
    comment for the actual proximity-fuse/detonation logic. The capture EH
    checks the fired ammo classname matches what was actually commanded and
    removes itself on the first match, mitigating (not perfectly
    guaranteeing -- no hard engine guarantee ties a specific Fired event to
    a specific fireAtTarget call) catching an unrelated shot from the same
    gunner in between. Self-expires after 10 seconds (CBA_fnc_waitAndExecute)
    if the expected shot never actually happens (ammo jam, crew
    reassignment, or any other reason fireAtTarget doesn't result in a real
    fired round), so the handler doesn't sit registered on that gunner for
    the rest of the mission waiting for a match that will never come.

Parameters:
    _system - the firing System vehicle <OBJECT>
    _target - the selected target object, from aegism_intercept_fnc_
        selectTarget <OBJECT>
    _weaponInfo - [_turretPath, _weaponClass, _magazineClass, size] for the
        specific weapon to fire, from aegism_system_fnc_
        discoverCapabilities's launcherWeapons/ciwsWeapons (the trailing
        size element is unused here, kept only because it's the same array
        this function is always handed) <ARRAY>
    _reliability - crew reliability, 0-1, from aegism_intercept_fnc_
        applyCrewModulation <NUMBER>

Returns:
    True if a fireAtTarget command was issued, false if the crew's
    reliability roll failed or the target was invalid <BOOLEAN>

Examples:
    [_tigris, _incomingMissile, _weaponInfo, 0.85] call aegism_intercept_fnc_fireWeapon;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_target", "_weaponInfo", "_reliability"];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

// Hard circuit breaker, deliberately independent of engagementLoop's own
// salvoSize/minShotInterval bookkeeping (which is what SHOULD already
// prevent more than one shot per assignment, but is exactly the mechanism
// under suspicion while a real multi-round-per-fireAtTarget-call bug is
// being tracked down) -- this is the single, narrowest choke point every
// real fireAtTarget call in the whole codebase passes through, so gating
// HERE guarantees no second shot from this turret regardless of what
// upstream logic (buggy or not) tries to trigger it. Keyed per turret
// (system + turretPath), not per System, so a multi-weapon System's other
// turrets are unaffected.
private _holdKey = format ["AEGISM_fireHold_%1", _turretPath];
if (_system getVariable [_holdKey, false]) exitWith {
    diag_log text format ["[AEGIS-M] FIRE-SKIP: %1 turret %2 is on hold (aegism_intercept_fnc_debugSetFireHold) -- not firing.", _system, _turretPath];
    false
};

if (isNull _target || {!alive _target}) exitWith {
    diag_log text format ["[AEGIS-M] FIRE-SKIP: %1 -- target null or already dead.", _system];
    false
};
if (random 1 > _reliability) exitWith {
    diag_log text format ["[AEGIS-M] FIRE-SKIP: %1 at %2 -- crew reliability roll failed (reliability=%3).", _system, _target, _reliability];
    false
};

private _ammoClassName = getText (configFile >> "CfgMagazines" >> _magazineClass >> "ammo");

if (!isNil "ace_missileguidance_fnc_onFired") then {
    // ACE's own guidance config class is named after its component (PREFIX
    // ace + COMPONENT missileguidance -> "ace_missileguidance", ACE's ADDON
    // macro) via ADDON, e.g. "class ADDON: GVAR(type_Javelin) { enabled=1; };"
    // nested directly in the ammo's CfgAmmo entry -- NOT "ACE_Missileguidance".
    private _guidanceCfg = configFile >> "CfgAmmo" >> _ammoClassName >> "ace_missileguidance";
    // isClass alone would also match an INHERITED guidance block -- ACE's
    // own onFired requires the ammo to declare it explicitly (configName
    // check), so mirror that here rather than setting a target variable
    // ACE would never actually read for this ammo.
    if (isClass _guidanceCfg && {(configName _guidanceCfg) == "ace_missileguidance"} && {(getNumber (_guidanceCfg >> "enabled")) == 1}) then {
        private _gunner = _system turretUnit _turretPath;
        if (!isNull _gunner) then {
            _gunner setVariable ["ace_missileguidance_target", _target];
        };
    };
};

// Proximity fuse setup: only meaningful for a real blast-radius munition
// (a launcher's guided round) -- a CIWS gun round has indirectHitRange 0
// and relies on real collision/rate of fire instead (see this function's
// own doc comment).
private _fuseRange = [_ammoClassName] call aegism_intercept_fnc_munitionSize;
if (_fuseRange > 0) then {
    private _gunner = _system turretUnit _turretPath;
    if (!isNull _gunner) then {
        // addEventHandler only returns the real handler id AFTER
        // registration, but the handler body needs that id to remove
        // itself. extraArgs elements are spread individually onto the end
        // of _this (NOT nested as one array), so the id can't be baked into
        // them directly at registration time either way -- passed instead
        // as a single-element ARRAY (_ehIdBox), a reference type in SQF:
        // mutating _ehIdBox#0 after addEventHandler returns is visible to
        // the handler on its first actual invocation, which is exactly
        // when it's needed (the handler can't remove itself before it's
        // ever run). Native "Fired" EH base params are unit/weapon/muzzle/
        // mode/ammo/magazine/projectile (indices 0-6, 7 total) -- extraArgs
        // start at index 7.
        private _ehIdBox = [-1];
        _ehIdBox set [0, _gunner addEventHandler ["Fired", {
            params ["_unit", "", "", "", "_ammo", "", "_projectile", "_expectedAmmo", "_target", "_ehIdBox"];
            if (_ammo == _expectedAmmo) then {
                _unit removeEventHandler ["Fired", _ehIdBox#0];
                _ehIdBox set [0, -1]; // signals the timeout below that this already fired
                [_projectile, _target] call aegism_intercept_fnc_interceptorPFH;
            };
        }, [_ammoClassName, _target, _ehIdBox]]];

        // Self-expiry: if fireAtTarget never actually results in a shot
        // (ammo depletes/jams, crew reassigned, or any other reason the
        // engine doesn't fire this specific round), the handler above would
        // otherwise sit registered on this gunner for the rest of the
        // mission, waiting for an ammo match that's never coming -- harmless
        // (an idle EH), but unbounded. 10s is well beyond any plausible
        // fire-command latency.
        [{
            params ["_gunner", "_ehIdBox"];
            if (!isNull _gunner && {(_ehIdBox#0) != -1}) then {
                _gunner removeEventHandler ["Fired", _ehIdBox#0];
            };
        }, [_gunner, _ehIdBox], 10] call CBA_fnc_waitAndExecute;
    };
};

private _ammoBefore = _system magazineTurretAmmo [_magazineClass, _turretPath];
diag_log text format ["[AEGIS-M] FIRE: %1 (%2) fires %3 (mag %4, %5 rounds before shot) at %6 (%7).", _system, typeOf _system, _weaponClass, _magazineClass, _ammoBefore, _target, typeOf _target];

_system fireAtTarget [_target, _weaponClass];

// Checked 1s later (not synchronously/next-frame -- the actual physical
// launch can take a moment after fireAtTarget is called, e.g. turret
// traverse/lock time, so checking too early would report a false anomaly
// before the real shot has even left the tube yet) -- if more than exactly
// 1 round is missing, that's direct proof the engine itself launched more
// than one physical round from this single fireAtTarget call, rather than
// this function (or its caller) somehow being invoked multiple times --
// fireAtTarget is only ever called from this one place in the whole
// codebase, always logged immediately above, so a genuine multi-round
// mystery narrows to exactly this.
[{
    params ["_system", "_magazineClass", "_turretPath", "_ammoBefore"];
    if (!isNull _system) then {
        private _ammoAfter = _system magazineTurretAmmo [_magazineClass, _turretPath];
        private _consumed = _ammoBefore - _ammoAfter;
        if (_consumed != 1) then {
            diag_log text format ["[AEGIS-M] FIRE-ANOMALY: %1 -- expected 1 round consumed by that shot, engine actually consumed %2 (before=%3, after=%4).", _system, _consumed, _ammoBefore, _ammoAfter];
        };
    };
}, [_system, _magazineClass, _turretPath, _ammoBefore], 1] call CBA_fnc_waitAndExecute;

true
