/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_seekerCone

Description:
    How far off its line of flight an incoming missile's guidance can be on
    a target -- what it could be homing on when its target can't be read
    (aegism_detect_fnc_munitionThreat). From its config, cached per ammo
    type ("AEGISM_cacheSeekerCone"):

        ACE-guided (the ammo declares its own ace_missileguidance class,
            enabled = 1) - its ACE seekerAngle, a half-angle
        engine-guided (CfgAmmo simulation shotMissile, maneuvrability > 0) -
            missileKeepLockedCone, else missileLockCone (the same reading as
            aegism_intercept_fnc_missileAgility): vanilla M_Scalpel_AT 60,
            Missile_AGM_01_F 20, Missile_AGM_02_F 30
        unguided - a shotMissile that can't steer (maneuvrability 0 and no
            ACE guidance: vanilla Rocket_03_HE_F, Rocket_04_HE_F), or any
            other simulation

Parameters:
    _ammo - CfgAmmo class <STRING>

Returns:
    The cone, degrees (at most 180), or -1 if it's unguided <NUMBER>

Examples:
    ["M_Scalpel_AT"] call aegism_detect_fnc_seekerCone;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_ammo"];

private _cache = missionNamespace getVariable "AEGISM_cacheSeekerCone";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheSeekerCone", _cache];
};
private _cached = _cache get _ammo;
if (!isNil "_cached") exitWith { _cached };

private _ammoCfg = configFile >> "CfgAmmo" >> _ammo;
private _aceCfg = _ammoCfg >> "ace_missileguidance";
private _cone = switch (true) do {
    case ((toLower getText (_ammoCfg >> "simulation")) != "shotmissile"): { -1 };
    // ACE's own test: the class declared on the ammo itself, not inherited.
    case (("configName _x == 'ace_missileguidance'" configClasses _ammoCfg) isNotEqualTo [] && {(getNumber (_aceCfg >> "enabled")) == 1}): {
        [180, getNumber (_aceCfg >> "seekerAngle")] select ((getNumber (_aceCfg >> "seekerAngle")) > 0)
    };
    case ((getNumber (_ammoCfg >> "maneuvrability")) <= 0): { -1 };
    default {
        private _keep = getNumber (_ammoCfg >> "missileKeepLockedCone");
        if (_keep <= 0) then { _keep = getNumber (_ammoCfg >> "missileLockCone"); };
        [180, _keep] select (_keep > 0)
    };
};
_cone = _cone min 180;

_cache set [_ammo, _cone];
_cone
