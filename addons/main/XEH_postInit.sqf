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

// PERF summary line (aegism_fnc_perfLog), server only: that's where the
// engagement pipeline runs.
if (isServer) then {
    [{
        if (missionNamespace getVariable ["aegism_main_perfLog", true]) then { [] call aegism_fnc_perfLog; };
    }, 10, []] call CBA_fnc_addPerFrameHandler;
};
