/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileProfileAt

Description:
    One reading off a missile's simulated flight (aegism_intercept_fnc_
    missileProfile), interpolated between its steps:

        "distance" - metres it has flown _value s after launch
        "time" - seconds it takes to fly _value metres
        "speed" - m/s it's going _value s after launch

    Past the end of its simulated life it carries on at its last speed: a
    caller that cares compares the time with the missile's lifetime itself
    (the lead solver's feasibility, aegism_intercept_fnc_missileFlightTime).

Parameters:
    _profile - [step, distances, speeds] from aegism_intercept_fnc_
        missileProfile <ARRAY>
    _query - "distance", "time" or "speed" <STRING>
    _value - seconds; metres for "time" <NUMBER>

Returns:
    <NUMBER>, -1 for an empty profile (no speed in config)

Examples:
    [_profile, "time", 4400] call aegism_intercept_fnc_missileProfileAt;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_profile", "_query", "_value"];

if (_profile isEqualTo []) exitWith { -1 };
_profile params ["_step", "_distances", "_speeds"];
private _last = (count _distances) - 1;

if (_query == "time") exitWith {
    private _far = _distances select _last;
    switch (true) do {
        case (_value <= 0): { 0 };
        case (_value >= _far): { _last * _step + (_value - _far) / ((_speeds select _last) max 1) };
        default {
            // The steps either side of it (the distances only rise).
            private _lo = 0;
            private _hi = _last;
            while {_hi - _lo > 1} do {
                private _mid = floor ((_lo + _hi) / 2);
                if ((_distances select _mid) < _value) then { _lo = _mid; } else { _hi = _mid; };
            };
            private _from = _distances select _lo;
            private _span = (_distances select _hi) - _from;
            if (_span > 0) then { (_lo + (_value - _from) / _span) * _step } else { _hi * _step }
        };
    }
};

private _i = (_value max 0) / _step;
private _table = [_distances, _speeds] select (_query == "speed");
if (_i >= _last) exitWith {
    if (_query == "speed") then {
        _speeds select _last
    } else {
        (_distances select _last) + (_value - _last * _step) * (_speeds select _last)
    }
};
private _lo = floor _i;
private _from = _table select _lo;
_from + ((_table select (_lo + 1)) - _from) * (_i - _lo)
