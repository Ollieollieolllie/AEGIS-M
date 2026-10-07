/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_radarRelay

Description:
    The relay scan: while their Site is quiet, its turning radars searching
    in bursts work as one radar whose beam is handed from vehicle to
    vehicle.
    Full notes: docs/functions/modules_system.md

Parameters:
    _vehicle - the radar vehicle <OBJECT>

Returns:
    [bearing it's lit on now (-1: not lit), bearing to point at (-1: nothing
    for it yet -- hold), detail for the overlays], or [] if it isn't in a
    relay (no turning radar) <ARRAY>

Examples:
    ([_radarTruck] call aegism_system_fnc_radarRelay) params ["_lit", "_aim", "_detail"];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Each arc of a lap is this share of the narrowest radar's arc, at most.
#define AEGISM_RELAY_ARC_SHARE 0.9

params ["_vehicle"];

if ((_vehicle call aegism_system_fnc_turningRadar) isEqualTo []) exitWith { [] };

private _network = _vehicle getVariable ["AEGISM_network", objNull];
private _members = if (isNull _network) then { [_vehicle] } else {
    (_network getVariable ["AEGISM_groupMembers", _network getVariable ["AEGISM_networkMembers", []]]) select { !isNull _x && {alive _x} }
};
private _holder = if (isNull _network) then { _vehicle } else { _network getVariable ["AEGISM_linkLead", _network] };

// The radars in the relay, in a fixed order (netId): turning radars in a
// bursting mode that are quiet now -- this one, and any other whose last
// state was a burst or a pause.
private _relay = (_members select {
    ((_x getVariable ["AEGISM_resolvedEngagementSettings", createHashMap]) getOrDefault ["emcon", "auto"]) in ["intermittent", "auto"]
        && {(_x call aegism_system_fnc_turningRadar) isNotEqualTo []}
        && {count (_x getVariable ["AEGISM_armInbound", createHashMap]) == 0}
        && {_x == _vehicle || {((_x getVariable ["AEGISM_emcon", createHashMap]) getOrDefault ["reason", ""]) in ["", "burst", "pause"]}}
}) apply { [netId _x, _x] };
_relay sort true;
_relay = _relay apply { _x select 1 };
_relay pushBackUnique _vehicle;

private _settings = _vehicle getVariable ["AEGISM_resolvedEngagementSettings", createHashMap];
private _on = (_settings getOrDefault ["emconBurstOn", 5]) max 1;
private _off = (_settings getOrDefault ["emconBurstOff", 15]) max 0;
private _narrowest = selectMin (_relay apply { (_x call aegism_system_fnc_turningRadar) select 2 });
private _arcs = ceil (360 / ((AEGISM_RELAY_ARC_SHARE * _narrowest) max 1));
private _arcStep = 360 / _arcs;
private _cycle = _arcs * _on + _off;
private _lap = floor (CBA_missionTime / _cycle);
private _phase = CBA_missionTime - _lap * _cycle;
// The step lit now (-1 in the pause after a lap), and the one after it.
private _step = if (_phase < _arcs * _on) then { floor (_phase / _on) } else { -1 };
private _next = if (_step >= 0 && {_step < _arcs - 1}) then { [_lap, _step + 1] } else { [_lap + 1, 0] };

private _plan = _holder getVariable "AEGISM_radarRelay";
if (isNil "_plan") then { _plan = createHashMap; _holder setVariable ["AEGISM_radarRelay", _plan, false]; };
{ if ((_x select 0) < _lap - 1) then { _plan deleteAt _x; }; } forEach (keys _plan);

// The radar for a step: kept if already picked and still in the relay;
// otherwise the one that can swing onto its arc soonest, not _avoid (the
// one lit before it) unless it's the only one.
private _fnPick = {
    params ["_key", "_avoid"];
    private _picked = _plan getOrDefault [_key, ""];
    if (_picked != "" && {(_relay findIf { netId _x == _picked }) != -1}) exitWith { _picked };
    private _bearing = (_key select 1) * _arcStep;
    private _best = [];
    {
        if (netId _x != _avoid || {count _relay == 1}) then {
            private _sensor = _x call aegism_system_fnc_turningRadar;
            private _rate = (([_x, _sensor select 3] call aegism_intercept_fnc_turretConfig) select 6) max 1;
            private _pointing = (_x getVariable ["AEGISM_radarBeam", createHashMap]) getOrDefault ["bearing", getDir _x];
            private _slew = (abs (((_pointing - _bearing + 540) mod 360) - 180)) / _rate;
            if (_best isEqualTo [] || {_slew < (_best select 0)}) then { _best = [_slew, netId _x]; };
        };
    } forEach _relay;
    _picked = _best param [1, ""];
    _plan set [_key, _picked];
    _picked
};
private _litId = if (_step >= 0) then { [[_lap, _step], ""] call _fnPick } else { "" };
private _nextId = [_next, _litId] call _fnPick;

private _myId = netId _vehicle;
private _lit = if (_step >= 0 && {_litId == _myId}) then { _step * _arcStep } else { -1 };
private _aim = switch (true) do {
    case (_lit >= 0): { _lit };
    case (_nextId == _myId): { (_next select 1) * _arcStep };
    default { -1 };
};
private _detail = switch (true) do {
    case (_lit >= 0): {
        format ["relay search: lit on the %1-degree arc, %2 of %3; silent in %4s", round _lit, _step + 1, _arcs, ceil ((_step + 1) * _on - _phase)]
    };
    case (_aim >= 0): {
        format ["relay search: next on the %1-degree arc, in %2s", round _aim,
            ceil ((if ((_next select 0) == _lap) then { (_next select 1) * _on } else { _cycle }) - _phase)]
    };
    default { format ["relay search: %1 turning radar(s) taking turns, one lit at a time", count _relay] };
};
[_lit, _aim, _detail]
