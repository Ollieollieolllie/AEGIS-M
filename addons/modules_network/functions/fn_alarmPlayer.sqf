/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_alarmPlayer

Description:
    Plays the Sites' alarms on this machine: every machine with a player
    runs it every frame (this addon's XEH_postInit). The server only decides
    each Site's alarm and publishes it ("AEGISM_alarmNow", aegism_network_
    fnc_siteAlarm); this plays it for this machine alone (playSound3D,
    local) at each of the Site's speakers:
        - one cycle of the sound at a time, the next as soon as the last has
          ended (after the sound's own CfgSFX delay, none for AEGIS-M's
          tones). Every cycle is a new sound, so none is ever left stuck: a
          looping engine sound source (what the server used to create)
          wasn't heard again after the camera had been away -- Zeus, a
          spectator, a teleport -- and sometimes not from its start;
        - only while the camera, wherever it is (the player, Zeus, a
          spectator), is within the sound's reach of the speaker, and from
          the moment it comes within it;
        - a one-shot (the All Clear) once, when it's published, from the
          speakers in reach then.
    A new state stops the old sound at once.

    The sound is read from the class's own config, as the engine plays a
    sound source: CfgVehicles <class> >> sound, and that CfgSFX class's
    sounds[] (each [file, volume, pitch, reach, probability, min, mid, max
    delay], one picked by probability for each cycle). A file named without
    its extension, as CfgSFX allows (playSound3D needs it), is found as .wss,
    .ogg or .wav. Resolved once per class ("AEGISM_cacheAlarmSound"); a class
    with nothing playable is logged once (ALARM-SOUND).

Parameters:
    None

Returns:
    Nothing

Examples:
    [aegism_network_fnc_alarmPlayer, 0, []] call CBA_fnc_addPerFrameHandler;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

private _sites = missionNamespace getVariable ["AEGISM_alarmSites", []];
if (_sites isEqualTo []) exitWith {};

// A sound source class -> [sounds, weights]: each sound [file, volume,
// pitch, reach, min delay, mid delay, max delay].
private _fnSounds = {
    params ["_class"];
    private _cache = missionNamespace getVariable "AEGISM_cacheAlarmSound";
    if (isNil "_cache") then {
        _cache = createHashMap;
        missionNamespace setVariable ["AEGISM_cacheAlarmSound", _cache];
    };
    private _cached = _cache get _class;
    if (!isNil "_cached") exitWith { _cached };

    // A CfgSFX volume is a number, or a "db-10" string in a config left as text.
    private _fnNumber = {
        params ["_value"];
        if (_value isEqualType 0) exitWith { _value };
        if ((toLower (_value select [0, 2])) == "db") exitWith { 10 ^ ((parseNumber (_value select [2])) / 20) };
        parseNumber _value
    };
    private _sfx = configFile >> "CfgSFX" >> getText (configFile >> "CfgVehicles" >> _class >> "sound");
    private _sounds = [];
    private _weights = [];
    private _missing = [];
    {
        (getArray (_sfx >> _x)) params [["_file", ""], ["_volume", 1], ["_pitch", 1], ["_reach", 0], ["_probability", 1], ["_minDelay", 0], ["_midDelay", 0], ["_maxDelay", 0]];
        // An addon path, without the leading "@" or "\" a config may give it.
        while {_file != "" && {(_file select [0, 1]) in ["@", "\"]}} do { _file = _file select [1]; };
        if (_file != "") then {
            if !((toLower (_file select [count _file - 4])) in [".wss", ".ogg", ".wav"]) then {
                private _found = [".wss", ".ogg", ".wav"] findIf { fileExists (_file + _x) };
                _file = if (_found == -1) then { _missing pushBack _file; "" } else { _file + ([".wss", ".ogg", ".wav"] select _found) };
            };
        };
        if (_file != "" && {([_probability] call _fnNumber) > 0}) then {
            _sounds pushBack [_file, [_volume] call _fnNumber, [_pitch] call _fnNumber, [_reach] call _fnNumber,
                [_minDelay] call _fnNumber, [_midDelay] call _fnNumber, [_maxDelay] call _fnNumber];
            _weights pushBack ([_probability] call _fnNumber);
        };
    } forEach getArray (_sfx >> "sounds");
    if (_sounds isEqualTo []) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ALARM-SOUND: %1 has nothing to play here -- its CfgSFX class %2 lists no sound file found%3. The alarm is silent on this machine.",
            _class, configName _sfx, ["", format [" (looked for %1 as .wss, .ogg and .wav)", _missing]] select (_missing isNotEqualTo [])];
    };
    _cached = [_sounds, _weights];
    _cache set [_class, _cached];
    _cached
};

// Starts one cycle at a speaker: its sound id.
private _fnPlay = {
    params ["_speaker", "_sound"];
    _sound params ["_file", "_volume", "_pitch", "_reach"];
    // The player's own vehicle as the source (its position is given): an
    // empty source muffled the sound for a player in first person in a
    // vehicle (playSound3D, BI wiki).
    playSound3D [_file, vehicle player, false, getPosASL _speaker, _volume min 5, _pitch, _reach, 0, true]
};

private _camera = AGLToASL (positionCameraToWorld [0, 0, 0]);
{
    private _site = _x;
    if (!isNull _site) then {
        (_site getVariable ["AEGISM_alarmNow", []]) params ["", ["_class", ""], ["_speakers", []], ["_count", 0], ["_once", false]];
        // This machine's own playing: [the publish it's playing, a voice
        // per speaker -- [sound id (-1 none), next cycle no sooner than]].
        private _playing = _site getVariable "AEGISM_alarmPlaying";
        if (isNil "_playing") then {
            _playing = [0, []];
            _site setVariable ["AEGISM_alarmPlaying", _playing];
        };
        private _voices = _playing select 1;
        private _sounds = [[], []];
        if (_class != "") then { _sounds = [_class] call _fnSounds; };
        _sounds params ["_list", "_weights"];

        if (_count != (_playing select 0)) then {
            // A new state: the old sound stops at once.
            { if ((_x select 0) >= 0) then { stopSound (_x select 0); }; } forEach _voices;
            private _joined = (_playing select 0) == 0;
            _voices = _speakers apply { [-1, CBA_missionTime] };
            _playing set [0, _count];
            _playing set [1, _voices];
            // A one-shot: now, from the speakers in reach, and not again --
            // nor for a player joining after it (the first state this machine
            // sees can't be one otherwise: an All Clear follows an alarm).
            if (_once && {!_joined} && {_list isNotEqualTo []}) then {
                {
                    private _sound = _list selectRandomWeighted _weights;
                    if (!isNull _x && {(_sound select 3) <= 0 || {(_camera distance (getPosASL _x)) <= (_sound select 3)}}) then {
                        (_voices select _forEachIndex) set [0, [_x, _sound] call _fnPlay];
                    };
                } forEach _speakers;
            };
        };

        if (!_once && {_list isNotEqualTo []}) then {
            // Its reach: the longest of its sounds' (0 = no limit).
            private _unlimited = (_list findIf { (_x select 3) <= 0 }) != -1;
            private _reach = selectMax (_list apply { _x select 3 });
            {
                private _voice = _voices select _forEachIndex;
                _voice params ["_id", "_nextAt"];
                // Its last cycle has ended: the next after that sound's delay.
                if (_id >= 0 && {(soundParams _id) isEqualTo []}) then {
                    _id = -1;
                    _voice set [0, -1];
                    (_voice param [2, []]) params ["", "", "", "", ["_minDelay", 0], ["_midDelay", 0], ["_maxDelay", 0]];
                    _nextAt = CBA_missionTime + ([_minDelay, random [_minDelay, (_midDelay max _minDelay) min _maxDelay, _maxDelay]] select (_maxDelay > _minDelay));
                    _voice set [1, _nextAt];
                };
                if (!isNull _x) then {
                    if (_unlimited || {(_camera distance (getPosASL _x)) <= _reach}) then {
                        if (_id < 0 && {CBA_missionTime >= _nextAt}) then {
                            private _sound = _list selectRandomWeighted _weights;
                            _voice set [0, [_x, _sound] call _fnPlay];
                            _voice set [2, _sound];
                        };
                    } else {
                        // Out of reach: stopped, and started again the moment
                        // the camera is back within it.
                        if (_id >= 0) then {
                            stopSound _id;
                            _voice set [0, -1];
                        };
                        _voice set [1, CBA_missionTime];
                    };
                };
            } forEach _speakers;
        };
    };
} forEach _sites;
