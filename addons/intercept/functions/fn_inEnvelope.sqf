/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_inEnvelope

Description:
    Whether a contact at a given slant range and height can be engaged by a
    specific weapon under the resolved doctrine. The effective envelope is
    the INTERSECTION of:
        the weapon's own real envelope - weaponInfo minRange/maxRange, read
            from config by aegism_system_fnc_discoverCapabilities, never
            scaled (the engine's own values)
        the doctrine envelope - real-world base metres, scaled by aegism_
            fnc_scaledRange:
              launcher: minRange / maxRange (maxRange 0 = no doctrine cap)
              ciws: ciwsMaxRange (0 = no doctrine cap); no doctrine minimum
            plus, for both, minAltitude/maxAltitude (height above ground;
            maxAltitude 0 = no cap)

    The launcher range settings never apply to a CIWS. A CIWS is the inner
    layer: a Site minimum meant to keep SAMs from wasting shots up close
    must not also switch the gun off exactly when a threat gets near (it
    used to -- a Cheetah released a helicopter at 492m against a 500m Site
    minimum). The gun's own config minimum still applies.

    CIWS only: the target must also be at least doctrine ciwsMinElevation
    degrees above the gun's horizon (aegism_intercept_fnc_ciwsBurst also
    holds fire whenever the barrel itself dips below it).

    Previously only the doctrine envelope existed and applied to every
    weapon alike: a CIWS couldn't engage inside the SAM-oriented 500m
    minimum, and a 16km SAM was capped at the doctrine's (halved) 4km.

    Single shared rule for aegism_intercept_fnc_assignEngagements and
    aegism_intercept_fnc_selectTarget, so networked and standalone Systems
    can never disagree about what's in range.

Parameters:
    _engagementSettings - resolved doctrine <HASHMAP>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _distance - slant range from the weapon to the contact, metres <NUMBER>
    _height - contact height above ground, metres <NUMBER>
    _role - "launcher" or "ciws" (optional, default "launcher") <STRING>
    _elevation - contact elevation above the weapon's horizon, degrees
        (optional, default 90; see aegism_intercept_fnc_elevationAngle) <NUMBER>

Returns:
    <BOOLEAN>

Examples:
    [_settings, _weaponInfo, 3200, 150, "launcher"] call aegism_intercept_fnc_inEnvelope;
    [_settings, _weaponInfo, 900, 60, "ciws", 3.8] call aegism_intercept_fnc_inEnvelope;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_engagementSettings", "_weaponInfo", "_distance", "_height", ["_role", "launcher"], ["_elevation", 90]];

if (_role == "ciws" && {_elevation < (_engagementSettings getOrDefault ["ciwsMinElevation", 5])}) exitWith { false };

([_engagementSettings, _weaponInfo, _role] call aegism_intercept_fnc_envelopeBounds) params ["_minRange", "_maxRange", "_minAltitude", "_maxAltitude"];

(_distance >= _minRange)
    && {_distance <= _maxRange}
    && {_height >= _minAltitude}
    && {_maxAltitude <= 0 || {_height <= _maxAltitude}}
