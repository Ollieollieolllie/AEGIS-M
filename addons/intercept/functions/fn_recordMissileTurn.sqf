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

    A missile the game guides has no turn rate in config (maneuvrability has
    no unit), so this is where aegism_intercept_fnc_missileAgility gets it.
    For an ACE-guided missile it's a check on ACE's own configured rate.

    Logged per flight (MISSILE-TURN), with the predicted flight time against
    the real one.

Parameters:
    _ammoClass - the missile's CfgAmmo class <STRING>
    _launch - its launch plan [off-bore deg, predicted flight s, fired at]
        <ARRAY>
    _peakRate - fastest sustained turn this flight, deg/s <NUMBER>
    _flightTime - seconds from launch to intercept; -1 if AEGIS-M's fuse
        didn't see one <NUMBER>

Returns:
    Nothing

Examples:
    ["ammo_Missile_mim145", [35, 9.2, 120.5], 24.1, 9.6] call aegism_intercept_fnc_recordMissileTurn;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// aegism_intercept_fnc_launchSolution's own on-bore tolerance.
#define AEGISM_LAUNCH_ON_BORE 2

params ["_ammoClass", "_launch", "_peakRate", "_flightTime"];
_launch params [["_offBore", 0], ["_predictedFlight", -1]];

private _table = missionNamespace getVariable "AEGISM_missileTurn";
if (isNil "_table") then {
    _table = createHashMap;
    missionNamespace setVariable ["AEGISM_missileTurn", _table];
};
(_table getOrDefault [_ammoClass, [0, 0, 0]]) params ["_flights", "_turnedFlights", "_rate"];
private _turned = _offBore > AEGISM_LAUNCH_ON_BORE;
_flights = _flights + 1;
if (_turned) then {
    _turnedFlights = _turnedFlights + 1;
    _rate = _rate max _peakRate;
};
_table set [_ammoClass, [_flights, _turnedFlights, _rate]];

diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " MISSILE-TURN: %1 launched %2 deg off the intercept -- fastest sustained turn %3 deg/s; %4. %5",
    _ammoClass, round (_offBore * 10) / 10, round (_peakRate * 10) / 10,
    if (_flightTime >= 0) then {
        format ["intercepted after %1s (predicted %2s)", round (_flightTime * 10) / 10, round (_predictedFlight * 10) / 10]
    } else {
        "no intercept by AEGIS-M's fuse (it missed, or the game's own proximity fuse or the target's end came first)"
    },
    if (_turnedFlights > 0) then {
        format ["Turn rate now %1 deg/s, from %2 turning flight(s) of %3.", round (_rate * 10) / 10, _turnedFlights, _flights]
    } else {
        format ["Launched straight, so it doesn't set the turn rate (%1 flight(s), none turning yet).", _flights]
    }];
