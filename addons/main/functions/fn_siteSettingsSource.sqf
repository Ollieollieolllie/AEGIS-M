/* ----------------------------------------------------------------------------
Function: aegism_fnc_siteSettingsSource

Description:
    The Site whose settings apply to a Site's vehicles: the Site itself --
    or, while it's linked with others (aegism_network_fnc_linkSites) and one
    of them is ticked "Shared Site Coordinator", that one.
    Full notes: docs/functions/main.md

Parameters:
    _site - the Site logic <OBJECT>

Returns:
    The Site whose settings apply (_site itself when not overridden) <OBJECT>

Examples:
    [_site] call aegism_fnc_siteSettingsSource;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_site", objNull]];

if (isNull _site) exitWith { _site };
private _lead = _site getVariable ["AEGISM_linkLead", _site];
if (_lead != _site && {!isNull _lead} && {_lead getVariable ["sharedCoordinator", false]}) exitWith { _lead };
_site
