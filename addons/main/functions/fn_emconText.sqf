/* ----------------------------------------------------------------------------
Function: aegism_fnc_emconText

Description:
    A radar vehicle's emission state for the debug overlays and the status
    board, from what aegism_system_fnc_emconUpdate records on it ("AEGISM_
    emcon") and whether its radar really is emitting (isVehicleRadarOn):

        EMITTING (amber) - lit by AEGIS-M: always on, cued, guiding missiles,
            holding after its last contact, or an intermittent search burst
        SILENT (grey) - silent until cued, or between intermittent bursts
        SHUT DOWN (red) - an anti-radiation missile is inbound on it
        AI: EMITTING / AI: SILENT - Radar Emission "AI decides": AEGIS-M
            leaves it to the AI, and this is what the AI chose

    The detail says why ("cued: ...", "fire control: ...", "silent in 6s").
    If the radar hasn't followed what AEGIS-M set within 2 s, the detail
    says so.

Parameters:
    _vehicle - the vehicle <OBJECT>

Returns:
    [label, detail, colour hex, colour RGBA], or ["", "", "", []] if AEGIS-M
    doesn't run its radar's emission <ARRAY>

Examples:
    ([_radar] call aegism_fnc_emconText) params ["_label", "_detail", "_hex", "_rgba"];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle"];

private _state = _vehicle getVariable "AEGISM_emcon";
if (isNil "_state") exitWith { ["", "", "", []] };

private _reason = _state getOrDefault ["reason", ""];
private _detail = _state getOrDefault ["detail", ""];
private _on = isVehicleRadarOn _vehicle;
private _silent = _reason in ["arm", "silent", "pause"];

if (_reason != "ai" && {CBA_missionTime - (_state getOrDefault ["since", CBA_missionTime]) > 2} && {_on == _silent}) then {
    _detail = _detail + (["; but its radar isn't on", "; but its radar is still on"] select _on);
};

switch (true) do {
    case (_reason == "arm"): { ["SHUT DOWN", _detail, "#EF5350", [0.94, 0.33, 0.31, 1]] };
    case (_reason == "ai"): {
        [["AI: SILENT", "AI: EMITTING"] select _on, _detail, ["#78909C", "#FFCA28"] select _on, [[0.47, 0.56, 0.61, 1], [1, 0.79, 0.16, 1]] select _on]
    };
    case (_silent): { ["SILENT", _detail, "#78909C", [0.47, 0.56, 0.61, 1]] };
    default { ["EMITTING", _detail, "#FFCA28", [1, 0.79, 0.16, 1]] };
}
