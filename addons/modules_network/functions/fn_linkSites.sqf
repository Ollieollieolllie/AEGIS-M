/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_linkSites

Description:
    Links Sites into one, and splits them again once the link is gone. Two
    Sites are linked while a live AEGIS-M System is synced to both (e.g. a
    radar both connect to), or while the Site modules are synced to each
    other. Links chain: A linked to B and B to C make one group of three.

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

    When the link is gone -- the vehicle linking them destroyed or unsynced,
    the Site modules unsynced -- the group splits back: each part gets its
    own copy of the contacts and keeps its own vehicles' assignments (a
    missile already in flight is still followed), and its own settings
    again. Logged: LINK, UNLINK.

    Run from every Site's coordinator tick (server, every 0.5 s); works out
    every Site's group once a frame. Each Site logic carries:
        AEGISM_linkLead - its group's lead (itself while not linked)
        AEGISM_linkSites - its group's Sites ([itself])
        AEGISM_groupMembers - every vehicle of its group (its own members)
        AEGISM_linkShared - what links its group: the shared vehicles, and
            the Site modules synced to each other

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
private _membersOf = _sites apply { (_x getVariable ["AEGISM_networkMembers", []]) select { !isNull _x } };
private _syncedOf = _sites apply { synchronizedObjects _x };

// Each Site's state as it stands, taken before any of it is replaced:
// [lead, group's Sites, pool, claims].
private _old = _sites apply {
    [_x getVariable ["AEGISM_linkLead", _x], _x getVariable ["AEGISM_linkSites", [_x]], _x getVariable ["AEGISM_pooledContacts", createHashMap], _x getVariable ["AEGISM_claims", createHashMap]]
};

// The groups: Sites joined by a live System synced to both, or synced to
// each other, chained. [Site indices, what links them] per group.
private _count = count _sites;
private _groupOf = [];
_groupOf resize _count;
_groupOf = _groupOf apply { -1 };
private _groups = [];
for "_i" from 0 to _count - 1 do {
    if ((_groupOf select _i) < 0) then {
        private _groupIndex = count _groups;
        private _indices = [_i];
        private _links = [];
        _groupOf set [_i, _groupIndex];
        private _queue = [_i];
        while { _queue isNotEqualTo [] } do {
            private _a = _queue deleteAt 0;
            for "_b" from 0 to _count - 1 do {
                if ((_groupOf select _b) < 0) then {
                    private _common = ((_membersOf select _a) arrayIntersect (_membersOf select _b)) select { alive _x && {!isNil {_x getVariable "AEGISM_system"}} };
                    private _siteA = _sites select _a;
                    private _siteB = _sites select _b;
                    if (_siteB in (_syncedOf select _a) || {_siteA in (_syncedOf select _b)}) then { _common append [_siteA, _siteB]; };
                    if (_common isNotEqualTo []) then {
                        _groupOf set [_b, _groupIndex];
                        _indices pushBack _b;
                        _queue pushBack _b;
                        { _links pushBackUnique _x; } forEach _common;
                    };
                };
            };
        };
        _indices sort true;
        _groups pushBack [_indices, _links];
    };
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

        private _oldShared = [];
        { { _oldShared pushBackUnique _x; } forEach (_x getVariable ["AEGISM_linkShared", []]); } forEach _groupSites;
        {
            _x setVariable ["AEGISM_pooledContacts", _pool, false];
            _x setVariable ["AEGISM_claims", _claims, false];
            _x setVariable ["AEGISM_linkLead", _lead, false];
            _x setVariable ["AEGISM_linkSites", _groupSites, false];
            _x setVariable ["AEGISM_groupMembers", _groupMembers, false];
        } forEach _groupSites;

        if (count _groupSites > 1) then {
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " LINK: Sites %1 now work as one, linked by %2 -- %3 coordinates every target across all %4 vehicle(s); %5; contacts and assignments are shared, and their alarms sound together.%6",
                _groupSites, _links apply { format ["%1 (%2)", _x, typeOf _x] }, _lead, count _groupMembers,
                ["each vehicle keeps its own Site's settings (no Shared Site Coordinator)", format ["%1 is the Shared Site Coordinator: its settings apply to every vehicle of the group", _lead]] select (_lead getVariable ["sharedCoordinator", false]),
                ["", format [" WARNING: %1 are all ticked Shared Site Coordinator -- %2, set up first, leads.", _coordinators, _lead]] select (count _coordinators > 1)];
        } else {
            private _lost = _oldShared select { !(_x in _groupMembers) || {!alive _x} };
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " UNLINK: Site %1 works on its own again, with its own settings -- %2. It keeps its own vehicles' assignments and a copy of the contacts.", _lead,
                if (_lost isEqualTo []) then { "what linked it is no longer synced to both" } else {
                    (_lost apply { format ["%1 (%2) %3", _x, typeOf _x, ["is no longer synced to both", "was destroyed"] select (!alive _x)] }) joinString ", "
                }];
        };

        // Whose settings apply may have changed (aegism_fnc_siteSettingsSource):
        // every vehicle of the group, at once rather than at its next 5 s poll.
        { if (!isNil {_x getVariable "AEGISM_system"}) then { [_x] call aegism_system_fnc_resolveSettings; }; } forEach _groupMembers;
    };

    {
        _x setVariable ["AEGISM_groupMembers", _groupMembers, false];
        _x setVariable ["AEGISM_linkShared", _links, false];
    } forEach _groupSites;
} forEach _groups;
