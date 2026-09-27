/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_firedEventHandler

Description:
    CBA_fnc_addClassEventHandler "Fired" callback, registered globally
    (see XEH_preInit.sqf) rather than per-System: a single mission may fire
    many munitions per second, and per-System registration of the same
    class-EH repeatedly would multiply callbacks. Classifies the fired
    projectile and, if it's a real munition class (missile/rocket/bomb/
    artillery shell -- classifyTarget returns "" for anything else, e.g.
    plain bullets), spawns a per-munition tracker (aegism_detect_fnc_
    trackMunition) via CBA_fnc_addPerFrameHandler. The tracker itself is
    what actually pushes the contact into each nearby pool.

    Server-only (isServer): the tracker mutates AEGISM_pooledContacts,
    which only the server's engagement loop ever reads (see aegism_system_
    fnc_moduleInit) -- running this pipeline on clients too would waste
    CPU tracking munitions no local loop will ever act on.

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

if (!isServer) exitWith {};
if (isNull _projectile) exitWith {};

private _class = [_projectile] call aegism_detect_fnc_classifyTarget;
if (_class == "") exitWith {};

[_projectile, _class] call aegism_detect_fnc_trackMunition;
