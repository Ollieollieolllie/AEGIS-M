/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_linkSites

Description:
    Links Sites into one, and splits them again once every link between
    them is gone. Two Sites are linked by any of these, as many as there are:
        shared - a live AEGIS-M System synced to both (e.g. a radar both
            connect to)
        pair - a live System of one synced to a live System of the other
            (a vehicle-to-vehicle sync line; to a crewman counts as to his
            vehicle) -- held while both are alive
        modules - the two Site modules synced to each other
    Links chain: A linked to B and B to C make one group of three. Losing one
    of several links keeps the group (logged, LINK-CHANGE); losing the last
    splits it (UNLINK).

    A linked group works as one Site:
        - one contact pool and one assignment ledger: every Site in it holds
          the same "AEGISM_pooledContacts" and "AEGISM_claims" HashMaps, so
          each Site's sensors feed the group and each Site's vehicles see
          the group's assignments
        - one coordinator, its lead: the Site ticked "Shared Site
          Coordinator", or, if none is, the first of them set up. It assigns
          every target across all the group's vehicles ("AEGISM_
          groupMembers", aegism_intercept_fnc_assignEngagements), so two of
          its weapons are never put on one target unless that's the plan (a
          CIWS alongside a launcher). The other Sites' coordinators stand by.
          Its Target Priority orders the group's targets.
        - settings: with a Shared Site Coordinator, its settings apply to
          every vehicle of the group (aegism_fnc_siteSettingsSource); without
          one, each vehicle keeps its own Site's. Every vehicle of a group
          that changes is re-resolved at once.
        - it protects all its vehicles: a munition threatening any of them
          is a threat to the group (aegism_detect_fnc_munitionThreat), and
          its Sites' alarms sound together (incoming, going live).
    More than one Site of a group ticked as coordinator (Eden and Zeus untick
    the others, so only a link made later can do that): the first set up
    leads, logged (LINK).

    When the group splits, each part gets its own copy of the contacts and
    keeps its own vehicles' assignments (a missile already in flight is
    still followed), and its own settings again. Logged: LINK, LINK-CHANGE,
    UNLINK.

    Run from every Site's coordinator tick (server, every 0.5 s); works out
    every Site's group once a frame. Each Site logic carries:
        AEGISM_linkLead - its group's lead (itself while not linked)
        AEGISM_linkSites - its group's Sites ([itself])
        AEGISM_groupMembers - every vehicle of its group (its own members)
        AEGISM_links - every link holding its group together: [type, a, b]
            -- ["shared", vehicle, objNull], ["pair", vehicle, vehicle] (one
            on each Site), ["modules", Site, Site]

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_network_fnc_linkSites;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

if (!isServer) exitWith {};
if ((missionNamespace getVariable ["AEGISM_linkFrame", -1]) == diag_frameNo) exitWith {};
missionNamespace setVariable ["AEGISM_linkFrame", diag_frameNo];

// Every Site, in the order they were set up.
private _sites = (missionNamespace getVariable ["AEGISM_allPoolOwners", []]) select { !isNull _x && {!isNil {_x getVariable "AEGISM_networkMembers"}} };
if (_sites isEqualTo []) exitWith {};
private _count = count _sites;
private _membersOf = _sites apply { (_x getVariable ["AEGISM_networkMembers", []]) select { !isNull _x } };
// Members that can link: live AEGIS-M Systems.
private _linkersOf = _membersOf apply { _x select { alive _x && {!isNil {_x getVariable "AEGISM_system"}} } };
private _syncedOf = _sites apply { synchronizedObjects _x };
// Per Site: [linker, vehicles it's synced to] -- its own sync lines and its
// crew's, each as the vehicle.
private _vehicleSyncsOf = _linkersOf apply {
    _x apply {
        private _vehicle = _x;
        private _synced = synchronizedObjects _vehicle;
        { _synced append (synchronizedObjects _x); } forEach (crew _vehicle);
        [_vehicle, (_synced apply { vehicle _x }) - [_vehicle]]
    }
};

// Each Site's state as it stands, taken before any of it is replaced:
// [lead, group's Sites, pool, claims, links].
private _old = _sites apply {
    [_x getVariable ["AEGISM_linkLead", _x], _x getVariable ["AEGISM_linkSites", [_x]], _x getVariable ["AEGISM_pooledContacts", createHashMap], _x getVariable ["AEGISM_claims", createHashMap], _x getVariable ["AEGISM_links", []]]
};

// The links between every two Sites: [i, j, [link, ...]].
private _edges = [];
for "_i" from 0 to _count - 2 do {
    for "_j" from _i + 1 to _count - 1 do {
        private _siteA = _sites select _i;
        private _siteB = _sites select _j;
        private _linkersA = _linkersOf select _i;
        private _linkersB = _linkersOf select _j;
        private _links = (_linkersA arrayIntersect _linkersB) apply { ["shared", _x, objNull] };
        {
            _x params ["_vehicle", "_synced"];
            if !(_vehicle in _linkersB) then {
                { if (_x in _linkersB && {!(_x in _linkersA)}) then { _links pushBackUnique ["pair", _vehicle, _x]; }; } forEach _synced;
            };
        } forEach (_vehicleSyncsOf select _i);
        // A sync line seen from the other end only.
        {
            _x params ["_vehicle", "_synced"];
            if !(_vehicle in _linkersA) then {
                { if (_x in _linkersA && {!(_x in _linkersB)}) then { _links pushBackUnique ["pair", _x, _vehicle]; }; } forEach _synced;
            };
        } forEach (_vehicleSyncsOf select _j);
        if (_siteB in (_syncedOf select _i) || {_siteA in (_syncedOf select _j)}) then { _links pushBack ["modules", _siteA, _siteB]; };
        if (_links isNotEqualTo []) then { _edges pushBack [_i, _j, _links]; };
    };
};

// The groups: Sites joined by links, chained. [Site indices, links] each.
private _groupOf = [];
_groupOf resize _count;
_groupOf = _groupOf apply { -1 };
private _groups = [];
for "_i" from 0 to _count - 1 do {
    if ((_groupOf select _i) < 0) then {
        private _groupIndex = count _groups;
        private _indices = [_i];
        _groupOf set [_i, _groupIndex];
        private _queue = [_i];
        while { _queue isNotEqualTo [] } do {
            private _a = _queue deleteAt 0;
            {
                _x params ["_ei", "_ej"];
                private _other = if (_ei == _a) then { _ej } else { [-1, _ei] select (_ej == _a) };
                if (_other >= 0 && {(_groupOf select _other) < 0}) then {
                    _groupOf set [_other, _groupIndex];
                    _indices pushBack _other;
                    _queue pushBack _other;
                };
            } forEach _edges;
        };
        _indices sort true;
        private _links = [];
        { if ((_x select 0) in _indices) then { _links append (_x select 2); }; } forEach _edges;
        _groups pushBack [_indices, _links];
    };
};

// A link, readable: "AN/MPQ-105 Radar (synced to both)".
private _fnLinkText = {
    params ["_type", "_a", "_b"];
    switch (_type) do {
        case "shared": { format ["%1 %2 (synced to both)", _a, typeOf _a] };
        case "pair": { format ["%1 %2 -- %3 %4", _a, typeOf _a, _b, typeOf _b] };
        default { format ["%1 and %2 synced to each other", _a, _b] };
    }
};

{
    _x params ["_indices", "_links"];
    private _groupSites = _indices apply { _sites select _x };
    // Its lead: the Site ticked Shared Site Coordinator, else the first set up.
    private _coordinators = _groupSites select { _x getVariable ["sharedCoordinator", false] };
    private _lead = [_groupSites select 0, _coordinators param [0, objNull]] select (_coordinators isNotEqualTo []);
    private _groupMembers = [];
    { _groupMembers append (_membersOf select _x); } forEach _indices;
    _groupMembers = _groupMembers arrayIntersect _groupMembers;

    // Changed: a Site that led or followed another group before, or a new
    // lead.
    private _changed = (_indices findIf {
        (_old select _x) params ["_oldLead", "_oldSites"];
        _oldLead != _lead || {count _oldSites != count _groupSites} || {(_oldSites - _groupSites) isNotEqualTo []}
    }) != -1;
    // The links it had, from every Site of it.
    private _oldLinks = [];
    { { _oldLinks pushBackUnique _x; } forEach ((_old select _x) select 4); } forEach _indices;
    private _lost = _oldLinks select { private _link = _x; (_links findIf { _x isEqualTo _link }) == -1 };
    private _gained = _links select { private _link = _x; (_oldLinks findIf { _x isEqualTo _link }) == -1 };
    // What happened to a lost link.
    private _fnLostText = {
        params ["_type", "_a", "_b"];
        private _why = switch (true) do {
            case (_type == "modules"): { "the modules are no longer synced" };
            case (isNull _a || {!alive _a}): { format ["%1 destroyed", _a] };
            case (_type == "pair" && {isNull _b || {!alive _b}}): { format ["%1 destroyed", _b] };
            default { "no longer synced" };
        };
        format ["%1 (%2)", _this call _fnLinkText, _why]
    };

    if (_changed) then {
        // The group's pool and ledger, made from what its Sites held: every
        // contact (a copy -- a Site splitting off keeps its own), and the
        // assignments of the group's own vehicles (the same records: a fired
        // missile is tracked on its record).
        private _pool = createHashMap;
        private _claims = createHashMap;
        private _merged = [];
        {
            (_old select _x) params ["_oldLead", "", "_oldPool", "_oldClaims"];
            if !(_oldLead in _merged) then {
                _merged pushBack _oldLead;
                { if !(_x in _pool) then { _pool set [_x, +_y]; }; } forEach _oldPool;
                {
                    private _records = _y select { (_x get "system") in _groupMembers };
                    if (_records isNotEqualTo []) then { _claims set [_x, (_claims getOrDefault [_x, []]) + _records]; };
                } forEach _oldClaims;
            };
        } forEach _indices;

        {
            _x setVariable ["AEGISM_pooledContacts", _pool, false];
            _x setVariable ["AEGISM_claims", _claims, false];
            _x setVariable ["AEGISM_linkLead", _lead, false];
            _x setVariable ["AEGISM_linkSites", _groupSites, false];
            _x setVariable ["AEGISM_groupMembers", _groupMembers, false];
        } forEach _groupSites;

        if (count _groupSites > 1) then {
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " LINK: Sites %1 now work as one, linked by %2 link(s): %3 -- %4 coordinates every target across all %5 vehicle(s); %6; contacts and assignments are shared, and their alarms sound together.%7",
                _groupSites, count _links, (_links apply { _x call _fnLinkText }) joinString "; ", _lead, count _groupMembers,
                ["each vehicle keeps its own Site's settings (no Shared Site Coordinator)", format ["%1 is the Shared Site Coordinator: its settings apply to every vehicle of the group", _lead]] select (_lead getVariable ["sharedCoordinator", false]),
                ["", format [" WARNING: %1 are all ticked Shared Site Coordinator -- %2, set up first, leads.", _coordinators, _lead]] select (count _coordinators > 1)];
        } else {
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " UNLINK: Site %1 works on its own again, with its own settings -- %2. It keeps its own vehicles' assignments and a copy of the contacts.", _lead,
                if (_lost isEqualTo []) then { "its last link is gone" } else { "lost " + ((_lost apply { _x call _fnLostText }) joinString "; ") }];
        };

        // Whose settings apply may have changed (aegism_fnc_siteSettingsSource):
        // every vehicle of the group, at once rather than at its next 5 s poll.
        { if (!isNil {_x getVariable "AEGISM_system"}) then { [_x] call aegism_system_fnc_resolveSettings; }; } forEach _groupMembers;
    } else {
        // The same group, its links changed: one of several lost (still
        // linked by the rest), or a new one.
        if (count _groupSites > 1 && {_lost isNotEqualTo [] || {_gained isNotEqualTo []}}) then {
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " LINK-CHANGE: Sites %1 still work as one, linked by %2 link(s)%3%4.", _groupSites, count _links,
                ["", " -- lost " + ((_lost apply { _x call _fnLostText }) joinString "; ")] select (_lost isNotEqualTo []),
                ["", " -- new " + ((_gained apply { _x call _fnLinkText }) joinString "; ")] select (_gained isNotEqualTo [])];
        };
    };

    {
        _x setVariable ["AEGISM_groupMembers", _groupMembers, false];
        _x setVariable ["AEGISM_links", _links, false];
    } forEach _groupSites;
} forEach _groups;
