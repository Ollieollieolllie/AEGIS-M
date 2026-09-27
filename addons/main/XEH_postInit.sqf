// True per-frame (interval 0) debug 3D draw -- see aegism_fnc_debugDraw's
// own doc comment for what it draws and why it stays gameplay-inert. Not
// isServer-gated: drawIcon3D/drawLine3D are inherently per-client visuals,
// and aegism_fnc_debugDraw itself is a no-op the instant the
// "aegism_main_debugDraw" CBA setting is off, so this costs nothing on a
// dedicated server (which never has a 3D view to draw into anyway) or on
// any client leaving the setting at its default (false).
[{
    [] call aegism_fnc_debugDraw;
}, 0, []] call CBA_fnc_addPerFrameHandler;
