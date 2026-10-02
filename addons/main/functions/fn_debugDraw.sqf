/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugDraw

Description:
    Per-frame 3D debug overlay of AEGIS-M's live detection/engagement
    state, drawn straight from the variables the pipeline itself reads and
    writes -- what's on screen is what the mod is doing, not a separate
    simulation of it. CBA setting "aegism_main_debugDraw" (client-side, no
    gameplay effect). Only has data where the engagement pipeline runs
    (singleplayer, Eden Preview, a hosted game's host).

    Built to be read at a glance: one colour scheme, one label per thing,
    labels stacked (at a spacing that scales with distance, so they stay
    apart at any range) rather than drawn on top of each other.

        Colour = an engagement's state (aegism_fnc_statusStyle): queued
            blue, assigned green, reacting / slewing amber, reloading
            orange, range hold teal, firing red, in flight gold, no LOS /
            no solution purple, crew failed / fire held / no ammo grey.

        Contact - one icon per contact, however many pools hold it: a
            plane, a helicopter, or a target mark for a munition or drone.
            White while nothing is on it, otherwise the colour of the most
            urgent engagement on it. One short label: its class and, for an
            incoming munition, seconds to impact (the coordinator's own
            figure, aegism_intercept_fnc_assignEngagements).

        Engagement - a line from the weapon to its target in the state's
            colour. Waiting ones (queued behind the launcher's current
            target, missiles already in flight, held) are faint, so a
            launcher's queue doesn't drown out what it's actually doing. A
            CIWS held back by Last Resort Only is a dashed orange line.

        System - a shield over each AEGIS-M vehicle (a radar mark for a
            radar-only one), and stacked labels:
            1. its name
            2. network and radar status (light blue): its own radar -- reach,
               arc, emitting or silent (munitions are found by AEGIS-M's own
               check either way; aircraft only while an active radar emits)
               -- and its Site's radars and tracks, or STANDALONE with its
               own tracks. NO RADAR ON SITE in orange when networked but no
               member of its Site has a radar (aegism_system_fnc_
               resolveContactSource).
            3. each weapon role with rounds left and what it's doing ("MSL
               4: firing +3 queued", "GUN 680: slewing"), or NO AMMO (red)
            Name and weapons in its most urgent engagement's colour; grey
            while idle.

        Radar - a faint ring at each radar's own detection range.

        Not active - a vehicle AEGIS-M found capable but hasn't activated
            (deferred until synced, AEGISM_deferredSystems): grey, with
            "NOT ACTIVE:" and why -- e.g. a launcher with no radar of its
            own placed without a Site.

    Reads only published state (AEGISM_allPoolOwners, AEGISM_allSystems,
    AEGISM_system, AEGISM_pooledContacts, AEGISM_claims, AEGISM_
    withheldCiws, each System's AEGISM_turrets "standalone_<role>" states)
    and calls no function of the addons that publish it: this lives in
    aegism_main, which they all depend on.

Parameters:
    None

Returns:
    Nothing (run every frame from aegism's XEH_postInit)

Examples:
    [] call aegism_fnc_debugDraw;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

if !("aegism_main_debugDraw" call CBA_settings_fnc_get) exitWith {};

#define AEGISM_DEBUG_CIRCLE_SEGMENTS 36
// Vanilla task icons (ui_f_data, IGUI\Cfg\simpleTasks\types).
#define AEGISM_ICON_PLANE "\a3\ui_f\data\igui\cfg\simpleTasks\types\plane_ca.paa"
#define AEGISM_ICON_HELI "\a3\ui_f\data\igui\cfg\simpleTasks\types\heli_ca.paa"
#define AEGISM_ICON_TARGET "\a3\ui_f\data\igui\cfg\simpleTasks\types\target_ca.paa"
#define AEGISM_ICON_SHIELD "\a3\ui_f\data\igui\cfg\simpleTasks\types\defend_ca.paa"
#define AEGISM_ICON_RADAR "\a3\ui_f\data\igui\cfg\simpleTasks\types\radio_ca.paa"
// A stacked label's spacing, as a fraction of its distance from the camera:
// about one text line on screen at any range.
#define AEGISM_LINE_SPACING 0.022
#define AEGISM_TEXT_SIZE 0.032
#define AEGISM_SMALL_TEXT 0.027
// A waiting engagement's line alpha.
#define AEGISM_FAINT 0.3

private _camera = positionCameraToWorld [0, 0, 0];
// AGL position _lines text lines above _position (AGL).
private _fnStacked = {
    params ["_position", "_lines"];
    _position vectorAdd [0, 0, (_camera distance _position) * AEGISM_LINE_SPACING * _lines]
};
private _fnText = {
    params ["_position", "_text", "_color", "_size"];
    drawIcon3D ["", _color, _position, 0, 0, 0, _text, 2, _size, "RobotoCondensedBold", "center"];
};
private _grey = [0.75, 0.75, 0.75, 0.9];
private _white = [1, 1, 1, 0.95];

// --- Gather: contacts (one per key across every pool), engagements, radars ---
private _contacts = createHashMap;  // key -> [object, class, [tti, at]]
private _engagements = [];          // [system, target, contact key, role, status]
private _withheld = [];             // [system, target]
private _radars = [];               // [position ASL, range]
{
    private _owner = _x;
    if (!isNull _owner) then {
        private _system = _owner getVariable "AEGISM_system";
        private _isSystem = !isNil "_system";
        if (_isSystem && {_system get "hasRadar"}) then { _radars pushBack [getPosASL _owner, _system get "radarRange"]; };

        private _pool = _owner getVariable ["AEGISM_pooledContacts", createHashMap];
        {
            private _object = _y getOrDefault ["object", objNull];
            // One per contact; the Site's entry carries its time to impact.
            if (!isNull _object && {!(_x in _contacts) || {(((_contacts get _x) select 2) select 0) >= 1e9}}) then {
                _contacts set [_x, [_object, _y getOrDefault ["class", ""], _y getOrDefault ["tti", [1e10, time]]]];
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

// --- Radar rings ---
{
    _x params ["_center", "_radius"];
    private _previous = [];
    for "_i" from 0 to AEGISM_DEBUG_CIRCLE_SEGMENTS do {
        private _angle = (_i % AEGISM_DEBUG_CIRCLE_SEGMENTS) * (360 / AEGISM_DEBUG_CIRCLE_SEGMENTS);
        private _point = ASLToAGL (_center vectorAdd [_radius * sin _angle, _radius * cos _angle, 0]);
        if (_i > 0) then { drawLine3D [_previous, _point, [0.3, 0.6, 1, 0.25]]; };
        _previous = _point;
    };
} forEach _radars;

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
    drawLine3D [ASLToAGL eyePos _system, ASLToAGL getPosASLVisual _target, _lineColor];

    if (_urgency > ((_byTarget getOrDefault [_contactKey, [-1]]) select 0)) then { _byTarget set [_contactKey, [_urgency, _color]]; };
    private _roleKey = [netId _system, _role];
    (_byRole getOrDefault [_roleKey, [-1, "", 0, _grey]]) params ["_best", "_bestLabel", "_queued", "_bestColor"];
    if (_status == "queued") then { _queued = _queued + 1; };
    if (_status != "queued" && {_urgency > _best}) then { _best = _urgency; _bestLabel = _label; _bestColor = _color; };
    _byRole set [_roleKey, [_best, _bestLabel, _queued, _bestColor]];
} forEach _engagements;

// Last Resort Only: dashed orange.
{
    _x params ["_system", "_target"];
    private _from = ASLToAGL eyePos _system;
    private _span = (ASLToAGL getPosASLVisual _target) vectorDiff _from;
    for "_i" from 0 to 5 step 2 do {
        drawLine3D [_from vectorAdd (_span vectorMultiply (_i / 6)), _from vectorAdd (_span vectorMultiply ((_i + 1) / 6)), [1, 0.5, 0, 0.8]];
    };
} forEach _withheld;

// --- Contacts ---
{
    _y params ["_object", "_class", "_ttiInfo"];
    _ttiInfo params ["_tti", "_ttiAt"];
    private _position = ASLToAGL getPosASLVisual _object;
    private _color = (_byTarget getOrDefault [_x, [-1, _white]]) select 1;
    private _icon = switch (_class) do {
        case "fixedWing": { AEGISM_ICON_PLANE };
        case "helicopter": { AEGISM_ICON_HELI };
        default { AEGISM_ICON_TARGET };
    };
    drawIcon3D [_icon, _color, _position, 0.6, 0.6, 0, "", 2];
    private _remaining = _tti - (time - _ttiAt);
    private _text = toUpper _class;
    if (_tti < 1e9) then { _text = format ["%1  %2s", _text, (round (_remaining * 10) / 10) max 0]; };
    [[_position, -1.4] call _fnStacked, _text, _color, AEGISM_SMALL_TEXT] call _fnText;
} forEach _contacts;

// --- Systems ---
private _allSystems = (missionNamespace getVariable ["AEGISM_allSystems", []]) select { !isNull _x && {alive _x} };
missionNamespace setVariable ["AEGISM_allSystems", _allSystems, false];
// Per Site, once a frame: [radar-capable live members, contacts in its pool].
private _siteStats = createHashMap;
private _fnSiteStats = {
    params ["_site"];
    private _key = netId _site;
    private _stats = _siteStats get _key;
    if (isNil "_stats") then {
        private _radars = { alive _x && {((_x getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasRadar", false])} } count (_site getVariable ["AEGISM_networkMembers", []]);
        _stats = [_radars, count (_site getVariable ["AEGISM_pooledContacts", createHashMap])];
        _siteStats set [_key, _stats];
    };
    _stats
};
{
    private _vehicle = _x;
    private _system = _vehicle getVariable "AEGISM_system";
    if (!isNil "_system") then {
        private _network = _vehicle getVariable ["AEGISM_network", objNull];
        private _position = (ASLToAGL getPosASLVisual _vehicle) vectorAdd [0, 0, 3];

        // Network and radar status (the middle line): the vehicle's own
        // radar -- its reach and arc, and whether it's emitting (munitions
        // are found by AEGIS-M's own check either way; aircraft only while
        // an active radar emits, through the game's sensors) -- and where
        // its contacts come from: its Site (radars, contacts in the Site's
        // picture) or, standalone, its own radar alone.
        private _statusParts = [];
        private _statusColor = [0.55, 0.8, 1, 0.9];
        if (_system getOrDefault ["hasRadar", false]) then {
            _statusParts pushBack format ["RADAR %1km %2 %3", (round ((_system get "radarRange") / 100)) / 10,
                [format ["%1deg", round (_system get "radarArc")], "360"] select ((_system get "radarArc") >= 360),
                ["silent", "emitting"] select (isVehicleRadarOn _vehicle)];
        };
        if (isNull _network) then {
            _statusParts pushBack format ["STANDALONE, %1 tracks", count (_vehicle getVariable ["AEGISM_pooledContacts", createHashMap])];
        } else {
            ([_network] call _fnSiteStats) params ["_siteRadars", "_siteTracks"];
            private _siteName = vehicleVarName _network;
            private _siteTag = ["SITE " + _siteName, "SITE"] select (_siteName == "");
            if (!("network" in (_vehicle getVariable ["AEGISM_resolvedContactSource", []]))) then {
                _statusColor = [1, 0.6, 0, 1];
                _statusParts pushBack (_siteTag + ": NO RADAR ON SITE");
            } else {
                _statusParts pushBack format ["%1: %2 radar%3, %4 tracks", _siteTag, _siteRadars, ["s", ""] select (_siteRadars == 1), _siteTracks];
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

        drawIcon3D [[AEGISM_ICON_RADAR, AEGISM_ICON_SHIELD] select _hasWeapons, _color, _position, 0.5, 0.5, 0, "", 2];
        [[_position, _line + 0.8] call _fnStacked, getText (configOf _vehicle >> "displayName"), _color, AEGISM_TEXT_SIZE] call _fnText;
        [[_position, _line] call _fnStacked, _status, _statusColor, AEGISM_SMALL_TEXT] call _fnText;
        if (_hasWeapons) then {
            [[_position, 0.8] call _fnStacked, _roles joinString "   ", _color, AEGISM_SMALL_TEXT] call _fnText;
        };
    };
} forEach _allSystems;

// --- Not active: found capable, but deferred until synced to a Site (aegism_
// system_fnc_moduleInit's adoption policy) -- e.g. a launcher with no radar
// placed on its own. Grey, with why and what to do.
private _deferred = (missionNamespace getVariable ["AEGISM_deferredSystems", []]) select { !isNull _x && {alive _x} && {_x getVariable ["AEGISM_systemDeferred", false]} };
missionNamespace setVariable ["AEGISM_deferredSystems", _deferred, false];
{
    private _position = (ASLToAGL getPosASLVisual _x) vectorAdd [0, 0, 3];
    drawIcon3D [AEGISM_ICON_SHIELD, [0.6, 0.6, 0.6, 0.7], _position, 0.5, 0.5, 0, "", 2];
    [[_position, 1.6] call _fnStacked, getText (configOf _x >> "displayName"), [0.7, 0.7, 0.7, 0.9], AEGISM_TEXT_SIZE] call _fnText;
    [[_position, 0.8] call _fnStacked, "NOT ACTIVE: " + (_x getVariable ["AEGISM_deferReason", "deferred until synced to a Site"]), [1, 0.6, 0, 1], AEGISM_SMALL_TEXT] call _fnText;
} forEach _deferred;
