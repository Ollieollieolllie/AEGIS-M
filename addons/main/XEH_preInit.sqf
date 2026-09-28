[
    "aegism_main_scaleMode",
    "LIST",
    ["AEGIS-M Range Scale", "Whether real-world-sourced ranges are used as-is or compressed for Arma-sized maps"],
    ["AEGIS-M", "General"],
    [[0, 1, 2], ["Arma Scale (half real-world)", "Real World Scale", "Custom Multiplier"], 0],
    1
] call CBA_fnc_addSetting;

[
    "aegism_main_scaleCustomMultiplier",
    "SLIDER",
    ["Custom Range Multiplier", "Only used when Range Scale is set to Custom Multiplier"],
    ["AEGIS-M", "General"],
    [0.1, 3, 1, 2],
    1
] call CBA_fnc_addSetting;

// Client-side (isForce=0) and NOT saved to the server's exported settings --
// this is a per-player visualisation toggle, not a mission rule, so each
// machine watching the battery picks it independently. See aegism_fnc_debugDraw.
[
    "aegism_main_debugDraw",
    "CHECKBOX",
    ["Enable Debug 3D Draw", "Draws pooled contacts, claims, engagement envelopes, and each System's acquired target/LOS check. Client-side only, no effect on gameplay."],
    ["AEGIS-M", "Debug"],
    false,
    0
] call CBA_fnc_addSetting;
