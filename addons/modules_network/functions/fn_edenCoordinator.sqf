/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_edenCoordinator

Description:
    Eden: keeps "Shared Site Coordinator" to one Site per group of connected
    Sites -- Site modules synced to each other, or synced to the same
    vehicle (directly or through its crew), chained. Run on every Eden
    attribute change and every new connection (Cfg3DEN EventHandlers, this
    addon's config).

    The Site just ticked wins: each Site's last-seen value is remembered for
    the editing session ("AEGISM_edenCoordinatorSeen"), so a Site ticked
    since the last run keeps it and the others in its group are unticked
    (set3DENAttribute -- undoable like any edit). Where a new connection
    joins two groups that each had one, the first Site keeps it.

    The same rule is applied in Zeus (aegism_network_fnc_zeusApplySite); a
    group that still ends up with two (a link made in Zeus) is led by the
    first set up (aegism_network_fnc_linkSites).

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
    // What each Site is synced to: other Sites, and vehicles (a crewman
    // stands for his vehicle).
    private _syncedOf = _sites apply {
        ((get3DENConnections _x) select { (_x select 0) == "Sync" }) apply { vehicle (_x select 1) }
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
                        private _shared = (_syncedA arrayIntersect _syncedB) select { _x isKindOf "AllVehicles" && {!(_x isKindOf "CAManBase")} };
                        if (_shared isNotEqualTo [] || {(_sites select _b) in _syncedA} || {(_sites select _a) in _syncedB}) then {
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
