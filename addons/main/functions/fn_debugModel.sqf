/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugModel

Description:
    What the 3D debug overlay draws, worked out on the server from its live
    detection and engagement state: rings, lines, icons and labels, each
    placed on an anchor any machine can find (aegism_fnc_debugDraw).
    Full notes: docs/functions/main.md

Parameters:
    None

Returns:
    [built at (CBA_missionTime), rings, lines, icons, texts] <ARRAY>

Examples:
    private _model = [] call aegism_fnc_debugModel;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Vanilla task icons (ui_f_data, IGUI\Cfg\simpleTasks\types).
#define AEGISM_ICON_PLANE "\a3\ui_f\data\igui\cfg\simpleTasks\types\plane_ca.paa"
#define AEGISM_ICON_HELI "\a3\ui_f\data\igui\cfg\simpleTasks\types\heli_ca.paa"
#define AEGISM_ICON_TARGET "\a3\ui_f\data\igui\cfg\simpleTasks\types\target_ca.paa"
#define AEGISM_ICON_SHIELD "\a3\ui_f\data\igui\cfg\simpleTasks\types\defend_ca.paa"
#define AEGISM_ICON_RADAR "\a3\ui_f\data\igui\cfg\simpleTasks\types\radio_ca.paa"
#define AEGISM_TEXT_SIZE 0.032
#define AEGISM_SMALL_TEXT 0.027
// A waiting engagement's line alpha.
#define AEGISM_FAINT 0.3
// A sensor sighting this recent counts as seen now (the pools' own contact
// expiry, aegism_detect_fnc_pruneStaleContacts).
#define AEGISM_SIGHT_WINDOW 3

// Where something is drawn: [object, its position ASL, its velocity, metres
// above it, at its eyes]. Where the object can't be had -- a shell flown on
// every machine for itself isn't one the network carries -- the position,
// moved on by the velocity, stands in (aegism_fnc_debugDraw).
private _fnAnchor = {
    params ["_object", ["_lift", 0], ["_eye", false]];
    [_object, if (_eye) then { eyePos _object } else { getPosASLVisual _object }, velocity _object, _lift, _eye]
};
private _fnFixed = { [objNull, _this, [0, 0, 0], 0, false] };
private _grey = [0.75, 0.75, 0.75, 0.9];
private _white = [1, 1, 1, 0.95];

private _rings = [];   // [anchor, radius, colour]
private _lines = [];   // [from anchor, to anchor, colour, dashes (0 solid)]
private _icons = [];   // [anchor, icon, colour, size]
private _texts = [];   // [anchor, lines above it, text, colour, size, impact at (-1: none; else the text takes seconds to it as %1)]

// --- Gather: contacts (one per key across every pool), engagements, radars ---
private _contacts = createHashMap;  // key -> [object, class, [tti, at], sensor kind -> last seen]
private _engagements = [];          // [system, target, contact key, role, status]
private _withheld = [];             // [system, target]
private _radars = [];               // [range, radar]
private _sightings = [];            // [sensor vehicle, contact key -> heard by passive radar only]
{
    private _owner = _x;
    if (!isNull _owner) then {
        private _system = _owner getVariable "AEGISM_system";
        private _isSystem = !isNil "_system";
        if (_isSystem && {_system get "hasRadar"}) then { _radars pushBack [_system get "radarRange", _owner]; };

        private _pool = _owner getVariable ["AEGISM_pooledContacts", createHashMap];

        // What its own sensors saw in the last AEGISM_SIGHT_WINDOW s: aircraft
        // in its own pool, and the munitions its last sensor read saw
        // (aegism_detect_fnc_confidenceLoop) -- not its Site's whole picture.
        if (_isSystem && {_system getOrDefault ["hasSensor", false]}) then {
            private _seen = createHashMap;
            {
                private _key = _x;
                private _kinds = [];
                { if (CBA_missionTime - _y <= AEGISM_SIGHT_WINDOW) then { _kinds pushBack _x; }; } forEach (_y getOrDefault ["sources", createHashMap]);
                if (_kinds isNotEqualTo []) then { _seen set [_key, _kinds isEqualTo ["passiveradar"]]; };
            } forEach _pool;
            (_owner getVariable ["AEGISM_seenMunitions", [-1e9, createHashMap]]) params ["_readAt", "_munitions"];
            if (CBA_missionTime - _readAt <= AEGISM_SIGHT_WINDOW) then {
                { _seen set [_x, false]; } forEach _munitions;
            };
            _sightings pushBack [_owner, _seen];
        };
        {
            private _object = _y getOrDefault ["object", objNull];
            if (!isNull _object) then {
                private _known = _contacts get _x;
                if (isNil "_known") then {
                    _known = [_object, _y getOrDefault ["class", ""], [1e10, CBA_missionTime], createHashMap];
                    _contacts set [_x, _known];
                };
                // One per contact; the Site's entry carries its time to impact.
                if ("tti" in _y && {(((_known select 2) select 0) >= 1e9)}) then { _known set [2, _y get "tti"]; };
                // The sensor kinds that saw it, from every pool holding it.
                private _seen = _known select 3;
                { if (_y > (_seen getOrDefault [_x, -1e9])) then { _seen set [_x, _y]; }; } forEach (_y getOrDefault ["sources", createHashMap]);
            };
        } forEach _pool;

        if (_isSystem) then {
            // Standalone: each weapon turret's own engagement state.
            {
                private _turretState = _y;
                {
                    private _state = _turretState getOrDefault ["standalone_" + _x, createHashMap];
                    private _target = _state getOrDefault ["target", objNull];
                    if (!isNull _target) then { _engagements pushBack [_owner, _target, [_target] call aegism_fnc_contactKey, _x, _state getOrDefault ["status", ""]]; };
                } forEach ["launcher", "ciws"];
            } forEach (_owner getVariable ["AEGISM_turrets", createHashMap]);
        } else {
            // A Site: every assignment record across the battery.
            {
                private _contactKey = _x;
                {
                    private _target = _x getOrDefault ["target", objNull];
                    private _assigned = _x getOrDefault ["system", objNull];
                    if (!isNull _target && {!isNull _assigned}) then {
                        _engagements pushBack [_assigned, _target, _contactKey, _x get "role", _x getOrDefault ["status", ""]];
                    };
                } forEach _y;
            } forEach (_owner getVariable ["AEGISM_claims", createHashMap]);
            {
                _x params ["_contactKey", "_heldSystem"];
                private _target = (_pool getOrDefault [_contactKey, createHashMap]) getOrDefault ["object", objNull];
                if (!isNull _target && {!isNull _heldSystem}) then { _withheld pushBack [_heldSystem, _target]; };
            } forEach (_owner getVariable ["AEGISM_withheldCiws", []]);
        };
    };
} forEach (missionNamespace getVariable ["AEGISM_allPoolOwners", []]);

// Each contact's anchor, once.
private _contactAnchors = createHashMap;
{ _contactAnchors set [_x, [_y select 0] call _fnAnchor]; } forEach _contacts;

// --- Radar rings: blue, amber while AEGIS-M has it emitting, grey while it
// keeps it silent, red while it's shut down for an anti-radiation missile
// (aegism_fnc_emconText) ---
{
    _x params ["_radius", "_radar"];
    private _color = [0.3, 0.6, 1, 0.25];
    ([_radar] call aegism_fnc_emconText) params ["_label", "", "", "_rgba"];
    if (_label != "" && {!(_label in ["AI: EMITTING", "AI: SILENT"])}) then {
        _color = +_rgba;
        _color set [3, [0.3, 0.15] select (_label == "SILENT")];
    };
    _rings pushBack [[_radar] call _fnAnchor, _radius, _color];
} forEach _radars;

// --- Sight lines: a faint line from each sensor vehicle to each contact its
// own sensors see now (lighter for one only its passive radar hears) -- a
// Site's picture is every member's, so this is the only place it shows which
// vehicle actually sees what ---
private _seesCount = createHashMap;  // vehicle netId -> [seen, heard only]
{
    _x params ["_sensorVehicle", "_seen"];
    private _from = [_sensorVehicle, 2] call _fnAnchor;
    private _sees = 0;
    private _hears = 0;
    {
        private _to = _contactAnchors get _x;
        if (!isNil "_to") then {
            if (_y) then { _hears = _hears + 1; } else { _sees = _sees + 1; };
            _lines pushBack [_from, _to, [[0.55, 0.8, 1, 0.35], [0.7, 0.55, 1, 0.18]] select _y, 0];
        };
    } forEach _seen;
    _seesCount set [netId _sensorVehicle, [_sees, _hears]];
} forEach _sightings;

// --- Sites (aegism_network_fnc_linkSites) -----------------------------------------
// Each Site module is labelled with its name, what it is to its linked group
// and whose settings its vehicles use, in the Site's own colour, with a
// faint line of that colour to each of its vehicles. Each link between two
// Sites is a dashed white line between their modules, captioned with what
// forms it; a link made by two vehicles synced to each other is also drawn
// between those two.
private _siteColours = [[0.3, 0.9, 1], [1, 0.8, 0.3], [0.65, 1, 0.45], [1, 0.55, 0.8], [0.65, 0.7, 1], [1, 0.6, 0.35]];
private _allSites = (missionNamespace getVariable ["AEGISM_allPoolOwners", []]) select { !isNull _x && {!isNil { _x getVariable "AEGISM_networkMembers" }} };
{
    private _site = _x;
    private _rgb = _siteColours select (_forEachIndex mod (count _siteColours));
    private _at = [_site, 3] call _fnAnchor;
    private _linked = (_site getVariable ["AEGISM_linkSites", [_site]]) - [_site];
    private _lead = _site getVariable ["AEGISM_linkLead", _site];
    private _source = [_site] call aegism_fnc_siteSettingsSource;
    private _members = (_site getVariable ["AEGISM_networkMembers", []]) select { !isNull _x && {alive _x} };
    private _second = format ["%1 vehicle(s)", count _members];
    if (_linked isNotEqualTo []) then {
        _second = _second + format [", linked with %1; %2", (_linked apply { [_x] call aegism_fnc_siteName }) joinString " + ",
            ["its own settings", format ["settings from %1", [_source] call aegism_fnc_siteName]] select (_source != _site)];
    };
    _texts pushBack [_at, 1, format ["%1%2", toUpper ([_site] call aegism_fnc_siteName), ["", "  -  COORDINATOR"] select (_linked isNotEqualTo [] && {_lead == _site})], _rgb + [1], AEGISM_TEXT_SIZE, -1];
    _texts pushBack [_at, 0, _second, _rgb + [0.9], AEGISM_SMALL_TEXT, -1];
    { _lines pushBack [_at, [_x, 2] call _fnAnchor, _rgb + [0.35], 0]; } forEach _members;
} forEach _allSites;

// Each group's links once. Several between the same two Sites stack their
// captions.
private _linkGroupsDrawn = [];
private _captions = createHashMap;
private _fnVehicleName = { private _name = getText (configOf _this >> "displayName"); [_name, typeOf _this] select (_name == "") };
{
    private _site = _x;
    private _lead = _site getVariable ["AEGISM_linkLead", _site];
    if !(_lead in _linkGroupsDrawn) then {
        _linkGroupsDrawn pushBack _lead;
        {
            _x params ["_type", "_a", "_b", ["_siteA", objNull], ["_siteB", objNull]];
            if (!isNull _siteA && {!isNull _siteB}) then {
                _lines pushBack [[_siteA, 3] call _fnAnchor, [_siteB, 3] call _fnAnchor, [1, 1, 1, 0.85], 8];
                private _pairKey = [netId _siteA, netId _siteB];
                private _row = _captions getOrDefault [_pairKey, 0];
                _captions set [_pairKey, _row + 1];
                private _middle = ((getPosASLVisual _siteA) vectorAdd (getPosASLVisual _siteB)) vectorMultiply 0.5;
                _texts pushBack [(_middle vectorAdd [0, 0, 3]) call _fnFixed, _row,
                    format ["LINK  %1 + %2  by %3", [_siteA] call aegism_fnc_siteName, [_siteB] call aegism_fnc_siteName,
                        switch (_type) do {
                            case "shared": { format ["%1 (in both)", _a call _fnVehicleName] };
                            case "pair": { format ["%1 synced to %2", _a call _fnVehicleName, _b call _fnVehicleName] };
                            default { "their modules" };
                        }],
                    [1, 1, 1, 0.95], AEGISM_SMALL_TEXT, -1];
                if (_type == "pair" && {!isNull _a} && {!isNull _b}) then {
                    _lines pushBack [[_a, 2] call _fnAnchor, [_b, 2] call _fnAnchor, [1, 1, 1, 0.6], 5];
                };
            };
        } forEach (_site getVariable ["AEGISM_links", []]);
    };
} forEach _allSites;

// --- Engagement lines; per target and per system role, the most urgent ---
// (Keyed by contact key and vehicle netId: a HashMap can't key on objects.)
private _byTarget = createHashMap;  // contact key -> [urgency, colour]
private _byRole = createHashMap;    // [system netId, role] -> [urgency, label, queued count, colour]
{
    _x params ["_system", "_target", "_contactKey", "_role", "_status"];
    ([_status] call aegism_fnc_statusStyle) params ["_label", "_color", "", "_urgency"];
    private _waiting = _status in ["queued", "inFlight", "held", "crewFailed", "noAmmo"];
    private _lineColor = +_color;
    if (_waiting) then { _lineColor set [3, AEGISM_FAINT]; };
    private _to = _contactAnchors get _contactKey;
    if (isNil "_to") then { _to = [_target] call _fnAnchor; };
    _lines pushBack [[_system, 0, true] call _fnAnchor, _to, _lineColor, 0];

    if (_urgency > ((_byTarget getOrDefault [_contactKey, [-1]]) select 0)) then { _byTarget set [_contactKey, [_urgency, _color]]; };
    private _roleKey = [netId _system, _role];
    (_byRole getOrDefault [_roleKey, [-1, "", 0, _grey]]) params ["_best", "_bestLabel", "_queued", "_bestColor"];
    if (_status == "queued") then { _queued = _queued + 1; };
    if (_status != "queued" && {_urgency > _best}) then { _best = _urgency; _bestLabel = _label; _bestColor = _color; };
    _byRole set [_roleKey, [_best, _bestLabel, _queued, _bestColor]];
} forEach _engagements;

// Held back by its Engagement Mode: dashed orange.
{
    _x params ["_system", "_target"];
    _lines pushBack [[_system, 0, true] call _fnAnchor, [_target] call _fnAnchor, [1, 0.5, 0, 0.8], 3];
} forEach _withheld;

// --- Contacts ---
{
    _y params ["_object", "_class", "_ttiInfo", "_seen"];
    _ttiInfo params ["_tti", "_ttiAt"];
    private _anchor = _contactAnchors get _x;
    private _color = (_byTarget getOrDefault [_x, [-1, _white]]) select 1;
    private _icon = switch (_class) do {
        case "fixedWing": { AEGISM_ICON_PLANE };
        case "helicopter": { AEGISM_ICON_HELI };
        default { AEGISM_ICON_TARGET };
    };
    _icons pushBack [_anchor, _icon, _color, 0.6];
    private _text = toUpper _class;
    if (_tti < 1e9) then { _text = _text + "  %1s"; };
    private _tags = [_seen] call aegism_fnc_sensorTags;
    // Only passive radar hears it: it cues radars, nothing engages it.
    if !([createHashMapFromArray [["sources", _seen]]] call aegism_fnc_hasTrack) then { _tags = ([_tags, "CUE ONLY"] - [""]) joinString " "; };
    if (_tags != "") then { _text = format ["%1  [%2]", _text, _tags]; };
    _texts pushBack [_anchor, -1.4, _text, _color, AEGISM_SMALL_TEXT, [-1, _ttiAt + _tti] select (_tti < 1e9)];
} forEach _contacts;

// --- Systems ---
private _allSystems = (missionNamespace getVariable ["AEGISM_allSystems", []]) select { !isNull _x && {alive _x} };
missionNamespace setVariable ["AEGISM_allSystems", _allSystems, false];
// Per Site, once a build: [live members with a radar, live members with
// another sensor of their own (IR, visual) and no radar, contacts in its pool].
private _siteStats = createHashMap;
private _fnSiteStats = {
    params ["_site"];
    private _key = netId _site;
    private _stats = _siteStats get _key;
    if (isNil "_stats") then {
        // A Site linked with others (aegism_network_fnc_linkSites): the whole
        // group's sensors feed its shared contacts.
        private _members = (_site getVariable ["AEGISM_groupMembers", _site getVariable ["AEGISM_networkMembers", []]]) select { alive _x };
        private _radarCount = { ((_x getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasRadar", false]) } count _members;
        private _others = {
            private _memberSystem = _x getVariable ["AEGISM_system", createHashMap];
            (_memberSystem getOrDefault ["hasSensor", false]) && {!(_memberSystem getOrDefault ["hasRadar", false])}
        } count _members;
        _stats = [_radarCount, _others, count (_site getVariable ["AEGISM_pooledContacts", createHashMap])];
        _siteStats set [_key, _stats];
    };
    _stats
};
{
    private _vehicle = _x;
    private _system = _vehicle getVariable "AEGISM_system";
    if (!isNil "_system") then {
        private _network = _vehicle getVariable ["AEGISM_network", objNull];
        private _anchor = [_vehicle, 3] call _fnAnchor;

        // Network and sensor status (the middle line): the vehicle's own
        // sensors, the longest of each kind -- reach, arc, "turret" if it
        // turns with one, and for a radar whether it's emitting (a silent
        // radar sees nothing, aircraft or munitions) -- and where
        // its contacts come from: its Site (sensor vehicles, contacts in the
        // Site's picture) or, standalone, its own sensors alone.
        private _statusParts = [];
        private _statusColor = [0.55, 0.8, 1, 0.9];
        private _sensorParts = [];
        private _kindsShown = [];
        private _sensorCodes = createHashMapFromArray [["radar", "RDR"], ["passive", "PAS"], ["ir", "IR"], ["visual", "VIS"]];
        {
            _x params ["_type", "_range", "_arc", "_aim"];
            if !(_type in _kindsShown) then {
                _kindsShown pushBack _type;
                private _text = format ["%1 %2km %3", _sensorCodes getOrDefault [_type, toUpper _type], (round (_range / 100)) / 10, [format ["%1deg", round _arc], "360"] select (_arc >= 360)];
                if (_aim isNotEqualTo []) then { _text = _text + " turret"; };
                if (_type == "radar") then {
                    // Its emission (Radar Emission, aegism_fnc_emconText), and why.
                    ([_vehicle] call aegism_fnc_emconText) params ["_label", "_detail"];
                    if (_label == "") then { _label = ["SILENT", "EMITTING"] select (isVehicleRadarOn _vehicle); };
                    _text = _text + " " + _label;
                    if !(_detail in ["", "always on", "the AI decides"]) then { _text = _text + format [" (%1)", _detail]; };
                    // Where a turning radar's beam is and why (aegism_system_
                    // fnc_radarSchedule): SEARCH 120 deg, TRACK 2 (045 deg).
                    private _beamText = (_vehicle getVariable ["AEGISM_radarBeam", createHashMap]) getOrDefault ["text", ""];
                    if (_beamText != "") then { _text = _text + " " + _beamText; };
                };
                _sensorParts pushBack _text;
            };
        } forEach (_system getOrDefault ["sensors", []]);
        if (_sensorParts isNotEqualTo []) then {
            private _sensorText = _sensorParts joinString "  ";
            // How many contacts its own sensors see now (the sight lines).
            if (_system getOrDefault ["hasSensor", false]) then {
                (_seesCount getOrDefault [netId _vehicle, [0, 0]]) params ["_sees", "_hears"];
                _sensorText = _sensorText + format [": sees %1", _sees] + (["", format [", hears %1", _hears]] select (_hears > 0));
            };
            _statusParts pushBack _sensorText;
        };
        if (isNull _network) then {
            _statusParts pushBack format ["STANDALONE, %1 tracks", count (_vehicle getVariable ["AEGISM_pooledContacts", createHashMap])];
        } else {
            ([_network] call _fnSiteStats) params ["_siteRadars", "_siteOthers", "_siteTracks"];
            private _siteTag = toUpper ([_network] call aegism_fnc_siteName);
            private _linkedSites = count (_network getVariable ["AEGISM_linkSites", [_network]]);
            if (_linkedSites > 1) then {
                private _lead = _network getVariable ["AEGISM_linkLead", _network];
                private _links = _network getVariable ["AEGISM_links", []];
                _siteTag = _siteTag + format [" (LINKED, %1 Sites by %2 link%3, %4)", _linkedSites, count _links, ["s", ""] select (count _links == 1),
                    if (_lead == _network) then { "coordinating" } else { format ["coordinated by %1", toUpper ([_lead] call aegism_fnc_siteName)] }];
                // This vehicle forms one of the links.
                if ((_links findIf { (_x select 0) in ["shared", "pair"] && {(_x select 1) == _vehicle || {(_x select 2) == _vehicle}} }) != -1) then {
                    _siteTag = "LINK  " + _siteTag;
                };
            };
            // No sensor of its own: its contacts come from its Site's (DL).
            if !(_system getOrDefault ["hasSensor", false]) then { _statusParts pushBack "DL"; };
            if (!("network" in (_vehicle getVariable ["AEGISM_resolvedContactSource", []]))) then {
                _statusColor = [1, 0.6, 0, 1];
                _statusParts pushBack (_siteTag + ": NO SENSOR ON SITE");
            } else {
                private _siteSensors = format ["%1 radar%2", _siteRadars, ["s", ""] select (_siteRadars == 1)];
                if (_siteOthers > 0) then { _siteSensors = _siteSensors + format [" + %1 IR/visual", _siteOthers]; };
                _statusParts pushBack format ["%1: %2, %3 tracks", _siteTag, _siteSensors, _siteTracks];
            };
        };
        private _status = _statusParts joinString "  |  ";

        private _roles = [];
        private _totalAmmo = 0;
        private _best = -1;
        private _color = _grey;
        {
            _x params ["_role", "_tag"];
            private _weapons = _system getOrDefault [["launcherWeapons", "ciwsWeapons"] select (_role == "ciws"), []];
            if (_weapons isNotEqualTo []) then {
                private _rounds = 0;
                { _x params ["_turretPath", "", "_magClass"]; _rounds = _rounds + (_vehicle magazineTurretAmmo [_magClass, _turretPath]); } forEach _weapons;
                _totalAmmo = _totalAmmo + _rounds;
                (_byRole getOrDefault [[netId _vehicle, _role], [-1, "", 0, _grey]]) params ["_urgency", "_label", "_queued", "_roleColor"];
                private _text = format ["%1 %2", _tag, _rounds];
                if (_label != "") then { _text = _text + ": " + _label; };
                if (_queued > 0) then { _text = _text + format [" +%1 queued", _queued]; };
                _roles pushBack _text;
                if (_urgency > _best) then { _best = _urgency; _color = _roleColor; };
            };
        } forEach [["launcher", "MSL"], ["ciws", "GUN"]];

        // Top to bottom: name, network and radar status, weapons (a
        // radar-only vehicle has no weapons line).
        private _hasWeapons = _roles isNotEqualTo [];
        if (_hasWeapons && {_totalAmmo <= 0}) then { _color = [1, 0.25, 0.25, 1]; _roles = ["NO AMMO"]; };
        private _line = [0.8, 1.6] select _hasWeapons;

        _icons pushBack [_anchor, [AEGISM_ICON_RADAR, AEGISM_ICON_SHIELD] select _hasWeapons, _color, 0.5];
        _texts pushBack [_anchor, _line + 0.8, getText (configOf _vehicle >> "displayName"), _color, AEGISM_TEXT_SIZE, -1];
        _texts pushBack [_anchor, _line, _status, _statusColor, AEGISM_SMALL_TEXT, -1];
        if (_hasWeapons) then {
            _texts pushBack [_anchor, 0.8, _roles joinString "   ", _color, AEGISM_SMALL_TEXT, -1];
        };
    };
} forEach _allSystems;

// --- Not active: found capable, but deferred until synced to a Site (aegism_
// system_fnc_moduleInit's adoption policy) -- e.g. a launcher with no radar
// placed on its own. Grey, with why and what to do.
private _deferred = (missionNamespace getVariable ["AEGISM_deferredSystems", []]) select { !isNull _x && {alive _x} && {_x getVariable ["AEGISM_systemDeferred", false]} };
missionNamespace setVariable ["AEGISM_deferredSystems", _deferred, false];
{
    private _anchor = [_x, 3] call _fnAnchor;
    _icons pushBack [_anchor, AEGISM_ICON_SHIELD, [0.6, 0.6, 0.6, 0.7], 0.5];
    _texts pushBack [_anchor, 1.6, getText (configOf _x >> "displayName"), [0.7, 0.7, 0.7, 0.9], AEGISM_TEXT_SIZE, -1];
    _texts pushBack [_anchor, 0.8, "NOT ACTIVE: " + (_x getVariable ["AEGISM_deferReason", "deferred until synced to a Site"]), [1, 0.6, 0, 1], AEGISM_SMALL_TEXT, -1];
} forEach _deferred;

[CBA_missionTime, _rings, _lines, _icons, _texts]
