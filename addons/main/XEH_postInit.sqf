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
    [{
        if (missionNamespace getVariable ["aegism_main_perfLog", true]) then { [] call aegism_fnc_perfLog; };
    }, 10, []] call CBA_fnc_addPerFrameHandler;

    [{
        params ["_args"];
        _args params ["_lastTick", "_lastTime"];
        private _now = diag_tickTime;
        _args set [0, _now];
        _args set [1, time];
        // Paused: game time didn't move. A pause would otherwise show up as
        // one enormous frame (the first after it), so a frame over a second
        // long in which game time moved less than a quarter of that isn't
        // counted either.
        private _tickDelta = _now - _lastTick;
        if (time == _lastTime || {_tickDelta > 1 && {(time - _lastTime) < _tickDelta / 4}}) exitWith {};
        private _frameMs = _tickDelta * 1000;
        PERF_INC(PERF_FRAMES);
        AEGISM_perfCounts set [PERF_FRAME_MAX_MS, (AEGISM_perfCounts select PERF_FRAME_MAX_MS) max _frameMs];
        if (_frameMs > PERF_SLOW_FRAME_MS) then { PERF_INC(PERF_SLOW_FRAMES); };
    }, 0, [diag_tickTime, time]] call CBA_fnc_addPerFrameHandler;
};
