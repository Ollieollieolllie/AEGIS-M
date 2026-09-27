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

if (isNull _target || {!alive _target}) exitWith { false };
if (random 1 > _reliability) exitWith { false }; // crew didn't get a clean shot off this cycle

if (!isNil "ace_missileguidance_fnc_onFired") then {
    private _ammoClassName = getText (configFile >> "CfgMagazines" >> _magazineClass >> "ammo");
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

_system fireAtTarget [_target, _weaponClass]
