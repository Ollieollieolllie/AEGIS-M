/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_munitionSize

Description:
    Reads a CfgAmmo entry's indirectHitRange (blast radius, metres) as a
    real-config proxy for a munition's physical size/destructive class --
    used both to size an incoming contact's own munition (how big is the
    missile bearing down on us) and an interceptor's loaded ammo (how big
    a warhead does this launcher's weapon carry), so aegism_intercept_fnc_
    assignEngagements can match one against the other without a mission
    designer hand-tuning a "small/medium/large" tier per class.

    indirectHitRange is engine-mandatory for anything meant to actually
    explode (the engine uses it directly for splash damage, so it's
    populated consistently across vanilla, ACE3, RHS, and CUP ammo rather
    than being an optional/author-forgotten field), and scales monotonically
    with real-world warhead scale: near-zero for small arms/unguided AT
    rockets, moderate for a MANPAD/Titan-class missile, large for an anti-
    ship missile or aircraft bomb. hit (direct-hit damage) is NOT used here
    -- it's noisy across ammo roles (some launchers front-load direct hit
    and leave indirectHit/indirectHitRange comparatively small), where
    indirectHitRange stays a consistent physical-scale signal regardless of
    how a given mod's author balanced direct vs. splash damage.

    Plain (non-explosive) gun ammo, e.g. a CIWS autocannon's own rounds,
    correctly returns 0 -- it has no blast radius, and 0 is the right
    "size" for a weapon whose actual lethality against an incoming munition
    comes from raw rate of fire and hit probability, not warhead energy.

Parameters:
    _ammoClassName - a CfgAmmo classname <STRING>

Returns:
    indirectHitRange in metres, or 0 if the ammo doesn't define one (plain
    kinetic ammo, or an invalid classname) <NUMBER>

Examples:
    ["M_Titan_AA"] call aegism_intercept_fnc_munitionSize;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_ammoClassName"];

private _ammoConfig = configFile >> "CfgAmmo" >> _ammoClassName;
if (!isClass _ammoConfig) exitWith { 0 };

getNumber (_ammoConfig >> "indirectHitRange")
