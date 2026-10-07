/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_edenCoordinator

Description:
    Eden: keeps Shared Site Coordinator to one Site per group of connected
    Sites.
    Full notes: docs/functions/modules_network.md

Parameters:
    Whatever the Eden event passes (not used)

Returns:
    Nothing

Examples:
    [] call aegism_network_fnc_edenCoordinator;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

if (!is3DEN) exitWith {};

private _sites = (all3DENEntities select 3) select { _x isKindOf "AEGISM_Module_Site" };
private _seen = missionNamespace getVariable "AEGISM_edenCoordinatorSeen";
if (isNil "_seen") then {
    _seen = createHashMap;
    missionNamespace setVariable ["AEGISM_edenCoordinatorSeen", _seen];
};
private _fnTicked = { ((_this get3DENAttribute "sharedCoordinator") param [0, false]) isEqualTo true };

if (count _sites > 1) then {
    // What an entity is synced to, each as its vehicle (a crewman stands for
    // his vehicle).
    private _fnSynced = { ((get3DENConnections _this) select { (_x select 0) == "Sync" }) apply { vehicle (_x select 1) } };
    // What each Site is synced to (other Sites, and its vehicles), and what
    // its vehicles are synced to themselves (directly or by a crewman).
    private _syncedOf = _sites apply { _x call _fnSynced };
    private _vehicleSyncsOf = _syncedOf apply {
        private _siteSynced = _x;
        private _reach = [];
        {
            if (_x isKindOf "AllVehicles" && {!(_x isKindOf "CAManBase")}) then {
                _reach append (_x call _fnSynced);
                { _reach append (_x call _fnSynced); } forEach (crew _x);
            };
        } forEach _siteSynced;
        _reach
    };
    private _count = count _sites;
    private _groupOf = [];
    _groupOf resize _count;
    _groupOf = _groupOf apply { -1 };
    for "_i" from 0 to _count - 1 do {
        if ((_groupOf select _i) < 0) then {
            private _group = [_i];
            _groupOf set [_i, _i];
            private _queue = [_i];
            while { _queue isNotEqualTo [] } do {
                private _a = _queue deleteAt 0;
                for "_b" from 0 to _count - 1 do {
                    if ((_groupOf select _b) < 0) then {
                        private _syncedA = _syncedOf select _a;
                        private _syncedB = _syncedOf select _b;
                        private _vehiclesB = _syncedB select { _x isKindOf "AllVehicles" && {!(_x isKindOf "CAManBase")} };
                        private _shared = (_syncedA arrayIntersect _syncedB) select { _x isKindOf "AllVehicles" && {!(_x isKindOf "CAManBase")} };
                        // A vehicle of one synced to a vehicle of the other.
                        private _paired = ((_vehicleSyncsOf select _a) arrayIntersect _vehiclesB) isNotEqualTo [];
                        if (_shared isNotEqualTo [] || {_paired} || {(_sites select _b) in _syncedA} || {(_sites select _a) in _syncedB}) then {
                            _groupOf set [_b, _i];
                            _group pushBack _b;
                            _queue pushBack _b;
                        };
                    };
                };
            };

            // More than one ticked: the one ticked since the last run keeps
            // it, else the first.
            private _ticked = (_group apply { _sites select _x }) select { _x call _fnTicked };
            if (count _ticked > 1) then {
                private _new = _ticked select { !(_seen getOrDefault [get3DENEntityID _x, false]) };
                private _keep = [_ticked select 0, _new select 0] select (_new isNotEqualTo []);
                { if (_x != _keep) then { _x set3DENAttribute ["sharedCoordinator", false]; }; } forEach _ticked;
            };
        };
    };
};

{ _seen set [get3DENEntityID _x, _x call _fnTicked]; } forEach _sites;
