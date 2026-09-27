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
