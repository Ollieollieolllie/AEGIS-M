/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_debugCheckCiws

Description:
    On-demand CIWS-qualification check for a specific vehicle, meant to be
    run from the Arma debug console while testing -- answers "why doesn't
    this vehicle's gun register as CIWS-capable" directly, by walking every
    currently-loaded gun magazine through the exact same real-config checks
    aegism_system_fnc_discoverCapabilities itself uses (magazinesAllTurrets,
    ammo classification, reloadTime vs. the CIWS rate-of-fire threshold),
    rather than requiring a rebuild/RPT-log round trip to see the same
    numbers aegism_system_fnc_discoverCapabilities's own diag_log already
    reports on a fresh scan.

    For every magazine currently loaded anywhere on the vehicle that
    classifies as plain (non-guided) gun ammo (i.e. NOT missile/rocket --
    those go through the launcher path instead, not this check): reports
    the turret, the resolved firing weapon, the ammo classname, its real
    reloadTime, and whether that reloadTime actually clears the CIWS
    threshold, with the exact comparison spelled out.

    Also reports the vehicle's OWN currently-cached AEGISM_system capability
    HashMap (if it has one) so a stale cache from before a rearm/loadout
    change is visible too, alongside what a fresh check finds right now.

Parameters:
    _vehicle - the vehicle to check <OBJECT>

Returns:
    Nothing

Examples:
    [cursorObject] call aegism_system_fnc_debugCheckCiws;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle"];

if (isNull _vehicle) exitWith {
    hint "[AEGIS-M] DEBUG CIWS CHECK: no vehicle given (pass cursorObject or a specific object).";
};

#define AEGISM_CIWS_ROF_THRESHOLD 0.3

private _lines = [format ["=== AEGIS-M CIWS Check: %1 (%2) ===", _vehicle, typeOf _vehicle]];

private _cachedSystem = _vehicle getVariable "AEGISM_system";
if (isNil "_cachedSystem") then {
    _lines pushBack "Cached AEGISM_system: none -- this vehicle has never been recognized as an AEGIS-M System at all.";
} else {
    _lines pushBack format ["Cached AEGISM_system: hasRadar=%1 launcherWeapons=%2 ciwsWeapons=%3 (from whenever this vehicle was last scanned -- may be stale if the loadout changed since)", _cachedSystem get "hasRadar", count (_cachedSystem get "launcherWeapons"), count (_cachedSystem get "ciwsWeapons")];
};

_lines pushBack "Live gun-magazine check (right now):";

private _anyGunMagazine = false;
{
    _x params ["_magClass", "_turretPath"];
    private _ammoClassName = getText (configFile >> "CfgMagazines" >> _magClass >> "ammo");
    private _class = [_ammoClassName] call aegism_detect_fnc_classifyAmmoClass;

    // Only plain gun ammo goes through the CIWS check -- a missile/rocket
    // magazine is a launcher weapon instead, not relevant to this check.
    if !(_class in ["missile", "rocket"]) then {
        private _weaponClass = "";
        {
            if (_magClass in (getArray (configFile >> "CfgWeapons" >> _x >> "magazines"))) exitWith {
                _weaponClass = _x;
            };
        } forEach (_vehicle weaponsTurret _turretPath);

        if (_weaponClass != "") then {
            _anyGunMagazine = true;
            private _reloadTime = getNumber (configFile >> "CfgAmmo" >> _ammoClassName >> "reloadTime");
            private _qualifies = _reloadTime > 0 && {_reloadTime < AEGISM_CIWS_ROF_THRESHOLD};
            _lines pushBack format ["  - turret %1, weapon %2, ammo %3: reloadTime=%4 -- %5 (need > 0 and < %6)", _turretPath, _weaponClass, _ammoClassName, _reloadTime, ["DOES NOT QUALIFY", "QUALIFIES"] select _qualifies, AEGISM_CIWS_ROF_THRESHOLD];
        };
    };
} forEach (magazinesAllTurrets _vehicle);

if (!_anyGunMagazine) then {
    _lines pushBack "  (no plain gun magazine found on this vehicle at all -- only missile/rocket magazines, or none loaded)";
};

private _fullMsg = _lines joinString "\n";
hint _fullMsg;
diag_log text _fullMsg;
