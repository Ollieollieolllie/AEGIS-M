/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_classifyAmmoClass

Description:
    Pure CfgAmmo classifier, extracted from aegism_detect_fnc_classifyTarget
    so the same inheritance-chain logic can classify an ammo classname
    directly (e.g. from a magazine's "ammo" config entry) as well as a live
    fired-projectile object -- used both for incoming-threat classification
    and for aegism_system_fnc_discoverCapabilities classifying a vehicle's
    OWN loaded ammo to determine whether it has launcher/CIWS capability.

    Walks the CfgAmmo config-inheritance chain (via CBA_fnc_inheritsFrom)
    against the vanilla base classes ShellCore (artillery/mortar shells),
    BombCore (aircraft bombs), MissileCore (guided missiles), and RocketCore
    (unguided rockets) -- inheritance is a more reliable discriminator than
    simulation-string matching, since mods reuse simulation types across
    different ammo roles but rarely break the base class chain.

Parameters:
    _ammoClassName - a CfgAmmo classname <STRING>

Returns:
    One of "missile" | "rocket" | "bomb" | "artilleryShell", or "" if it
    doesn't classify as any of these (e.g. plain cannon/gun ammo) <STRING>

Examples:
    ["M_Titan_AA"] call aegism_detect_fnc_classifyAmmoClass;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_ammoClassName"];

private _ammoConfig = configFile >> "CfgAmmo" >> _ammoClassName;
if (!isClass _ammoConfig) exitWith { "" };

private _missileCore = configFile >> "CfgAmmo" >> "MissileCore";
private _bombCore = configFile >> "CfgAmmo" >> "BombCore";
private _shellCore = configFile >> "CfgAmmo" >> "ShellCore";
private _rocketCore = configFile >> "CfgAmmo" >> "RocketCore";

if (isClass _missileCore && {[_ammoConfig, _missileCore] call CBA_fnc_inheritsFrom}) exitWith { "missile" };
if (isClass _bombCore && {[_ammoConfig, _bombCore] call CBA_fnc_inheritsFrom}) exitWith { "bomb" };
if (isClass _shellCore && {[_ammoConfig, _shellCore] call CBA_fnc_inheritsFrom}) exitWith { "artilleryShell" };
if (isClass _rocketCore && {[_ammoConfig, _rocketCore] call CBA_fnc_inheritsFrom}) exitWith { "rocket" };

// Fallback: simulation-string match for ammo that doesn't chain through
// the vanilla *Core classes (some mod ammo reparents directly off Default).
private _simulation = toLower getText (_ammoConfig >> "simulation");
if (_simulation == "shotmissile") exitWith { "missile" };
if (_simulation == "shotrocket") exitWith { "rocket" };
if (_simulation in ["shotshell", "shotsubmunitions"]) exitWith { "artilleryShell" };

""
