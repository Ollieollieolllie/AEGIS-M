/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_drawThreatRings

Description:
    Draws a Site's threat rings on the map (its Threat Rings setting): a
    ring for each weapon and sensor of every member System.
    Full notes: docs/functions/modules_network.md

Parameters:
    _logic - the Site logic (any Site of a linked group) <OBJECT>

Returns:
    Nothing

Examples:
    [_site] call aegism_network_fnc_drawThreatRings;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Line segments in a full ring (5 degrees each).
#define AEGISM_RING_SEGMENTS 72
// The side channel.
#define AEGISM_RING_CHANNEL 1
// Rings of one kind whose reaches are within this fraction of each other,
// on vehicles within this fraction of the larger reach of each other, are
// drawn as one.
#define AEGISM_RING_MERGE_FRACTION 0.1
// Where a full ring's label sits on its edge: the first of these bearings
// clear of the labels placed so far -- north-east, then the other
// diagonals, then between them.
#define AEGISM_RING_LABEL_BEARINGS [45, 315, 135, 225, 15, 345, 165, 195, 75, 285, 105, 255]
// Clear: at least this fraction of the larger ring's radius from another
// label, and never under this many metres.
#define AEGISM_RING_LABEL_GAP 0.1
#define AEGISM_RING_LABEL_MIN_GAP 500

params ["_logic"];

if (!isServer || {isNull _logic}) exitWith {};

// The Site's linked group (aegism_network_fnc_linkSites), drawn as one set by
// its lead; just the Site when it isn't linked. Whatever any of them had
// drawn goes first.
private _lead = _logic getVariable ["AEGISM_linkLead", _logic];
if (isNull _lead) then { _lead = _logic; };
private _groupSites = (_lead getVariable ["AEGISM_linkSites", [_lead]]) select { !isNull _x };
_groupSites pushBackUnique _lead;
private _hadRings = false;
{
    private _old = _x getVariable ["AEGISM_threatRings", []];
    if (_old isNotEqualTo []) then { _hadRings = true; };
    { deleteMarker _x; } forEach _old;
    _x setVariable ["AEGISM_threatRings", [], false];
} forEach _groupSites;

// Whose vehicles: with a Shared Site Coordinator, its Threat Rings setting
// decides for the whole group (its settings take precedence); otherwise each
// Site's own.
private _drawingSites = if (_lead getVariable ["sharedCoordinator", false]) then {
    [[], _groupSites] select (_lead getVariable ["threatRings", false])
} else {
    _groupSites select { _x getVariable ["threatRings", false] }
};
// Every vehicle once: one synced to two of them (linking them) is one vehicle.
private _drawnHere = [];
{
    { if (alive _x && {!isNil {_x getVariable "AEGISM_system"}}) then { _drawnHere pushBackUnique _x; }; } forEach (_x getVariable ["AEGISM_networkMembers", []]);
} forEach _drawingSites;
if (_drawnHere isEqualTo []) exitWith {
    if (_hadRings) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " THREAT-RINGS: %1 -- rings deleted (Threat Rings on Map now off).", _groupSites];
    };
};

// Who places them, and so whose side channel: one of the Sites' crew.
private _creator = objNull;
{
    private _crew = (crew _x) select { alive _x };
    if (_crew isNotEqualTo []) exitWith { _creator = _crew select 0; };
} forEach _drawnHere;
if (isNull _creator) exitWith {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " THREAT-RINGS: %1 has no crewed member System, so no side channel to draw its rings in -- none drawn.", _drawingSites];
};

private _sensorNames = createHashMapFromArray [["radar", "radar"], ["passive", "passive radar"], ["ir", "IR"], ["visual", "visual"]];

// [vehicle, colour, range, from bearing, arc, [what...]] per ring.
private _rings = [];
{
    private _vehicle = _x;
    private _capabilities = _vehicle getVariable "AEGISM_system";
    // Resolved now, not the cached copy: a vehicle adopted standalone before
    // the Site set up still has its standalone settings cached until its
    // next 5 s poll.
    private _settings = [_vehicle] call aegism_system_fnc_resolveEngagementSettings;
    private _vehicleRings = [];
    {
        _x params ["_role", "_colour"];
        {
            private _range = ([_settings, _x, _role] call aegism_intercept_fnc_envelopeBounds) select 1;
            _vehicleRings pushBack [_colour, round _range, 0, 360, getText (configFile >> "CfgWeapons" >> (_x select 1) >> "displayName")];
        } forEach (_capabilities get (_role + "Weapons"));
    } forEach [["launcher", "ColorRed"], ["ciws", "ColorOrange"]];
    {
        _x params ["_type", "_range", "_arc", "_aim", "_viewDistanceCoef"];
        if (_viewDistanceCoef > 0) then { _range = _range min (viewDistance * _viewDistanceCoef); };
        private _from = 0;
        if (_aim isNotEqualTo [] || {_arc >= 360}) then { _arc = 360; } else { _from = getDir _vehicle - _arc / 2; };
        _vehicleRings pushBack ["ColorBlue", round _range, round _from, round _arc, _sensorNames getOrDefault [_type, _type]];
    } forEach (_capabilities get "sensors");

    {
        _x params ["_colour", "_range", "_from", "_arc", "_what"];
        if (_range > 0) then {
            private _index = _rings findIf { (_x select [0, 5]) isEqualTo [_vehicle, _colour, _range, _from, _arc] };
            if (_index < 0) then {
                _rings pushBack [_vehicle, _colour, _range, _from, _arc, [_what]];
            } else {
                ((_rings select _index) select 5) pushBackUnique _what;
            };
        };
    } forEach _vehicleRings;
} forEach _drawnHere;

// Full rings of one kind (launcher, CIWS or sensor) with similar reaches on
// vehicles close together -- every pair's reaches within AEGISM_RING_MERGE_
// FRACTION of each other, and as close together as that fraction of the
// larger reach -- are drawn as one, whatever the weapon or vehicle. Sectors
// are drawn on their own.
// [colour, from, arc, [[vehicle, range, what], ...]] per ring drawn.
private _drawn = [];
{
    _x params ["_vehicle", "_colour", "_range", "_from", "_arc", "_what"];
    private _whatText = _what joinString " + ";
    private _index = if (_arc < 360) then { -1 } else {
        _drawn findIf {
            _x params ["_otherColour", "", "_otherArc", "_members"];
            _otherArc >= 360 && {_otherColour == _colour} && {
                (_members findIf {
                    _x params ["_memberVehicle", "_memberRange"];
                    private _limit = (_memberRange max _range) * AEGISM_RING_MERGE_FRACTION;
                    (abs (_memberRange - _range)) > _limit || {(_memberVehicle distance2D _vehicle) > _limit}
                }) == -1
            }
        }
    };
    if (_index < 0) then {
        _drawn pushBack [_colour, _from, _arc, [[_vehicle, _range, _whatText]]];
    } else {
        ((_drawn select _index) select 3) pushBack [_vehicle, _range, _whatText];
    };
} forEach _rings;

// A name no other marker has: the creator's machine, a running count, the
// channel.
private _fnCreate = {
    params ["_position"];
    private _count = (missionNamespace getVariable ["AEGISM_threatRingCount", 0]) + 1;
    missionNamespace setVariable ["AEGISM_threatRingCount", _count];
    createMarkerLocal [format ["_USER_DEFINED #%1/aegism%2/%3", clientOwner, _count, AEGISM_RING_CHANNEL], _position, AEGISM_RING_CHANNEL, _creator]
};

private _markers = [];
private _logged = [];
// Labels already placed: [position, ring radius].
private _placed = [];
{
    _x params ["_colour", "_from", "_arc", "_members"];
    private _vehicles = [];
    { _vehicles pushBackUnique (_x select 0); } forEach _members;
    // Centred on the middle of its vehicles, out to where the furthest-
    // reaching of them reaches: each one's reach plus its distance from the
    // middle, the largest of those -- so it covers every ring it replaces.
    private _cx = 0;
    private _cy = 0;
    {
        (getPosASL _x) params ["_px", "_py"];
        _cx = _cx + _px;
        _cy = _cy + _py;
    } forEach _vehicles;
    _cx = _cx / count _vehicles;
    _cy = _cy / count _vehicles;
    private _radius = 0;
    { _radius = _radius max ((_x select 1) + ([_cx, _cy] distance2D (_x select 0))); } forEach _members;
    private _full = _arc >= 360;

    // The ring: a sector runs out from the vehicle and back.
    private _points = [];
    if (!_full) then { _points append [_cx, _cy]; };
    private _steps = ceil (AEGISM_RING_SEGMENTS * _arc / 360) max 2;
    for "_i" from 0 to _steps do {
        private _bearing = _from + _arc * _i / _steps;
        _points append [_cx + _radius * sin _bearing, _cy + _radius * cos _bearing];
    };
    if (!_full) then { _points append [_cx, _cy]; };
    private _ring = [[_cx, _cy]] call _fnCreate;
    if (_ring != "") then {
        _ring setMarkerShapeLocal "POLYLINE";
        _ring setMarkerPolylineLocal _points;
        _ring setMarkerColor _colour;
        _markers pushBack _ring;
    };

    // Its label, on its edge: a sector's in the middle of its arc; a full
    // ring's on the first of AEGISM_RING_LABEL_BEARINGS (north-east first,
    // then the other diagonals) clear of every label placed so far -- two
    // rings the same size round the same place (a radar's and a launcher's
    // 16 km) put theirs on different diagonals instead of on top of each
    // other. Every system on it, longest reach first, the same vehicle and
    // weapon counted once: "4x MIM-145 Defender: MIM-145 16.0 km | Mk49
    // Spartan: RIM-116 15.5 km".
    private _fnLabelAt = { [_cx + _radius * sin _this, _cy + _radius * cos _this] };
    private _labelBearing = _from + _arc / 2;
    if (_full) then {
        private _clearIndex = AEGISM_RING_LABEL_BEARINGS findIf {
            private _at = _x call _fnLabelAt;
            (_placed findIf { (_at distance2D (_x select 0)) < ((((_x select 1) max _radius) * AEGISM_RING_LABEL_GAP) max AEGISM_RING_LABEL_MIN_GAP) }) == -1
        };
        _labelBearing = AEGISM_RING_LABEL_BEARINGS select (_clearIndex max 0);
    };
    _placed pushBack [_labelBearing call _fnLabelAt, _radius];
    // [name, what, range, count] per system.
    private _systems = [];
    {
        _x params ["_vehicle", "_range", "_what"];
        private _name = getText (configOf _vehicle >> "displayName");
        private _index = _systems findIf { (_x select [0, 3]) isEqualTo [_name, _what, _range] };
        if (_index < 0) then {
            _systems pushBack [_name, _what, _range, 1];
        } else {
            (_systems select _index) set [3, ((_systems select _index) select 3) + 1];
        };
    } forEach _members;
    _systems = [_systems, [], { _x select 2 }, "DESCEND"] call BIS_fnc_sortBy;
    private _text = (_systems apply {
        _x params ["_name", "_what", "_range", "_count"];
        format ["%1%2: %3 %4 km", ["", format ["%1x ", _count]] select (_count > 1), _name, _what, (_range / 1000) toFixed 1]
    }) joinString " | ";
    private _label = [_labelBearing call _fnLabelAt] call _fnCreate;
    if (_label != "") then {
        _label setMarkerShapeLocal "ICON";
        _label setMarkerTypeLocal "mil_dot";
        _label setMarkerTextLocal _text;
        _label setMarkerColor _colour;
        _markers pushBack _label;
    };
    _logged pushBack format ["%1 %2%3", _vehicles, _text,
        ["", format [" (one ring round all %1 vehicles, %2 km)", count _vehicles, (_radius / 1000) toFixed 1]] select (count _vehicles > 1)];
} forEach _drawn;

// Each drawing Site's protected area (Protected Area Radius, the Shared Site
// Coordinator's when there is one: aegism_fnc_siteSettingsSource), green,
// round the Site module -- labelled like the rings, on the first clear
// diagonal.
private _areas = 0;
{
    private _site = _x;
    private _areaRadius = (([_site] call aegism_fnc_siteSettingsSource) getVariable ["AEGISM_engagement", createHashMap]) getOrDefault ["protectRadius", 750];
    if (_areaRadius > 0) then {
        (getPosASL _site) params ["_cx", "_cy"];
        private _points = [];
        for "_i" from 0 to AEGISM_RING_SEGMENTS do {
            private _bearing = 360 * _i / AEGISM_RING_SEGMENTS;
            _points append [_cx + _areaRadius * sin _bearing, _cy + _areaRadius * cos _bearing];
        };
        private _ring = [[_cx, _cy]] call _fnCreate;
        if (_ring != "") then {
            _ring setMarkerShapeLocal "POLYLINE";
            _ring setMarkerPolylineLocal _points;
            _ring setMarkerColor "ColorGreen";
            _markers pushBack _ring;
        };
        private _fnLabelAt = { [_cx + _areaRadius * sin _this, _cy + _areaRadius * cos _this] };
        private _clearIndex = AEGISM_RING_LABEL_BEARINGS findIf {
            private _at = _x call _fnLabelAt;
            (_placed findIf { (_at distance2D (_x select 0)) < ((((_x select 1) max _areaRadius) * AEGISM_RING_LABEL_GAP) max AEGISM_RING_LABEL_MIN_GAP) }) == -1
        };
        private _labelBearing = AEGISM_RING_LABEL_BEARINGS select (_clearIndex max 0);
        _placed pushBack [_labelBearing call _fnLabelAt, _areaRadius];
        private _label = [_labelBearing call _fnLabelAt] call _fnCreate;
        if (_label != "") then {
            _label setMarkerShapeLocal "ICON";
            _label setMarkerTypeLocal "mil_dot";
            _label setMarkerTextLocal format ["Protected area: %1 m", round _areaRadius];
            _label setMarkerColor "ColorGreen";
            _markers pushBack _label;
        };
        _areas = _areas + 1;
        _logged pushBack format ["%1 protected area %2 m", _site, round _areaRadius];
    };
} forEach _drawingSites;

_lead setVariable ["AEGISM_threatRings", _markers, false];
diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " THREAT-RINGS: %1 drew %2 ring(s) for %3 vehicle(s) and %4 protected area(s) in %5's side channel (placed by %6): %7", _drawingSites, count _drawn, count _drawnHere, _areas, side group _creator, _creator, _logged joinString "; "];
