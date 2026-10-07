// Surface strikes from a terminal (aegism_intercept_fnc_surfaceStrike).

// A missile is first sent for a point above its aim point by this much of
// its ground distance to it, and that point comes down onto the aim point
// as the missile closes: it climbs over what's between and comes down on
// it from above.
#define AEGISM_STRIKE_LOFT 0.35
// ...and by no more than this, m.
#define AEGISM_STRIKE_LOFT_MAX 3000
// Inside this much ground from the point there's no loft left: the missile
// is flown straight at it, so it isn't still being turned as it arrives. m.
#define AEGISM_STRIKE_TERMINAL 400
// The loft with DISTANCE m of ground still to cover.
#define AEGISM_STRIKE_LOFT_AT(DISTANCE) ((AEGISM_STRIKE_LOFT * (((DISTANCE) - AEGISM_STRIKE_TERMINAL) max 0)) min AEGISM_STRIKE_LOFT_MAX)
// A missile isn't fired at a point nearer than this, m.
#define AEGISM_STRIKE_MIN_RANGE 300
// Nor one with a warhead smaller than this, by its blast radius (its ammo's
// indirectHitRange), m: a shoulder-launched missile's is no use on the
// ground. In the game's config the Titan AA and the Stinger-sized 70 mm
// have 6, the RIM-116 10, the Zephyr 12, the RIM-162 13, the MIM-145 and
// S-750 30.
#define AEGISM_STRIKE_MIN_BLAST 8
// What a missile is told to fly at is kept this far above the ground, m: a
// seeker has to see it.
#define AEGISM_STRIKE_SEEKER_HEIGHT 1.5
// What a radar-seeker missile of a guidance mod chases is given this speed
// along the line to the missile, m/s: its seeker drops anything near the
// ground that isn't moving along that line (ACE: over 10 m/s).
#define AEGISM_STRIKE_SEEKER_SPEED 25
// ...and is shared with its side's datalink for this long, s.
#define AEGISM_STRIKE_SEEKER_SHARE 120
// A gun's line of fire counts as clear if the ground in the way is this
// near the point, m.
#define AEGISM_STRIKE_LOS_SLACK 15
// The barrel is on when it's this near where it has to point, deg.
#define AEGISM_STRIKE_ALIGN_LAUNCHER 3
#define AEGISM_STRIKE_ALIGN_GUN 0.3
// A weapon that isn't on and ready this long after its order: a launcher
// fires as it stands (its missile turns), a gun gives up. s.
#define AEGISM_STRIKE_AIM_TIMEOUT 8
// The fire command is taken as failed when no missile has left this long
// after it, s.
#define AEGISM_STRIKE_LAUNCH_WAIT 2
// A missile that has passed its point (it came within AEGISM_STRIKE_PASS m
// and is now going away): set off if it came within AEGISM_STRIKE_FUZE m;
// if not, AEGISM_STRIKE_OVERFLY s after.
#define AEGISM_STRIKE_PASS 300
#define AEGISM_STRIKE_FUZE 20
#define AEGISM_STRIKE_OVERFLY 2
