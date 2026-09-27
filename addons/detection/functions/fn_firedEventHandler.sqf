/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_firedEventHandler

Description:
    CBA_fnc_addClassEventHandler "Fired" callback, registered globally
    against relevant munition-firing base classes (see aegism_detect_fnc_
    registerFiredHandler / XEH_preInit.sqf). Classifies the fired munition
    and, if its class is allowlisted by ANY currently-existing AEGIS-M
    System or Network, spawns a per-munition tracker
    (aegism_detect_fnc_trackMunition) via CBA_fnc_addPerFrameHandler.

    This is intentionally global rather than per-System: a single mission
    may fire many munitions per second, and per-System registration of the
    same class-EH repeatedly would multiply callbacks. The tracker itself
    (trackMunition) is what actually pushes the contact into each nearby
    System's/Network's pool.

Parameters:
    _unit - the firing unit or vehicle <OBJECT>
    _weapon - fired weapon classname <STRING>
    _muzzle - fired muzzle classname <STRING>
    _mode - fired weapon mode <STRING>
    _ammo - fired ammo classname <STRING>
    _magazine - fired magazine classname <STRING>
    _projectile - the spawned projectile object <OBJECT>

Returns:
    Nothing

Examples:
    (params of a CBA "Fired" class event handler) call aegism_detect_fnc_firedEventHandler;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["", "", "", "", "", "", "_projectile"];

if (isNull _projectile) exitWith {};

private _class = [_projectile] call aegism_detect_fnc_classifyTarget;
if (_class == "") exitWith {};

[_projectile, _class] call aegism_detect_fnc_trackMunition;
