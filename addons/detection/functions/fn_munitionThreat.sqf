/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_munitionThreat

Description:
    Whether a munition is a threat to what a pool owner protects: every live
    member of its Site (of every Site linked with it,
    aegism_network_fnc_linkSites), or just itself if standalone.
    Full notes: docs/functions/detection.md

Parameters:
    _projectile - the munition <OBJECT>
    _class - its threat class, from aegism_detect_fnc_classifyTarget <STRING>
    _poolOwner - the radar System evaluating it <OBJECT>
    _radiusSetting - doctrine friendlyThreatRadius, 0 = from config <NUMBER>
    _flags - the tracked munition's flags (aegism_detect_fnc_trackMunition),
        where a missile's angle to the vehicles is kept between checks
        <HASHMAP, default a new one>
    _useAreas - judge it against the Sites' protected areas too (hostile
        munitions) <BOOLEAN, default true>

Returns:
    [] if no threat, else [threatened vehicle <OBJECT>, predicted miss
    distance m <NUMBER>, threat radius m <NUMBER>, "guided" | "heading" |
    "seeker" | "ballistic", and for "seeker" the degrees it is off the
    missile's line of flight <NUMBER>], or for a protected area [Site
    <OBJECT>, distance from its centre m <NUMBER>, its radius m <NUMBER>,
    "area", "guided" | "heading" | "ballistic", and for "guided" what it's
    guided at <OBJECT>]

Examples:
    [_shell, "artilleryShell", _radar, 0] call aegism_detect_fnc_munitionThreat;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_GRAVITY 9.80665

params ["_projectile", "_class", "_poolOwner", ["_radiusSetting", 0], ["_flags", createHashMap], ["_useAreas", true]];

// A Site linked to others protects the whole group (aegism_network_fnc_
// linkSites).
private _network = _poolOwner getVariable ["AEGISM_network", objNull];
private _protected = if (isNull _network) then { [_poolOwner] } else {
    (_network getVariable ["AEGISM_groupMembers", _network getVariable ["AEGISM_networkMembers", []]]) select { !isNull _x && {alive _x} }
};
// Protected areas: a circle round each Site module of the group, of the
// Site's Protected Area Radius (the Shared Site Coordinator's, when there is
// one: aegism_fnc_siteSettingsSource) -- [Site, centre ASL, radius].
private _areas = [];
if (_useAreas && {!isNull _network}) then {
    {
        if (!isNull _x) then {
            private _areaRadius = (([_x] call aegism_fnc_siteSettingsSource) getVariable ["AEGISM_engagement", createHashMap]) getOrDefault ["protectRadius", 750];
            if (_areaRadius > 0) then { _areas pushBack [_x, getPosASL _x, _areaRadius]; };
        };
    } forEach (_network getVariable ["AEGISM_linkSites", [_network]]);
};
if (_protected isEqualTo [] && {_areas isEqualTo []}) exitWith { [] };
// The first protected area a ground point (ASL) is inside: [Site, distance
// from its centre, radius], or [].
private _fnInArea = {
    private _point = _this;
    private _index = _areas findIf { (_point distance2D (_x select 1)) <= (_x select 2) };
    if (_index < 0) exitWith { [] };
    (_areas select _index) params ["_site", "_centre", "_areaRadius"];
    [_site, _point distance2D _centre, _areaRadius]
};

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
// Guided at anything inside a protected area -- an ammo truck, a building.
private _guidedArea = if (isNull _missileTarget) then { [] } else { (getPosASL _missileTarget) call _fnInArea };
if (_guidedArea isNotEqualTo []) exitWith { _guidedArea + ["area", "guided", _missileTarget] };

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
    // Or flying into a protected area: where its line of flight, descending,
    // comes down to the area's own height.
    if (_best isEqualTo [] && {_vz < 0}) then {
        {
            _x params ["_site", "_centre", "_areaRadius"];
            private _t = ((_pos select 2) - (_centre select 2)) / -_vz;
            if (_t > 0) then {
                private _ground = _pos vectorAdd (_velocity vectorMultiply _t);
                private _distance = _ground distance2D _centre;
                if (_distance <= _areaRadius && {_best isEqualTo []}) then { _best = [_site, _distance, _areaRadius, "area", "heading"]; };
            };
        } forEach _areas;
    };
};
// A guided missile whose target can't be read (ACE's own guidance, a laser
// spot, a position) and isn't flying straight at one: a protected vehicle
// inside its seeker's view -- within its seeker cone of its line of flight
// (aegism_detect_fnc_seekerCone), closing -- could be what it's homing on.
// A guided missile on its way in steers, so its line of flight passes within
// a blast radius of its target only at the very end: a Scalpel seen at 2.2km
// was judged no threat until 51m from a Site vehicle.
//
// And only while it's converging on that vehicle: a missile homing on it
// turns toward it, so its angle off closes check by check; one flying past
// opens. Judged against the same vehicle's angle at this protector's last
// check (flags "seekerOff": [[protector, vehicle, angle], ...]), so the
// first sighting waits one tracker check (0.5s). Without it a Missile_AGM_02_F
// with a radar 22 deg off its flight, flying past it, cost a RAM.
private _cone = if (_class == "missile") then { [typeOf _projectile] call aegism_detect_fnc_seekerCone } else { -1 };
if (_cone >= 0 && {_best isEqualTo []} && {isNull _missileTarget}) then {
    private _speed = vectorMagnitude _velocity;
    if (_speed > 0) then {
        private _bestOff = 1e10;
        private _candidate = [];
        {
            private _toVehicle = (getPosASL _x) vectorDiff _pos;
            private _distance = vectorMagnitude _toVehicle;
            if (_distance > 0) then {
                private _off = acos ((((_toVehicle vectorDotProduct _velocity) / (_distance * _speed)) max -1) min 1);
                if (_off <= _cone && {_off < 90} && {_off < _bestOff}) then {
                    _bestOff = _off;
                    _candidate = [_x, _distance * sin _off, _radius, "seeker", _off];
                };
            };
        } forEach _protected;

        private _protector = [_network, _poolOwner] select (isNull _network);
        private _history = _flags getOrDefault ["seekerOff", []];
        private _index = _history findIf { (_x select 0) == _protector };
        private _last = if (_index < 0) then { [] } else { _history select _index };
        if (_candidate isNotEqualTo []) then {
            if (_last isNotEqualTo [] && {(_last select 1) == (_candidate select 0)} && {_bestOff <= (_last select 2)}) then { _best = _candidate; };
            if (_index < 0) then { _history pushBack [_protector, _candidate select 0, _bestOff]; } else { _history set [_index, [_protector, _candidate select 0, _bestOff]]; };
        } else {
            if (_index >= 0) then { _history deleteAt _index; };
        };
        _flags set ["seekerOff", _history];
    };
};
// A guided missile homing on something else, and not flying at the Site: no
// threat. An unguided one (a rocket built as a missile that can't steer)
// falls like a rocket, below.
if (_class == "missile" && {_cone >= 0}) exitWith { _best };

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

// Or predicted to land inside a protected area, the same fall down to the
// area's own height.
if (_best isEqualTo []) then {
    {
        _x params ["_site", "_centre", "_areaRadius"];
        private _disc = _vz * _vz + 2 * AEGISM_GRAVITY * ((_pos select 2) - (_centre select 2));
        if (_disc >= 0 && {_best isEqualTo []}) then {
            private _t = (_vz + sqrt _disc) / AEGISM_GRAVITY;
            if (_t > 0) then {
                private _distance = [(_pos select 0) + _vx * _t, (_pos select 1) + _vy * _t] distance2D _centre;
                if (_distance <= _areaRadius) then { _best = [_site, _distance, _areaRadius, "area", "ballistic"]; };
            };
        };
    } forEach _areas;
};

_best
