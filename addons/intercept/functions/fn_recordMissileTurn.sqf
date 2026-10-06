/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_recordMissileTurn

Description:
    One AEGIS-M missile's flight, measured (aegism_intercept_fnc_
    interceptorPFH), folded into its missile's turn rate: the fastest
    sustained turn seen on a flight that had to turn -- launched more than
    AEGISM_LAUNCH_ON_BORE degrees off the intercept, so it turned as hard as
    it could. A flight launched straight at the intercept only makes small
    corrections, which say little about how hard it can turn; it's counted
    but doesn't set the rate. The rate only ever rises: each turning flight's
    fastest turn is something the missile did.

    Safeguards (calibration.hpp), since one bad flight would otherwise set
    it for the rest of the mission: a flight whose seeker changed target
    isn't used (its turns weren't all toward one intercept), nor a turn
    faster than AEGISM_TURN_RATE_MAX (a tumble or a glitch); and once two
    turning flights are in, the rate is the second fastest -- no single
    flight sets it beyond what another has confirmed.

    A missile the game guides has no turn rate in config (maneuvrability has
    no unit), so this is where aegism_intercept_fnc_missileAgility gets it.
    For an ACE-guided missile it's a check on ACE's own configured rate.

    Logged per flight (MISSILE-TURN), with the predicted flight time against
    the real one.

Parameters:
    _ammoClass - the missile's CfgAmmo class <STRING>
    _launch - its launch plan [off-bore deg, predicted flight s, fired at,
        ...] <ARRAY>
    _peakRate - fastest sustained turn this flight, deg/s <NUMBER>
    _flightTime - seconds from launch to intercept; -1 if AEGIS-M's fuse
        didn't see one <NUMBER>
    _retargeted - optional, its seeker changed target in flight <BOOLEAN>

Returns:
    Nothing

Examples:
    ["ammo_Missile_mim145", [35, 9.2, 120.5], 24.1, 9.6] call aegism_intercept_fnc_recordMissileTurn;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"
#include "..\calibration.hpp"

// aegism_intercept_fnc_launchSolution's own on-bore tolerance.
#define AEGISM_LAUNCH_ON_BORE 2

params ["_ammoClass", "_launch", "_peakRate", "_flightTime", ["_retargeted", false]];
_launch params [["_offBore", 0], ["_predictedFlight", -1]];

private _table = missionNamespace getVariable "AEGISM_missileTurn";
if (isNil "_table") then {
    _table = createHashMap;
    missionNamespace setVariable ["AEGISM_missileTurn", _table];
};
// [flights, turning flights used, rate, the two fastest turning flights' peaks]
(_table getOrDefault [_ammoClass, [0, 0, 0, []]]) params ["_flights", "_turnedFlights", "_rate", ["_peaks", []]];
private _turned = _offBore > AEGISM_LAUNCH_ON_BORE;
private _rejected = switch (true) do {
    case (!_turned): { "" };
    case (_retargeted): { "its seeker changed target in flight" };
    case (_peakRate > AEGISM_TURN_RATE_MAX): { format ["faster than %1 deg/s: a tumble or a glitch", AEGISM_TURN_RATE_MAX] };
    default { "" };
};
_flights = _flights + 1;
if (_turned && {_rejected == ""}) then {
    _turnedFlights = _turnedFlights + 1;
    _peaks pushBack _peakRate;
    _peaks sort false;
    _peaks resize ((count _peaks) min 2);
    _rate = _peaks select -1;
};
_table set [_ammoClass, [_flights, _turnedFlights, _rate, _peaks]];

if (AEGISM_RPT_VERBOSE) then {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MISSILE-TURN: %1 launched %2 deg off the intercept -- fastest sustained turn %3 deg/s; %4. %5",
        _ammoClass, round (_offBore * 10) / 10, round (_peakRate * 10) / 10,
        if (_flightTime >= 0) then {
            format ["intercepted after %1s (predicted %2s)", round (_flightTime * 10) / 10, round (_predictedFlight * 10) / 10]
        } else {
            "no intercept by AEGIS-M's fuse (it missed, or the game's own proximity fuse or the target's end came first)"
        },
        switch (true) do {
            case (_rejected != ""): { format ["Not used for its turn rate: %1. Turn rate %2 deg/s, from %3 turning flight(s) of %4.", _rejected, round (_rate * 10) / 10, _turnedFlights, _flights] };
            case (_turnedFlights > 0): {
                format ["Turn rate now %1 deg/s (%2), from %3 turning flight(s) of %4.", round (_rate * 10) / 10,
                    ["its one turning flight so far", "the second fastest, confirmed by a faster one"] select (count _peaks > 1), _turnedFlights, _flights]
            };
            default { format ["Launched straight, so it doesn't set the turn rate (%1 flight(s), none turning yet).", _flights] };
        }];
};
