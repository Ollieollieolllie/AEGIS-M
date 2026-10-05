/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_emconUpdate

Description:
    Emission control for one radar vehicle, once a second on the server
    (aegism_system_fnc_moduleInit's detection loop, before its sensors are
    read): whether its active radar emits, from its Radar Emission setting
    ("emcon": the Site's, or the vehicle's own override). An active radar
    only sees while it emits, aircraft and munitions alike; while it emits,
    enemy radar-warning receivers and anti-radiation missiles can find it.
    Set with setVehicleRadar (0 the AI decides, 1 on, 2 off), only when what
    it wants changes.

        ai - the AI decides, as without AEGIS-M. A radar AEGIS-M had set is
            handed back once; one it never set isn't touched.
        on - always emitting.
        cued - silent until a threat it covers turns up (aegism_system_fnc_
            radarCovers): any contact in its Site's picture -- its whole
            linked group's (aegism_network_fnc_linkSites) -- found by
            another sensor: heard by passive radar, seen by IR or visual
            sensors, by datalink where that's allowed (aegism_detect_fnc_
            confidenceLoop), or by another radar. It stays lit while any
            contact is in its coverage, while a launcher's missiles are in
            flight at a target it covers (fire control: the Site's track
            must not drop while they guide), and for emconHold s after the
            last, then goes silent.
        intermittent - as cued, but searching meanwhile: emconBurstOn s on
            every emconBurstOn + emconBurstOff s. The intermittent radars
            of a linked group take turns, their bursts spread evenly over
            the cycle (three radars at 5 s on, 15 s off: one on every 6.7 s,
            silent gaps of 1.7 s between them).

    Anti-radiation missiles, in every mode (armShutdown on, the default): a
    radar an inbound one is homing on, or has in its seeker's view, shuts
    down whether or not that saves it (aegism_detect_fnc_armInbound marks
    it), until the missile is gone or past when it would have arrived. Its
    Site's other radars that cover the missile are cued by it, to keep the
    track (in cued and intermittent modes).

    A narrow radar on a turret with no AEGIS-M weapon on it (the vanilla
    radar truck's 120 degrees) is pointed by AEGIS-M while lit (aegism_
    intercept_fnc_lockTurret): at its most urgent contact -- a target its
    Site's missiles are flying at, then one under engagement, then soonest
    impact, then nearest -- or, with nothing to look at, sweeping round in
    steps of three quarters of its arc every AEGISM_SWEEP_DWELL s. Handed
    back to its crew while silent.

    Records on the vehicle ("AEGISM_emcon", for the debug overlays, aegism_
    fnc_emconText): mode, applied (the last setVehicleRadar value, -1
    none), desired, reason ("ai", "on", "arm", "guiding", "cued",
    "holding", "burst", "pause", "silent"), detail, since.

    Logged: EMCON (its mode; going silent, or back to searching), CUE (lit
    by a contact, with what found it), ARM-SHUTDOWN (shut down, and back).

Parameters:
    _vehicle - the radar vehicle <OBJECT>

Returns:
    Nothing

Examples:
    [_radarTruck] call aegism_system_fnc_emconUpdate;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_SWEEP_DWELL 2
// How far out the point a radar turret is aimed at lies, metres.
#define AEGISM_LOOK_DISTANCE 2000

params ["_vehicle"];

if (isNull _vehicle || {!alive _vehicle}) exitWith {};
private _system = _vehicle getVariable "AEGISM_system";
if (isNil "_system" || {!(_system getOrDefault ["hasRadar", false])}) exitWith {};

private _settings = _vehicle getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_settings") then { _settings = [_vehicle] call aegism_system_fnc_resolveEngagementSettings; };
private _mode = _settings getOrDefault ["emcon", "ai"];
private _hold = _settings getOrDefault ["emconHold", 10];
private _burstOn = (_settings getOrDefault ["emconBurstOn", 5]) max 1;
private _burstOff = (_settings getOrDefault ["emconBurstOff", 15]) max 0;
private _armShutdown = _settings getOrDefault ["armShutdown", true];

private _state = _vehicle getVariable "AEGISM_emcon";
if (isNil "_state") then {
    _state = createHashMapFromArray [
        ["mode", ""], ["applied", -1], ["desired", 0], ["reason", ""], ["detail", ""], ["since", time],
        ["litUntil", -1], ["turret", []], ["sweepAt", -1], ["sweepBearing", random 360]
    ];
    _vehicle setVariable ["AEGISM_emcon", _state, false];
};

private _fnName = {
    private _name = getText (configOf _this >> "displayName");
    if (_name == "") then { typeOf _this } else { _name }
};
private _fnRange = {
    if (_this >= 1000) then { format ["%1km", (round (_this / 100)) / 10] } else { format ["%1m", round _this] }
};
private _fnCovers = { ([_vehicle, getPosASL _this] call aegism_system_fnc_radarCovers) select 0 };

if ((_state get "mode") != _mode) then {
    _state set ["mode", _mode];
    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " EMCON: %1 radar emission: %2%3", _vehicle,
        switch (_mode) do {
            case "on": { "Always on" };
            case "cued": { format ["Silent until cued -- lights up for a contact in its coverage another sensor finds, stays lit %1s after the last", _hold] };
            case "intermittent": { format ["Intermittent -- searches %1s on, %2s off; lit while a contact is in its coverage, and %3s after the last", _burstOn, _burstOff, _hold] };
            default { "AI decides" };
        },
        ["", " -- shuts down for an anti-radiation missile inbound on it"] select _armShutdown];
};

// --- Anti-radiation missiles inbound on it (aegism_detect_fnc_armInbound) ---
private _marks = _vehicle getVariable ["AEGISM_armInbound", createHashMap];
private _armEnded = "";
{
    (_marks get _x) params ["_missile", "", "_until"];
    if (isNull _missile || {!alive _missile}) then {
        _marks deleteAt _x;
        _armEnded = "the anti-radiation missile is gone";
    } else {
        if (time > _until) then {
            _marks deleteAt _x;
            if (_armEnded == "") then { _armEnded = "the anti-radiation missile is overdue (past when it would have arrived)"; };
        };
    };
} forEach (keys _marks);
// The nearest: [missile, ammo class, until, why, sensor kinds, seen by].
private _arm = [];
if (_armShutdown) then {
    private _nearest = 1e10;
    {
        private _distance = _vehicle distance (_y select 0);
        if (_distance < _nearest) then { _nearest = _distance; _arm = _y; };
    } forEach _marks;
};

private _network = _vehicle getVariable ["AEGISM_network", objNull];
private _members = if (isNull _network) then { [_vehicle] } else {
    (_network getVariable ["AEGISM_groupMembers", _network getVariable ["AEGISM_networkMembers", []]]) select { !isNull _x && {alive _x} }
};
private _claims = if (isNull _network) then { createHashMap } else { _network getVariable ["AEGISM_claims", createHashMap] };

// --- What it covers: targets missiles are flying at, contacts, and anti-
// radiation missiles inbound on its Site's other radars ---
private _guided = [];   // [target, launcher]
private _covered = [];  // [contact key, pool entry]
private _armCues = [];  // missiles
if (_arm isEqualTo [] && {_mode in ["on", "cued", "intermittent"]}) then {
    if (isNull _network) then {
        // Standalone: its own launchers' missiles in flight.
        {
            {
                _x params ["_target", "_interceptors"];
                if (!isNull _target && {alive _target} && {(_interceptors findIf { !isNull _x && {alive _x} }) != -1} && {_target call _fnCovers}) then {
                    _guided pushBack [_target, _vehicle];
                };
            } forEach (_y getOrDefault ["inFlight_launcher", []]);
        } forEach (_vehicle getVariable ["AEGISM_turrets", createHashMap]);
    } else {
        {
            {
                private _target = _x getOrDefault ["target", objNull];
                if ((_x get "role") == "launcher" && {!isNull _target} && {alive _target}
                    && {((_x getOrDefault ["interceptors", []]) findIf { !isNull _x && {alive _x} }) != -1} && {_target call _fnCovers}) then {
                    _guided pushBack [_target, _x get "system"];
                };
            } forEach _y;
        } forEach _claims;
    };
    {
        private _object = _y getOrDefault ["object", objNull];
        if (!isNull _object && {alive _object} && {_object call _fnCovers}) then { _covered pushBack [_x, _y]; };
    } forEach (([_network, _vehicle] select (isNull _network)) getVariable ["AEGISM_pooledContacts", createHashMap]);
    {
        if (_x != _vehicle) then {
            {
                private _missile = _y select 0;
                if (!isNull _missile && {alive _missile} && {_missile call _fnCovers}) then { _armCues pushBackUnique _missile; };
            } forEach (_x getVariable ["AEGISM_armInbound", createHashMap]);
        };
    } forEach _members;
};

// --- Emit or not ---
// Intermittent radars of its linked group search in turn, their bursts
// spread evenly over the cycle: random phases left stretches where every
// radar was silent at once, and munitions released then went unseen.
private _period = _burstOn + _burstOff;
private _searchers = _members select {
    ((_x getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasRadar", false])
        && {((_x getVariable ["AEGISM_resolvedEngagementSettings", createHashMap]) getOrDefault ["emcon", "ai"]) == "intermittent"}
};
private _slot = (_searchers find _vehicle) max 0;
private _phaseTime = (time + _period * _slot / ((count _searchers) max 1)) mod _period;
([] call {
    if (_arm isNotEqualTo []) exitWith { [2, "arm"] };
    if (_mode == "on") exitWith { [1, "on"] };
    if !(_mode in ["cued", "intermittent"]) exitWith { [0, "ai"] };
    if (_guided isNotEqualTo []) exitWith { [1, "guiding"] };
    if (_covered isNotEqualTo [] || {_armCues isNotEqualTo []}) exitWith { [1, "cued"] };
    if (time < (_state get "litUntil")) exitWith { [1, "holding"] };
    if (_mode == "cued") exitWith { [2, "silent"] };
    if (_phaseTime < _burstOn) exitWith { [1, "burst"] };
    [2, "pause"]
}) params ["_desired", "_reason"];
if (_reason in ["guiding", "cued"]) then { _state set ["litUntil", time + _hold]; };

// Its most urgent contact: a target missiles are flying at; then, of the
// contacts it covers, one under engagement, soonest impact, nearest; then an
// anti-radiation missile on another of its Site's radars.
private _focus = objNull;
private _focusEntry = createHashMap;
if (_guided isNotEqualTo []) then { _focus = (_guided select 0) select 0; };
if (isNull _focus && {_covered isNotEqualTo []}) then {
    private _eye = eyePos _vehicle;
    private _scored = [];
    {
        _x params ["_key", "_entry"];
        (_entry getOrDefault ["tti", [1e10, time]]) params ["_tti", "_ttiAt"];
        _scored pushBack [parseNumber !(_key in _claims), _tti - (time - _ttiAt), _eye distance (getPosASL (_entry get "object")), _forEachIndex];
    } forEach _covered;
    _scored sort true;
    _focusEntry = (_covered select ((_scored select 0) select 3)) select 1;
    _focus = _focusEntry get "object";
};
if (isNull _focus && {_armCues isNotEqualTo []}) then { _focus = _armCues select 0; };

private _detail = switch (_reason) do {
    case "arm": {
        _arm params ["_missile", "_ammo", "", "_why"];
        format ["anti-radiation missile inbound (%1, %2 out, %3)", _ammo, (_vehicle distance _missile) call _fnRange, _why]
    };
    case "on": { "always on" };
    case "guiding": {
        (_guided select 0) params ["_target", "_launcher"];
        format ["fire control: %1's missiles in flight at %2", _launcher call _fnName, _target call _fnName]
    };
    case "cued": {
        if (count _focusEntry > 0) then {
            private _tags = [_focusEntry getOrDefault ["sources", createHashMap]] call aegism_fnc_sensorTags;
            format ["%1 (%2, %3)%4%5", _focus call _fnName, _focusEntry get "class", (_vehicle distance _focus) call _fnRange,
                ["", format [" [%1]", _tags]] select (_tags != ""), ["", format [" +%1 more", count _covered - 1]] select (count _covered > 1)]
        } else {
            format ["an anti-radiation missile on another Site radar, %1 out", (_vehicle distance _focus) call _fnRange]
        }
    };
    case "holding": { format ["holding: %1 in %2s", ["silent", "back to searching"] select (_mode == "intermittent"), ceil ((_state get "litUntil") - time)] };
    case "burst": { format ["intermittent search: silent in %1s", ceil (_burstOn - _phaseTime)] };
    case "pause": { format ["intermittent: next search in %1s", ceil (_period - _phaseTime)] };
    case "silent": { "silent until cued" };
    default { "the AI decides" };
};

// --- Log what changed ---
private _previous = _state get "reason";
if (_reason != _previous) then {
    _state set ["since", time];
    if (_reason == "arm") then {
        _arm params ["_missile", "_ammo", "", "_why", "_sources", "_seenBy"];
        private _others = (_members - [_vehicle]) select { (_x getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasRadar", false] };
        private _emitting = _others select { isVehicleRadarOn _x };
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " ARM-SHUTDOWN: %1 shuts its radar down -- %2 (anti-radiation) inbound, %3 out, %4; seen by %5 (%6). %7",
            _vehicle, _ammo, round (_vehicle distance _missile), _why, _seenBy, _sources joinString ", ",
            switch (true) do {
                case (_others isEqualTo []): { "It's the Site's only radar: the Site has its other sensors until it's back." };
                case (_emitting isEqualTo []): { format ["Its Site's other radars (%1) are silent; those that cover the missile light up for it unless they're on AI decides or Always on.", _others] };
                default { format ["Still emitting on its Site: %1.", _emitting] };
            }];
    };
    if (_previous == "arm") then {
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " ARM-SHUTDOWN: %1 radar back -- %2; now %3.", _vehicle,
            [_armEnded, "Shut Down for Anti-Radiation Missiles was turned off"] select (_armEnded == ""), _detail];
    };
    if (_reason in ["cued", "guiding"] && {_previous in ["", "silent", "pause", "burst"]}) then {
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " CUE: %1 lit for %2 -- %3 (%4).", _vehicle, _focus,
            if (_reason == "guiding") then { _detail } else {
                if (count _focusEntry > 0) then {
                    private _seen = keys (_focusEntry getOrDefault ["sources", createHashMap]);
                    format ["%1 at %2m, found by %3", _focusEntry get "class", round (_vehicle distance _focus), ["its Site's picture", _seen joinString ", "] select (_seen isNotEqualTo [])]
                } else { format ["an anti-radiation missile inbound on another Site radar, %1m out", round (_vehicle distance _focus)] }
            },
            ["Silent until cued", "Intermittent"] select (_mode == "intermittent")];
    };
    if (_reason in ["silent", "pause", "burst"] && {_previous in ["cued", "guiding", "holding"]}) then {
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " EMCON: %1 %2 -- nothing in its coverage for %3s.", _vehicle,
            ["goes silent", "back to its intermittent search"] select (_mode == "intermittent"), _hold];
    };
    _state set ["reason", _reason];
};

// --- Apply ---
private _applied = _state get "applied";
if (_desired != _applied && {_desired != 0 || {_applied > 0}}) then {
    _vehicle setVehicleRadar _desired;
    _state set ["applied", _desired];
};
_state set ["desired", _desired];
_state set ["detail", _detail];

// --- Point a narrow radar on a turret no AEGIS-M weapon uses ---
private _weaponTurrets = ((_system getOrDefault ["launcherWeapons", []]) + (_system getOrDefault ["ciwsWeapons", []])) apply { _x select 0 };
private _pointable = (_system getOrDefault ["sensors", []]) select {
    (_x select 0) == "radar" && {(_x select 3) isNotEqualTo []} && {(_x select 2) < 360} && {!((_x select 3) in _weaponTurrets)}
};
if (_pointable isNotEqualTo []) then {
    (_pointable select 0) params ["", "", "_arc", "_turretPath", "", "", "", ["_verticalArc", 360]];
    private _aimAt = [];
    if (_desired == 1) then {
        if (!isNull _focus) then {
            _aimAt = getPosASL _focus;
        } else {
            // Sweeping: a bearing a little short of one arc on every dwell,
            // pitched up a quarter of its vertical arc (within its elevation
            // limits) so the beam covers the horizon and well above it.
            if (time >= (_state get "sweepAt")) then {
                _state set ["sweepAt", time + AEGISM_SWEEP_DWELL];
                _state set ["sweepBearing", ((_state get "sweepBearing") + _arc * 0.75) mod 360];
            };
            ([_vehicle, _turretPath] call aegism_intercept_fnc_turretConfig) params ["", "", "", "_minElev", "_maxElev"];
            private _bearing = _state get "sweepBearing";
            private _pitch = (((_verticalArc min 180) / 4) max _minElev) min _maxElev;
            _aimAt = (eyePos _vehicle) vectorAdd ([sin _bearing * cos _pitch, cos _bearing * cos _pitch, sin _pitch] vectorMultiply AEGISM_LOOK_DISTANCE);
        };
    };
    if (_aimAt isNotEqualTo []) then {
        [_vehicle, _turretPath, _aimAt] call aegism_intercept_fnc_lockTurret;
        _state set ["turret", _turretPath];
    } else {
        if ((_state get "turret") isNotEqualTo []) then {
            [_vehicle, _state get "turret", objNull] call aegism_intercept_fnc_lockTurret;
            _state set ["turret", []];
        };
    };
};
