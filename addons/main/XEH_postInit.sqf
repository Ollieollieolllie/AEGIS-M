// How long the last frame took on the mission clock (AEGISM_frameDelta), for
// whatever moves by the frame: the stretch of path a round or a missile
// covered, the time a gun spent firing. diag_deltaTime is real time, and with
// the game fast-forwarded a round covers accTime times that in a frame.
// Registered before every other handler of AEGIS-M's, so each reads this
// frame's.
AEGISM_frameTime = CBA_missionTime;
[{
    AEGISM_frameDelta = (CBA_missionTime - AEGISM_frameTime) max 0;
    AEGISM_frameTime = CBA_missionTime;
}, 0, []] call CBA_fnc_addPerFrameHandler;

// Debug overlays: only where there's a screen to draw on. aegism_fnc_debugDraw
// (per frame) and aegism_fnc_debugHint (once a second) are no-ops while their
// settings are off.
if (hasInterface) then {
    [{
        [] call aegism_fnc_debugDraw;
    }, 0, []] call CBA_fnc_addPerFrameHandler;

    [{
        [] call aegism_fnc_debugHint;
    }, 1, []] call CBA_fnc_addPerFrameHandler;
};

#include "perf.hpp"

// PERF summary line (aegism_fnc_perfLog), server only: that's where the
// engagement pipeline runs. Every frame is timed for it -- the whole
// interval's average fps, worst frame and slow frames, rather than
// diag_fpsMin's last 16 frames at the moment the line is written.
if (isServer) then {
    // ACE's missile guidance: heavily recommended, not required. Said once
    // when it isn't what flies the missiles AEGIS-M fires -- not loaded, or
    // not guiding AI-fired shots (its default is to).
    private _aceMissing = ["ace_missileguidance", "ace_missile_sam", "ace_missile_manpad"] select { !isClass (configFile >> "CfgPatches" >> _x) };
    if (_aceMissing isNotEqualTo []) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ACE-GUIDANCE: ACE's %1 isn't loaded -- the game guides the missiles of its own launchers itself. AEGIS-M is built and tested with ACE's missile guidance, and it's heavily recommended: in its tests without it the RIM-116 reached 4 km instead of 5, the MIM-145 missed every rocket it met inside about 4 km, and a RIM-116 sent at a point on the ground came down some 20 m off it. A launcher whose missile locks on after launch (the MIM-145, S-750 and RIM-162) takes no surface strike without it.",
            _aceMissing joinString ", "];
    } else {
        if ((missionNamespace getVariable ["ace_missileguidance_enabled", 0]) < 2) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ACE-GUIDANCE: ace_missileguidance_enabled is %1 -- ACE is loaded but isn't guiding AI-fired missiles, so the game guides the missiles of AEGIS-M's launchers. Leave it at 2 (player and AI), ACE's default.",
                missionNamespace getVariable ["ace_missileguidance_enabled", "not set"]];
        };
    };

    [{
        if (missionNamespace getVariable ["aegism_main_perfLog", true]) then { [] call aegism_fnc_perfLog; };
    }, 10, []] call CBA_fnc_addPerFrameHandler;

    [{
        params ["_args"];
        _args params ["_lastTick", "_lastTime"];
        private _now = diag_tickTime;
        _args set [0, _now];
        _args set [1, CBA_missionTime];
        // Paused: game time didn't move. A pause would otherwise show up as
        // one enormous frame (the first after it), so a frame over a second
        // long in which game time moved less than a quarter of that isn't
        // counted either.
        private _tickDelta = _now - _lastTick;
        if (CBA_missionTime == _lastTime || {_tickDelta > 1 && {(CBA_missionTime - _lastTime) < _tickDelta / 4}}) exitWith {};
        private _frameMs = _tickDelta * 1000;
        PERF_INC(PERF_FRAMES);
        AEGISM_perfCounts set [PERF_FRAME_MAX_MS, (AEGISM_perfCounts select PERF_FRAME_MAX_MS) max _frameMs];
        if (_frameMs > PERF_SLOW_FRAME_MS) then { PERF_INC(PERF_SLOW_FRAMES); };
    }, 0, [diag_tickTime, CBA_missionTime]] call CBA_fnc_addPerFrameHandler;
};
