/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_munitionThreat

Description:
    Whether a munition that IFF would otherwise ignore (fired by a friendly
    or neutral side) is predicted to hit what a pool owner protects: every
    live member of its Site, or just itself if standalone.

        guided missile - its own seeker target (missileTarget) is one of the
            protected vehicles
        anything else (or a missile with no target) - its predicted impact
            falls within the threat radius of one of them. Prediction is a
            drag-free ballistic fall from the current position and velocity
            to each protected vehicle's own height. Vanilla artillery really
            is drag-free (Sh_155mm_AMOS and the MLRS R_230mm_fly have
            airFriction 0, mortar rounds ~-0.0003), so this is accurate for
            the rounds that matter; a still-burning rocket is under-predicted
            until burnout, and re-evaluated every tracker tick anyway.

    Threat radius: the doctrine friendlyThreatRadius if > 0, else the
    munition's own CfgAmmo dangerRadiusHit (the radius the game's AI keeps
    friendlies out of, e.g. 750m for 155mm, 1250m for the MLRS rocket,
    1000m for bombs), else its blast radius (indirectHitRange) when
    dangerRadiusHit is unset (-1). A carrier round uses its payload's
    radius (see below).

Parameters:
    _projectile - the munition <OBJECT>
    _class - its threat class, from aegism_detect_fnc_classifyTarget <STRING>
    _poolOwner - the radar System evaluating it <OBJECT>
    _radiusSetting - doctrine friendlyThreatRadius, 0 = from config <NUMBER>

Returns:
    [] if no threat, else [threatened vehicle <OBJECT>, predicted miss
    distance m <NUMBER>, threat radius m <NUMBER>, "guided" | "ballistic"]

Examples:
    [_shell, "artilleryShell", _radar, 0] call aegism_detect_fnc_munitionThreat;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_GRAVITY 9.80665

params ["_projectile", "_class", "_poolOwner", ["_radiusSetting", 0]];

private _network = _poolOwner getVariable ["AEGISM_network", objNull];
private _protected = if (isNull _network) then { [_poolOwner] } else {
    (_network getVariable ["AEGISM_networkMembers", []]) select { !isNull _x && {alive _x} }
};
if (_protected isEqualTo []) exitWith { [] };

// A carrier round (simulation shotSubmunitions, e.g. the MLRS R_230mm_HE)
// has no warhead of its own -- dangerRadiusHit -1 and a token blast radius
// -- because its payload is the submunition it releases near the target
// (R_230mm_fly: dangerRadiusHit 1250). Judged on its own numbers, a carrier
// on a dead-centre trajectory was never a threat, so a friendly MLRS salvo
// was only flagged once the terminal stage appeared ~500m from impact. The
// radius is taken from the payload instead (the first listed submunition,
// or the heaviest-weighted one of a weighted list).
private _fnRadius = {
    params ["_cfg"];
    private _r = getNumber (_cfg >> "dangerRadiusHit");
    if (_r <= 0) then { _r = getNumber (_cfg >> "indirectHitRange"); };
    _r
};

private _ammoCfg = configOf _projectile;
private _radius = _radiusSetting;
if (_radius <= 0) then {
    _radius = [_ammoCfg] call _fnRadius;
    if ((toLower getText (_ammoCfg >> "simulation")) == "shotsubmunitions") then {
        private _payload = if (isArray (_ammoCfg >> "submunitionAmmo")) then {
            // [class, weight, class, weight, ...] -> heaviest weight
            private _list = getArray (_ammoCfg >> "submunitionAmmo");
            private _best = "";
            private _bestWeight = -1;
            for "_i" from 0 to (count _list - 2) step 2 do {
                if ((_list select (_i + 1)) > _bestWeight) then { _best = _list select _i; _bestWeight = _list select (_i + 1); };
            };
            _best
        } else {
            getText (_ammoCfg >> "submunitionAmmo")
        };
        private _payloadCfg = configFile >> "CfgAmmo" >> _payload;
        if (isClass _payloadCfg) then { _radius = _radius max ([_payloadCfg] call _fnRadius); };
    };
};

private _missileTarget = if (_class == "missile") then { missileTarget _projectile } else { objNull };
if (!isNull _missileTarget) exitWith {
    [[], [_missileTarget, 0, _radius, "guided"]] select (_missileTarget in _protected)
};

private _pos = getPosASL _projectile;
(velocity _projectile) params ["_vx", "_vy", "_vz"];

private _best = [];
{
    // Later root of z0 + vz*t - g*t^2/2 = protected vehicle's height: the
    // moment the round comes down through that height.
    private _disc = _vz * _vz + 2 * AEGISM_GRAVITY * ((_pos select 2) - ((getPosASL _x) select 2));
    if (_disc >= 0) then {
        private _t = (_vz + sqrt _disc) / AEGISM_GRAVITY;
        if (_t > 0) then {
            private _miss = [(_pos select 0) + _vx * _t, (_pos select 1) + _vy * _t] distance2D _x;
            if (_miss <= _radius && {_best isEqualTo [] || {_miss < (_best select 1)}}) then {
                _best = [_x, _miss, _radius, "ballistic"];
            };
        };
    };
} forEach _protected;

_best
