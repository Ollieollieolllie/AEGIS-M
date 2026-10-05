/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_armInbound

Description:
    An anti-radiation missile (aegism_detect_fnc_antiRadiation) seen by an
    AEGIS-M vehicle's own sensors: marks the radars it threatens among what
    that vehicle protects -- every live member of its Site and the Sites
    linked with it (aegism_network_fnc_linkSites), or itself if standalone
    -- so they shut down (Radar Emission, aegism_system_fnc_emconUpdate):

        - the radar it's homing on (missileTarget), if that's one of them;
        - otherwise each of them that's emitting inside its seeker's view:
          within its seeker's reach, and within half its seeker's arc of its
          line of flight.

    A friendly or neutral one only counts while homing on one of them.

    Each mark ("AEGISM_armInbound" on the radar: munition key -> [missile,
    ammo class, until, why, sensor kinds that saw it, who saw it]) lasts
    until the time the missile would take to reach that radar at its
    current speed (at least AEGISM_ARM_MIN_SPEED m/s), plus
    AEGISM_ARM_MARGIN s, and is renewed at every sighting; the radar comes
    back sooner if the missile is gone. A radar newly marked is shut down at
    once, not at its next once-a-second emission update.

    Called for every sighting by the munition tracker (aegism_detect_fnc_
    munitionCheck), whether or not the Site engages missiles: a Site that
    doesn't still protects its radars.

Parameters:
    _projectile - the missile <OBJECT>
    _key - its contact key (aegism_detect_fnc_trackMunition) <STRING>
    _poolOwner - the AEGIS-M vehicle that saw it <OBJECT>
    _sources - the sensor kinds that saw it <ARRAY of STRING>
    _hostile - fired by a side hostile to that vehicle's <BOOLEAN>

Returns:
    Nothing

Examples:
    [_harm, "m12", _radar, ["ir"], true] call aegism_detect_fnc_armInbound;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_ARM_MARGIN 5
#define AEGISM_ARM_MIN_SPEED 50

params ["_projectile", "_key", "_poolOwner", ["_sources", []], ["_hostile", true]];

private _seeker = [typeOf _projectile] call aegism_detect_fnc_antiRadiation;
if (_seeker isEqualTo []) exitWith {};
_seeker params ["_arc", "_reach"];

private _network = _poolOwner getVariable ["AEGISM_network", objNull];
private _protected = if (isNull _network) then { [_poolOwner] } else {
    _network getVariable ["AEGISM_groupMembers", _network getVariable ["AEGISM_networkMembers", []]]
};
private _radars = _protected select { !isNull _x && {alive _x} && {(_x getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasRadar", false]} };
if (_radars isEqualTo []) exitWith {};

private _position = getPosASL _projectile;
private _velocity = velocity _projectile;
private _homing = missileTarget _projectile;
private _targets = [];
private _why = "";
if (_homing in _radars) then {
    _targets = [_homing];
    _why = "homing on it";
} else {
    if (_hostile && {(vectorMagnitude _velocity) > 0}) then {
        private _heading = (_velocity select 0) atan2 (_velocity select 1);
        _targets = _radars select {
            isVehicleRadarOn _x && {(_position distance _x) <= _reach}
                && {(abs ((((_position getDir _x) - _heading) + 540) mod 360 - 180)) <= _arc / 2}
        };
        _why = "it's emitting in the missile's seeker view";
    };
};

private _speed = (vectorMagnitude _velocity) max AEGISM_ARM_MIN_SPEED;
{
    private _radar = _x;
    private _marks = _radar getVariable "AEGISM_armInbound";
    if (isNil "_marks") then {
        _marks = createHashMap;
        _radar setVariable ["AEGISM_armInbound", _marks, false];
    };
    private _isNew = !(_key in _marks);
    private _until = time + (_position distance _radar) / _speed + AEGISM_ARM_MARGIN;
    _marks set [_key, [_projectile, typeOf _projectile, _until max ((_marks getOrDefault [_key, []]) param [2, 0]), _why, _sources, _poolOwner]];
    if (_isNew) then { [_radar] call aegism_system_fnc_emconUpdate; };
} forEach _targets;
