/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_interceptorPFH

Description:
    Proximity-fuse tracker for one of AEGIS-M's own fired interceptors,
    started by aegism_intercept_fnc_fireWeapon the instant it captures the
    real projectile object resulting from its own fire command.
    Necessary, not optional: Arma's damage system has no real notion of a
    projectile-vs-projectile hit at all -- a missile intercepting another
    missile has no meaningful hitbox/HandleDamage pipeline the way a unit or
    vehicle does, so relying on the game's own collision to ever register a
    kill against a munition target would simply never happen, no matter how
    accurate the interceptor's own guidance is.

    Every frame, computes the minimum distance between the interceptor's
    flight segment since the last tick and the target's current position
    (point-to-line-segment distance, not just point-to-point, so a fast
    interceptor passing very close between two ticks isn't missed just
    because neither individual sampled position happened to be within fuse
    range). Once that minimum distance is within the interceptor's own real
    fuse radius (its loaded ammo's indirectHitRange, via aegism_intercept_
    fnc_munitionSize -- never an invented number) OR the interceptor starts
    moving away from the target again (distance increasing tick-over-tick,
    meaning it already passed its closest approach and won't get any
    closer), the intercept is resolved:
        - The interceptor itself is always detonated in place (triggerAmmo)
          at the point of closest approach -- this is what actually produces
          real splash damage/explosion effects, exactly as if it had struck
          something, whether or not the target itself is destroyed by that
          splash.
        - If the target is ALSO classified as a munition (aegism_detect_fnc_
          classifyTarget in ["missile","rocket","bomb","artilleryShell"]),
          it is separately, explicitly detonated too (triggerAmmo) -- a
          munition target has no meaningful HandleDamage/hitpoints pipeline
          to be killed by the interceptor's splash the way a real vehicle
          would, so without this the interceptor could detonate right next
          to the incoming missile and it would fly on completely unharmed.
          A platform target (helicopter/plane/drone) is NOT force-detonated
          -- it's a real CfgVehicles object with real hitpoints, and the
          interceptor's own genuine splash damage against it (from
          triggerAmmo above) is the actual, honest outcome; a real
          armored/lucky aircraft surviving a near-miss is exactly correct
          behaviour, not a bug to route around.
        - A "hit" only counts as a proximity-fuse success (rather than a
          missed/overshot interceptor that just fizzles) if the closest
          approach was actually within fuse range -- an interceptor that
          never got close before running past its target is a genuine miss,
          same as it would be in real life, and is NOT force-detonated
          early just because it's diverging; it's simply left to the
          engine's own flight/fuel/self-destruct behaviour from there.

    Removes itself once the interceptor no longer exists, the target no
    longer exists, or a resolution (hit or overshoot) has been reached.

Parameters:
    _projectile - the fired interceptor's own projectile object <OBJECT>
    _target - the target it was fired at <OBJECT>

Returns:
    Nothing (intended to be wrapped in a CBA_fnc_addPerFrameHandler by the
    caller)

Examples:
    [_interceptorProjectile, _incomingMissile] call aegism_intercept_fnc_interceptorPFH;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_target"];

if (isNull _projectile || {isNull _target}) exitWith {};

private _fuseRange = [typeOf _projectile] call aegism_intercept_fnc_munitionSize;
// A fuse radius of 0 (plain kinetic ammo, e.g. a CIWS gun round fired at a
// munition target by mistake -- shouldn't normally happen since CIWS
// engagements rely on real collision/rate of fire, not this pipeline, but
// guarded here regardless) has nothing meaningful to proximity-fuse against;
// let it rely on real collision alone rather than force-detonating on
// point-blank contact only.
if (_fuseRange <= 0) exitWith {};

private _lastPosition = getPosASLVisual _projectile;
private _lastDistance = _lastPosition distance (getPosASLVisual _target);

[{
    params ["_args", "_pfhHandle"];
    _args params ["_projectile", "_target", "_fuseRange", "_lastPosition", "_lastDistance"];

    if (isNull _projectile || {isNull _target}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };

    private _currentPosition = getPosASLVisual _projectile;
    private _targetPosition = getPosASLVisual _target;

    // Closest point on the interceptor's flight segment (last tick's
    // position to this tick's) to the target's current position -- not
    // just comparing the two sampled points directly, since a fast
    // interceptor can pass well within fuse range BETWEEN two ticks
    // without either individual sample ever being that close.
    private _segment = _currentPosition vectorDiff _lastPosition;
    private _segmentLengthSqr = _segment vectorDotProduct _segment;
    private _minDistance = if (_segmentLengthSqr <= 0.001) then {
        _currentPosition distance _targetPosition
    } else {
        private _t = 0 max (1 min (((_targetPosition vectorDiff _lastPosition) vectorDotProduct _segment) / _segmentLengthSqr));
        (_lastPosition vectorAdd (_segment vectorMultiply _t)) distance _targetPosition
    };

    private _overshot = _minDistance > _lastDistance;

    if (_minDistance <= _fuseRange || _overshot) then {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;

        if (_minDistance <= _fuseRange) then {
            triggerAmmo _projectile;

            // A munition target has no real HandleDamage/hitpoints pipeline
            // for the interceptor's own splash (above) to actually kill it
            // through -- explicitly detonate it too. A platform target is
            // deliberately left alone here: its own real hitpoints and the
            // interceptor's genuine splash damage decide its fate honestly,
            // rather than this pipeline guaranteeing a kill it didn't earn.
            private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;
            if (_targetClass in ["missile", "rocket", "bomb", "artilleryShell"]) then {
                triggerAmmo _target;
            };
        };
        // else: genuinely overshot without ever closing to fuse range --
        // a real miss, left to the interceptor's own remaining flight/self-
        // destruct behaviour rather than forced to detonate on a miss.
    } else {
        _args set [3, _currentPosition];
        _args set [4, _minDistance];
    };
}, 0, [_projectile, _target, _fuseRange, _lastPosition, _lastDistance]] call CBA_fnc_addPerFrameHandler;
