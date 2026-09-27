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

Parameters:
    _system - the firing System vehicle <OBJECT>
    _target - the selected target object, from aegism_intercept_fnc_
        selectTarget <OBJECT>
    _weaponInfo - [_turretPath, _weaponClass, _magazineClass] for the
        specific weapon to fire, from aegism_system_fnc_
        discoverCapabilities's launcherWeapons/ciwsWeapons <ARRAY>
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
_weaponInfo params ["", "_weaponClass", ""];

if (isNull _target || {!alive _target}) exitWith { false };
if (random 1 > _reliability) exitWith { false }; // crew didn't get a clean shot off this cycle

_system fireAtTarget [_target, _weaponClass]
