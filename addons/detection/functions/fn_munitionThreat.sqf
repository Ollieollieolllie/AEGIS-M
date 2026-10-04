/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_munitionThreat

Description:
    Whether a munition is a threat to what a pool owner protects: every live
    member of its Site (of every Site linked with it, aegism_network_fnc_
    linkSites), or just itself if standalone. Asked of a friendly or
    neutral munition (engaged only if so), and of any hostile munition when
    the Site only engages threats (aegism_detect_fnc_munitionCheck).

        missile - its own seeker target (missileTarget) is one of the
            protected vehicles ("guided"), or its current line of flight
            passes within the threat radius of one, closing ("heading")
        bomb - its line of flight passes within the threat radius, or its
            predicted fall lands within it
        artillery round, rocket - its predicted impact falls within the
            threat radius of one of them ("ballistic"). Prediction is a
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
    distance m <NUMBER>, threat radius m <NUMBER>, "guided" | "heading" |
    "ballistic"]

Examples:
    [_shell, "artilleryShell", _radar, 0] call aegism_detect_fnc_munitionThreat;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_GRAVITY 9.80665

params ["_projectile", "_class", "_poolOwner", ["_radiusSetting", 0]];

// A Site linked to others protects the whole group (aegism_network_fnc_
// linkSites).
private _network = _poolOwner getVariable ["AEGISM_network", objNull];
private _protected = if (isNull _network) then { [_poolOwner] } else {
    (_network getVariable ["AEGISM_groupMembers", _network getVariable ["AEGISM_networkMembers", []]]) select { !isNull _x && {alive _x} }
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

// The config radius, cached per ammo type ("AEGISM_cacheThreatRadius"): this
// runs every tracker check for every munition that needs a threat verdict.
private _radius = _radiusSetting;
if (_radius <= 0) then {
    private _cache = missionNamespace getVariable "AEGISM_cacheThreatRadius";
    if (isNil "_cache") then {
        _cache = createHashMap;
        missionNamespace setVariable ["AEGISM_cacheThreatRadius", _cache];
    };
    _radius = _cache get (typeOf _projectile);
    if (isNil "_radius") then {
        private _ammoCfg = configOf _projectile;
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
        _cache set [typeOf _projectile, _radius];
    };
};

private _missileTarget = if (_class == "missile") then { missileTarget _projectile } else { objNull };
if (!isNull _missileTarget && {_missileTarget in _protected}) exitWith {
    [_missileTarget, 0, _radius, "guided"]
};

private _pos = getPosASL _projectile;
private _velocity = velocity _projectile;
_velocity params ["_vx", "_vy", "_vz"];

private _best = [];
// A missile or bomb flying straight at the Site: the closest its current
// line of flight comes to a protected vehicle (it steers or glides, so its
// fall alone says little), if it's closing.
if (_class in ["missile", "bomb"]) then {
    private _speedSq = _velocity vectorDotProduct _velocity;
    if (_speedSq > 0) then {
        {
            private _toVehicle = (getPosASL _x) vectorDiff _pos;
            private _along = (_toVehicle vectorDotProduct _velocity) / _speedSq;
            if (_along > 0) then {
                private _miss = vectorMagnitude (_toVehicle vectorDiff (_velocity vectorMultiply _along));
                if (_miss <= _radius && {_best isEqualTo [] || {_miss < (_best select 1)}}) then {
                    _best = [_x, _miss, _radius, "heading"];
                };
            };
        } forEach _protected;
    };
};
// A missile guided at something else, not flying at the Site: no threat.
if (_class == "missile") exitWith { _best };

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
