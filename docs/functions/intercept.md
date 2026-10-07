# intercept: function notes

What each function does and why, in full: the descriptions that used to sit in each
function's header, moved out of the code on 2026-10-07. Each header keeps a short
description with its parameters, return value and examples. Change a function's
behaviour and its notes here change with it. This folder is not packed into the mod.

## aegism_intercept_fnc_aimWeapon

`addons/intercept/functions/fn_aimWeapon.sqf`

```text
Full aim solve for one System weapon: slews its turret toward the
intercept point (lockCameraTo on that turret, see aegism_intercept_fnc_
lockTurret) and reports whether the barrel is aligned closely enough to
fire. Each lock stamps the turret's "lockAt" (aegism_intercept_fnc_
turretState); aegism_intercept_fnc_engagementLoop hands the turret back
to its crew once that goes stale.

Launchers are solved here every engagement tick from the moment a target
is assigned (including the crew reaction window). A CIWS gun is solved
here by its per-frame tracker (aegism_intercept_fnc_ciwsTrack) every
AEGISM_CIWS_SOLVE_INTERVAL s and steered in between from the "solve" this
stores.

Aim point:
    ciws - where the unguided round meets the target, raised for drop
        (aegism_intercept_fnc_computeLeadPoint)
    launcher - the closest direction the turret can reach to where the
        missile (on its flight simulated from config) meets the target
        (aegism_intercept_fnc_launchSolution): the intercept itself, so
        it doesn't leave the rail and turn hard, or the turret's limit
When there is no feasible intercept (the target is receding faster than
the round can close, or the meeting point is beyond the weapon's reach)
the turret tracks the target itself and the weapon is not aligned.

Alignment:
    ciws - aegism_intercept_fnc_ciwsGate: the intercept inside the gun's
        open-fire range (aegism_intercept_fnc_openFireRange: where one
        burst still hits with doctrine ciwsOpenFireChance, from the gun's
        measured accuracy, the round's flight and reach, and the hit
        radius), and the barrel's error at the intercept
        within the target's size to the gun (aegism_intercept_fnc_
        targetHitRadius: an aircraft's half-size; a munition's body as
        seen along the line of fire, plus the round's own blast or
        proximity radius) plus the gun's own spread there (the current
        fire mode's CfgWeapons dispersion), with the last-ditch rule.
        An unguided munition's path is projected on gravity alone --
        exact for artillery (no drag), and the same projection aegism_
        intercept_fnc_canEngage judges reach with.
    launcher - by the way to launch that kills soonest (aegism_
        intercept_fnc_launchSolution):
        "now" / "fixed" - at once, along the barrel as it points (a
            vertical launch cell; a turret still swinging round, only
            when waiting for it would be too late to intercept)
        "onBore" / "slew" - barrel within AEGISM_AIM_ON_TARGET degrees
            of the launch direction, OR the turret has stopped closing
            on it (the angle hasn't shrunk for AEGISM_AIM_SETTLE_TICKS
            checks in a row: trailing a fast-moving lead point, or
            stopped at its limit), with the barrel's own angle off the
            intercept still inside the off-bore limit for the way it
            launches (the missile's post-launch cone, and Max Off-Bore
            Launch While Swinging or At Turret Limit: aegism_intercept_
            fnc_launchSolution)
        An off-bore launch also needs its first leg clear -- to where
        the missile's turn ends, or (its turn not known yet) its own
        arming distance (CfgAmmo fuseDistance) straight along the
        barrel -- traced at most every AEGISM_LAUNCH_PATH_REUSE s
        (LAUNCH-PATH-BLOCKED). The plan is kept as the turret's
        "launchPlan" for the FIRE log.
Barrel direction: aegism_intercept_fnc_barrelDirection.

CIWS aim carries the gun's own spotting correction for this target class
(turret state "corrections", [lead time s, elevation rad], aegism_
intercept_fnc_ciwsSpot). The prediction each solve uses is recorded as
the turret's "track" [time, position, velocity, acceleration] (and its
flight time, "trackTof") for aegism_intercept_fnc_onSystemFired to hand
each round.

Shared turrets: a vehicle whose launcher and gun sit on the same turret
(e.g. the Cheetah) would have both engagement loops issuing competing
aim orders. The CIWS loop owns the turret while it is actively aiming; a
launcher on the same turret skips its own lock for AEGISM_CIWS_AIM_
OWNERSHIP seconds and only checks alignment.

Records [angle, tolerance, time, target, feasible, aligned, aimPoint] as
the turret's "aim_<role>" -- per turret, so two guns on one vehicle each
gate their own bursts (one record per role used to be shared by every
turret: a second gun read the first's alignment and never fired).

2026-10-07: a launcher's own aim projects an unguided round on gravity
(_ballistic) instead of its sampled acceleration, so the plan, the
coordinator's check and the firing decision agree. On the sample, the
first tick on each new rocket had no acceleration yet and logged
NO-SOLUTION ("missile cannot catch it") before firing a tick or two later.
```

## aegism_intercept_fnc_ammoBurst

`addons/intercept/functions/fn_ammoBurst.sqf`

```text
How long a gun round really flies, and how it ends, from its config --
for any mod's ammo:

A round that is a submunition carrier (CfgAmmo simulation
"shotSubmunitions", like vanilla's SubmunitionBullet) turns into its
submunition triggerTime s after it's fired. If that submunition explodes
at once (CfgAmmo explosionTime set), the round is an airburst: its
flight ends there, in a blast of the submunition's radius (its
indirectHitRange -- the smallest, when it's one of several). POOK's
20, 23 and 30 mm AA rounds become 8-12 m airbursts 1 s after firing, so
their guns reached ~1 km while AEGIS-M took their timeToLive (4-11 s)
as their flight. If the submunition flies on instead (vanilla's minigun
rounds swap to another bullet after 0.1 s), the round's flight goes on
for the submunition's own lifetime.

The round's own timeToLive still ends it first if it's shorter.

Cached per ammo class ("AEGISM_cacheAmmoBurst").
```

## aegism_intercept_fnc_applyCrewModulation

`addons/intercept/functions/fn_applyCrewModulation.sqf`

```text
Derives engagement timing/reliability modifiers from a resolved
Crew/Personality data (skillTier x temperament, from AEGISM_Module_
Site's own Attributes), per the AEGIS-M
README's description of Crew as modulating "the linked doctrine's
timing and reliability rather than owning its own numbers" -- the
engagement loop and fire/guidance functions never read skillTier or
temperament directly, they call this once and use the returned
modifiers.

skillTier sets the baseline reaction time (seconds of hesitation after
a target is first acquired, before the first shot) and baseline
reliability (probability the crew gets a clean fire command off on a
given cycle at all, see aegism_intercept_fnc_fireWeapon -- the actual
hit-or-miss outcome from there is the game's own weapon/AI simulation,
not anything AEGIS-M fakes). temperament then scales both, plus how
eagerly the crew re-engages within a salvo (shotIntervalMult, applied
to the doctrine's minShotInterval): aggressive/nervous crews shoot
faster but sloppier, cautious crews are slower but steadier, standard
is a neutral 1x baseline.

Automated systems -- crewed by UAV AI (unitIsUAV: Phalanx, RAM, MIM-145,
radar units) -- have no human in the loop, so by default none of this
applies to them: no reaction delay, every fire cycle goes out (no
FIRE-SKIP), and the interval isn't scaled. The crew setting "Crew Skill
on Automated Systems" (crewOnAutomated, off by default) applies the full
crew model to them as well.
```

## aegism_intercept_fnc_assignEngagements

`addons/intercept/functions/fn_assignEngagements.sqf`

```text
Site-level engagement coordinator, run once per Site every 0.5s on the
server -- at once for a munition close to impact that has just come into
the picture (aegism_network_fnc_moduleInit). Decides, for every pooled contact, which member System's weapon
engages it; member engagement loops only execute these assignments.
Sites linked through a shared vehicle (aegism_network_fnc_linkSites) are
coordinated once, by their lead, across every vehicle of the group
("AEGISM_groupMembers"), from the pool and ledger they share.

1. Prune the Site pool by expiry (aegism_detect_fnc_pruneStaleContacts).
   Sensors never delete from the shared pool directly any more -- they
   used to, which deleted assignments every second and restarted the
   crew reaction timer so launchers never fired.

2. Review existing assignments (AEGISM_claims) and keep each unless:
     - its System is dead, or the contact left the pool
     - the weapon can no longer usefully engage it (aegism_intercept_
       fnc_canEngage: envelope, and a feasible intercept -- a gun is
       released from a jet flying away that its rounds can't catch).
       Not asked of a launcher whose salvo is away: its missiles are
       flying, and another launcher shouldn't fire on top of them
     - launcher MISSED: salvo spent, AEGISM_INTERCEPTOR_SETTLE seconds
       since the last shot, and none of its interceptors are still in
       flight. This is judged from the real missiles (captured by
       aegism_intercept_fnc_onSystemFired), not a fixed timer -- the old
       8s timer called a long-range shot "failed" while its missile was
       still flying and fired a second one at the same target. Only
       once a missile has actually left: a fire command that fired
       nothing (FIRE-FAILED) is taken back and the launcher holds; if
       none ever leaves, it's released after AEGISM_NO_LAUNCH_TIMEOUT s
     - CIWS idle: hasn't fired for AEGISM_CIWS_IDLE_GRACE seconds
     - launcher crew failed to fire (reliability roll, flagged by
       aegism_intercept_fnc_engagementLoop): the contact is re-tasked,
       and that launcher can't take it back until its lost fire cycle
       is over (the contact's "avoid" list), so another weapon tries
     - launcher out of missiles before firing at it
     - never fired within AEGISM_NEVER_FIRED_TIMEOUT seconds of being
       assigned (turret can't bear, LOS never clears) -- frees the
       contact for a better-placed weapon instead of holding it forever.
       A launcher's claim counts from when it reached the front of the
       launcher's queue ("frontSince", aegism_intercept_fnc_
       engagementLoop), not from when it was queued: a deep queue
       released claims as "never fired" while they waited their turn,
       and they were handed straight back with the crew's reaction
       restarted (17 times in one POOK test, 2026-10-06). Nor does it
       count while the launcher itself isn't ready (between missiles, a
       lost fire cycle, its weapon loading): the clock restarts until it
       is

3. Assign free roles, contacts in Target Priority order -- except a
   contact only passive radar hears (aegism_fnc_hasTrack), which only
   cues the Site's radars. For each
   contact, a launcher and a CIWS weapon are chosen independently (CIWS
   runs in parallel with a launcher unless that gun's "CIWS last
   resort" is set). A candidate weapon must:
     - have live ammo
     - engage that target class (its vehicle's own settings)
     - have the contact inside its envelope
     - not be on a TURRET already committed to a DIFFERENT contact
       (two weapons sharing a turret, e.g. the Cheetah's gun and
       missiles, used to be assigned to different targets and fight
       over the turret's aim forever)
     - for a launcher: a missile left for it once the claims ahead of
       it in that launcher's queue are served (a launcher is never
       queued past its last missile)
     - not be held in LAYERED RESERVE (below)
   Best fit: see _fnPickWeapon. A launcher is only given a munition it
   can kill in time (LATE otherwise). For one that isn't ready yet --
   cooling down, or with claims ahead on its queue -- that's judged
   from when it will be (_fnPlanShot, the reserve plan's own question):
   a shot from then on that meets the munition inside its envelope
   before impact. Not its wait plus the flight of a shot fired now (far
   longer than the flight will be once the munition has closed), and
   not where the munition is now (inside its minimum range, or too
   steep, by the time it can fire). So a slow launcher's place goes to
   the first munition due that it can actually kill. A queued one that
   falls later than AEGISM_LATE_MARGIN is handed to a launcher that can
   make it (HANDOFF) or released. A launcher's queue is soonest impact first,
   except that the claim its turret is already working keeps its place
   unless one AEGISM_WORKING_LEAD s more urgent comes (_fnQueuePlace).
   A gun is only given a munition it has its Minimum Firing Window on
   (CIWS setting; aegism_intercept_fnc_canEngage): after its crew's
   reaction, its barrel's swing and the rounds' flight, that long left
   to fire before impact, with the barrel still able to follow it. One
   it has less on is a last-ditch shot: a gun still free once every
   contact has been served takes the one it has the longest window on
   (the last-ditch pass), and drops it as soon as a contact it has its
   full window on comes. Given rockets 2-5 s from impact one after
   another, a Cheetah hit 2 of 21 and swung away from the rest of the
   volley.

A gun beside the launchers (CIWS setting Engagement Mode, each gun's
own): "overlap", it takes what it can reach, a launcher on it or not;
"lastResort", it holds while a launcher has the contact, unless that is
deep inside its reach; "planned", it and the launchers never share one:
it's planned munitions of its own (_gunPlanned) -- one it's free for as
that munition comes into its reach, and then its time on it before the
next -- which no launcher is given, and it takes nothing a launcher has.

Layered reserve (munitions only): every cycle the coordinator plays
forward each launcher tier, shortest reach first -- each launcher's own
queue, cooldown, measured shot spacing and missiles left, and the moment
each incoming munition will enter its envelope (projected on its
ballistic path) -- to see which munitions the cheaper tiers will kill in
time. A longer-reach launcher (e.g. a Patriot next to RAM launchers)
holds its missiles for those, and steps in only for the munitions the
cheaper tiers can't take in time: when the volume saturates them -- they
have no missile or no time left for it. It stops holding for one the
cheaper tier was planned to fire at AEGISM_RESERVE_GRACE s ago (by the
plan's latest estimate) that none of its launchers has, or whose shot
missed (RESERVE-MISSED): a plan the tier can't carry out -- a rocket
coming down too steep for the RAMs -- held every Patriot back until it
was too late. And it doesn't hold for one that even a free launcher of
the cheaper tier could only kill too late for the longer-reach launchers
to have a second shot (RESERVE-RELEASED); a kill that's only that late
because of the cheaper tier's queue stays with it.

Threat re-assessment: after AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD
launcher attempts on a still-living contact, further launcher shots only
go to it if no unassigned contact outranks it (aegism_intercept_fnc_
threatValue).

Per-vehicle settings: everything decided per WEAPON -- envelope, which
target classes it engages, missiles per target, CIWS last resort -- uses
that weapon's own vehicle's resolved settings ("AEGISM_resolved
EngagementSettings": the Site's, plus any per-vehicle overrides, see
aegism_system_fnc_applyOverrides). The Site's own doctrine decides the
rest: engagement ORDER (Target Priority -- contacts are served
highest-priority first, so when threats outnumber free weapons the
priority rule decides who gets them; it used to be HashMap order, and
the setting did nothing for a Site) and which classes the Site pool
holds at all (the Site's allowlist plus any class a member vehicle's
override adds, "AEGISM_contactAllowlist", read by aegism_detect_fnc_
addContact).

Writes AEGISM_claims: contact key (aegism_fnc_contactKey) -> array of
assignment records (HashMap: target, system, role, weaponInfo,
assignedAt, lastShotAt, roundsFired, interceptors), and
AEGISM_withheldCiws (diagnostic, for debugDraw). Publishes each member's
own records on the member itself ("AEGISM_assigned", role -> records,
soonest impact first), so its engagement loop never scans or sorts the
Site's claims. Consumers use the record's own "target" object.

Cost (it runs in one frame, so it's what shows as a server spike under a
salvo):
    - the layered-reserve plan's per-munition, per-launcher question
      (when can this launcher first make a shot that lands in time) is
      worked out step by step only as far as the first shot, each step
      cached ("AEGISM_planCache") while the munition keeps to its
      predicted path, and skipped while every munition already has a
      launcher (solving the whole path up front was the ~100 ms frame
      when a salvo came into view)
    - claims are indexed per turret, so the conflict and queue checks
      read one turret's claims (they scanned the whole Site's for every
      candidate weapon of every contact)
    - each launcher's timing is worked out once per run
    - a launcher whose salvo is away isn't re-judged (its missiles are
      flying; it's released once they're gone)
    - a launcher a contact is plainly beyond is skipped before the full
      engageability check; a gun's own check rules out far contacts on
      its flight time to its reach (aegism_intercept_fnc_canEngage)
    - so is a launcher whose queue and reaction alone run past a
      munition's impact (it can't be in time): the full check (its
      intercept solves) was most of the 18-27 ms runs under a rocket
      ripple, re-run for every launcher on every unassigned rocket
    - a question already answered isn't worked out again: the plan
      remembers the stretch of each munition's path with no shot in it
      (_fnPlanShot); a launcher's claim waiting its turn is judged by its
      planned shot, not also by a shot fired now; a gun too far to reach
      a contact is ruled out on one distance (_fnGunBeyond). Fitted to
      two tests' PERF lines (2026-10-06), re-reading cached plans was
      about half the coordinator's time under a salvo, the full
      engageability checks about a third, and rebuilding plans the rest
    - a munition further than AEGISM_URGENT_TTI s from impact isn't
      looked at for launchers on every run (_asleep): its next look is
      shortly before the reserve plan has a launcher firing at it, or
      AEGISM_FAR_INTERVAL s on, whichever is sooner -- at once if it
      loses its launcher -- and meanwhile it keeps the launcher slot
      the reserve plan last gave it. A long-range salvo's rockets were
      in the air for 65 s and given to a short-range launcher 26 s from
      impact; planning every one against every launcher on every run
      until then was 20 ms a run with 48 rockets and 11 launchers
      (2026-10-06)
    - a run that has worked out AEGISM_PLAN_STEPS new steps of launcher
      shots puts off the looks that can wait (_mustLook has those that
      can't): the munition keeps its slot for this run as if asleep,
      and its shots are worked out in the frames before the next
      (aegism_intercept_fnc_planAhead), which then finds them ready. A
      munition is looked at whole or not at all: nothing is ever decided
      on a shot half worked out. (The first way of spreading the work
      cut a run's questions short and decided nothing for those
      munitions, nor for any later to impact, until they were answered:
      under a salvo the newest rockets waited 15-20 s for their first
      look, and four Patriots stepped in 10 s later than they had,
      2026-10-06.)
Each run's time, and its parts', is counted for the PERF line
(aegism_fnc_perfLog).

2026-10-07, orders from a terminal's Interception page
(aegism_network_fnc_terminalOrder):
- "AEGISM_manualOrders" on the coordinating Site. After the review, an
  order not yet placed becomes a claim record marked "manual" with
  "salvo" 1 -- or, if its weapon already has a claim on that contact, one
  more missile on it ("salvo" = what it has fired or was to fire, + 1;
  the Site's own unfired claim just becomes the order's). "salvo" on a
  record replaces the vehicle's Missiles per Target for it, here and in
  aegism_intercept_fnc_engagementLoop.
- A manual record in the review: its class needn't be on any allowlist;
  no shot just now doesn't release it, only none for
  AEGISM_NEVER_FIRED_TIMEOUT (15 s) since it was ordered or last fired; a
  lost crew fire cycle doesn't release it (it fires at the next); it isn't
  offered to other launchers (the hand-off). When it is released, for
  whatever reason, its order goes too and the reason is kept for the
  terminals ("AEGISM_manualLog", RPT MANUAL).
- Published at the front of its launcher's queue (AEGISM_MANUAL_PLACE).
- A contact the Site doesn't hold itself is put in the pool by the order,
  "manualOnly": left out of the assign loop and of the idle turret cue,
  and kept fresh only while a member's "AEGISM_otherTracks" still lists
  it, so it's pruned 3 s after the sensors lose it or the order ends.
  aegism_detect_fnc_addContact clears "manualOnly" if the Site's own
  detection ever adds it (a friendly turned hostile).
- Automation ("AEGISM_automation" on a Site or a vehicle, false = orders
  only): those vehicles' weapons are taken out of _allWeapons after the
  orders are placed, and their unfired claims (and guns' claims) are
  released in the review. With no weapon left the run ends there: the
  end-of-run publish became _fnPublish so that exit can call it too.
- Not covered: a vehicle with no Site (no coordinator, so no orders);
  the launchers' ETA sums still place a manual claim by its time to
  impact, not at the front, so another contact's "fires in" can be one
  missile out while an order is on that launcher.
```

## aegism_intercept_fnc_barrelDirection

`addons/intercept/functions/fn_barrelDirection.sqf`

```text
World-space unit vector a System weapon's barrel (or missile rail)
currently points along.

weaponDirection is tried first. It looks the weapon up by NAME, and for
some turrets it returns [0,0,0] -- e.g. the POOK C-RAM's second turret
(LF_Turret, pook_SAM_M2HB): every alignment check against a zero vector
reads exactly 90 degrees, so that gun logged "barrel 90 deg off" forever
and never fired. The fallback reads the specific turret's own barrel
memory points (gunBeg/gunEnd, or missileBeg/missileEnd for a launcher;
names cached by aegism_intercept_fnc_turretConfig) -- beginning (muzzle)
minus end (breech) -- which follow the turret's animation.
```

## aegism_intercept_fnc_bodyPass

`addons/intercept/functions/fn_bodyPass.sqf`

```text
How close a round came to a munition's body over one frame: the least
distance between the round's path and the munition's box (aegism_
intercept_fnc_targetBody) -- 0 if it went through it. The fuses compare
it with the round's own radius (its blast, CfgAmmo indirectHitRange, or
its proximity fuse, proximityExplosionDistance): aegism_intercept_fnc_
ciwsRounds, aegism_intercept_fnc_interceptorPFH.

The path is relative: both move (at a 1500 m/s closing speed that's
~25 m a frame), so it's the round's position from the munition's model
origin, last frame and this, turned into the munition's own axes as it
points now.

A path that doesn't come within the box's sphere plus the radius is
turned away at once (most rounds, most frames); otherwise the distance
to the box along it -- a convex function of how far along -- is found by
ternary search.
```

## aegism_intercept_fnc_canEngage

`addons/intercept/functions/fn_canEngage.sqf`

```text
Whether one weapon can usefully engage one target right now -- the one
rule the Site coordinator (assign AND release, aegism_intercept_fnc_
assignEngagements) and standalone target selection (aegism_intercept_
fnc_selectTarget) share.

    launcher - a missile can be put onto it (aegism_intercept_fnc_
        launchSolution): it can catch it on its simulated flight,
        launched along the closest direction the turret can reach --
        straight, or off-bore within the missile's post-launch cone and
        turn (a vertical launch cell, a turret at its limit) -- and the
        point where it MEETS the target is inside the missile's envelope
        (lock range, doctrine limits: aegism_intercept_fnc_inEnvelope's
        rule). Not the target's current position: an incoming munition
        is launched at while still beyond the missile's reach, so the
        missile meets it out near the edge of it instead of well inside
        -- and there's time left for a second shot. Against an incoming
        munition, the turret's swing plus the missile's flight must
        beat its impact -- or, only when that's too late, a launch now,
        before the turret is round.
    ciws - a feasible intercept exists, and the INTERCEPT point (where
        the rounds would meet the target) is inside the gun's envelope
        -- its range, the target's height THERE, and the minimum
        elevation of the barrel aimed there -- within the turret's own
        elevation limits, and reachable in time: the barrel's swing onto
        it (aegism_intercept_fnc_turretSlewTime) or the crew's reaction,
        whichever is longer, plus the rounds' flight before the target
        comes down. Like a missile, it's judged where the rounds MEET
        the target: a gun opens fire so its rounds arrive just as the
        target comes into reach (aegism_intercept_fnc_computeLeadPoint).
        Against an incoming munition it also reports its FIRING WINDOW
        -- how long it can fire before the last rounds that still arrive
        before impact -- and whether that's short of the CIWS setting
        "Minimum Firing Window" (3 s by default), or the barrel can't
        follow the target that long (past a turret limit, or out of
        reach). A gun assigned rockets 2-5 s from impact hit 2 of 21;
        6-9 s, 14 of 19. The Site coordinator only gives a gun such a
        last-ditch shot when it has nothing better (aegism_intercept_
        fnc_assignEngagements).

Judging a gun at the intercept point is what stops it spending ammunition
on a jet flying away from it: the jet may be 2000m away "inside" a 2500m
gun, but the rounds would only catch it far beyond 2500m (or never), so
it is released instead of claimed forever.

A gun is also CUED onto a target that isn't in its reach yet but will
be within its "Cue Before In Range" time (CIWS setting, 5 s by default):
the same checks for a burst opened that many seconds from now, on the
target projected to then. Assigned that early, its crew has reacted and
its barrel is on the target by the time it can fire (it holds fire,
"cued", until then).

Both first rule out, without solving anything, a target too far to
reach at all: the intercept has to be within the weapon's range, and the
target can't cover more than speed x t + g t^2 / 2 in the round's or
missile's flight time t to that range (or its lifetime, CfgAmmo
timeToLive, if shorter; aegism_intercept_fnc_missileFlightTime for a
missile). The coordinator checks every free contact against every
weapon, most of them far out of reach.

No acceleration sampling, so calling this has no side effects: the
intercept is estimated from velocity -- plus gravity for a gun against
an unguided round, whose path that is.

2026-10-07: the launcher check projects an unguided round (artilleryShell,
rocket, bomb) on gravity, as the plan does. On velocity alone a rocket
coming down from 5 km was met about 450 m further out on paper, and a free
launcher was given it about 3.5 s late (first RAM kills 4.5 km of 5; 4.9 km
after the change, 00:41 RPT).
```

## aegism_intercept_fnc_ciwsBurst

`addons/intercept/functions/fn_ciwsBurst.sqf`

```text
Holds a CIWS gun's trigger for one sustained burst. Every frame the
weapon has cycled (weaponState roundReloadPhase back to 0) and the
turret is on its aim point, it fires again, so the gun runs at its own
config rate of fire (reloadTime) for the whole burst.

Each shot is the same command BIS_fnc_fire issues for a vehicle turret
-- the "UseMagazine" action with the loaded magazine's id -- given
directly: BIS_fnc_fire looks the magazine up in the vehicle's whole
magazine list and routes the action through remoteExec on every call,
~53 times a second for a Phalanx. The magazine id is found once and
reused until the magazine changes (a new one shows a higher round
count); a turret on another machine gets the action sent to its owner,
as BIS_fnc_fire does.

Why sustained: BIS_fnc_fire is ONE trigger pull in the turret's selected
fire mode. A Cheetah gunner's selected mode is its player mode "manual"
(burst = 2), so one call per engagement tick gave 2-round pops about a
second apart instead of sustained fire.

Fires only while the gun's aim -- refreshed every frame by its tracker,
aegism_intercept_fnc_ciwsTrack -- is for THIS target, fresh, and aligned
(aegism_intercept_fnc_ciwsGate, per turret): a turret that falls off the
lead point mid-burst holds fire until it's back on. It also holds fire
while the barrel itself (aegism_intercept_fnc_barrelDirection, world
space) is below doctrine ciwsMinElevation, so a target dipping low
mid-burst never pulls rounds into the ground or friendly positions; the
time held is reported in BURST-END.

Once the burst's last round has had its lifetime (CfgAmmo timeToLive)
to pass the target, a SPOTTING line reports where this burst's measured
rounds went and the aim correction the gun now carries for that target
class (aegism_intercept_fnc_ciwsSpot).

The burst ends at its deadline -- which the engagement loop pulls in if
the target changes or LOS is lost -- or when the target dies, ammo runs
out, or the engagement loop stops working the assignment (the turret's
"tickAt" goes stale: the engagement was released).

Turret state "burst": [endsAt, target, burstId]. endsAt is the planned
deadline while the burst runs and is rewritten to the actual end time
when it stops, so the engagement loop's pause between bursts counts from
it. burstId makes each handler exit as soon as a newer burst owns the
turret.
```

## aegism_intercept_fnc_ciwsGate

`addons/intercept/functions/fn_ciwsGate.sqf`

```text
A CIWS gun's fire gate for one aim: whether a round fired now would pass
close enough to hit, recorded as the turret's "aim_ciws" [angle,
tolerance, time, target, feasible, aligned, aimPoint, inRange] -- what
its burst (aegism_intercept_fnc_ciwsBurst) checks every frame. Run on
every full solve (aegism_intercept_fnc_aimWeapon) and every steered
frame in between (aegism_intercept_fnc_ciwsTrack).

    in range - the intercept inside the gun's open-fire range, and not
        inside the round's arming distance against a munition (aegism_
        intercept_fnc_openFireRange). Outside it the gun keeps tracking
        but never fires, last-ditch or not.
    aligned - in range, a feasible intercept and the barrel within
        tolerance: the target's half-size plus the gun's dispersion, as
        an angle at the intercept distance
    LAST-DITCH - once the target is due to impact within the gun's own
        longest burst (doctrine ciwsBurstMax), it also fires as soon as
        the turret has settled -- stopped closing on the aim point for
        AEGISM_AIM_SETTLE_TICKS engagement ticks -- wherever that is,
        as long as it's within AEGISM_LAST_DITCH_MAX_GATES times the
        gate: there's no later, better shot, and holding fire guarantees
        the round lands. A Praetorian followed a shell to the ground 0.3
        degrees off a 0.28-degree gate (1.1x); the cap stops what came
        after -- the last shell of a salvo took 113 rounds at 6.3
        degrees (22x the gate), with no chance of a hit. Logged once per
        target either way (LAST-DITCH / LAST-DITCH-HOLD).
```

## aegism_intercept_fnc_ciwsRounds

`addons/intercept/functions/fn_ciwsRounds.sqf`

```text
Tracks a CIWS gun's rounds in flight: proximity fuse against a munition
target, and spotting against the target's predicted track. One handler
per gun turret works through every round it has in the air (turret state
"rounds"); it used to be one per-frame handler per ROUND -- a Phalanx
firing ~53 rounds a second had 20-100 of them running at once.

A round is only examined while it can be near the target: from 80% of
its predicted flight time to the intercept (the aim solve's own, turret
state "trackTof") onward. Before that it's still on its way out and
nothing is done with it. (From half the flight time, a round was
examined ~100 frames on average: most of the round tracker's cost.)

Fuse (munition targets): the engine has no projectile-vs-projectile
collision, so a round passing through an incoming shell does nothing
unless scripted. A hit is the round's path, frame to frame, coming
within the round's own radius -- its blast (CfgAmmo indirectHitRange) or
its proximity fuse (proximityExplosionDistance), whichever is larger; 0
for a ball round -- of the target's body, its box (aegism_intercept_fnc_
bodyPass). It used to be within the box's sphere: 6.19 m round vanilla's
230 mm rocket, so a .50 with no blast at all scored kills 4-5 m off it.
The path is RELATIVE motion between frames (both move; at a 1500 m/s
closing speed that's ~25m per frame). No detonation before the round's
own CfgAmmo fuseDistance. On a hit: aegism_intercept_fnc_interceptHit. A
round stops being fuzed once it has closed on the target and started
opening (it can't come back), or the target is gone.

An airburst round (aegism_intercept_fnc_ammoBurst: POOK's 20-30 mm)
also kills where it bursts, if the target's body is within the burst's
blast then (SubmunitionCreated).

Spotting (every AEGISM_SPOT_EVERY-th round, aegism_intercept_fnc_
onSystemFired): the round's closest pass to the track the target was
PREDICTED to fly when it was fired goes to aegism_intercept_fnc_
ciwsSpot. Measuring against the prediction keeps the gun's own errors
(turret lag, flight time, drop) apart from the target's evasion. A round
that ends before it passes (it hit, or detonated) has its pass
extrapolated from its last motion relative to the predicted target.
Gun rounds against aircraft are tracked for spotting alone (the engine's
own collision decides hits on aircraft).

A round that hasn't resolved by twice its predicted flight time plus a
second (or its lifetime, aegism_intercept_fnc_ammoBurst, if the flight
time isn't known) is dropped.
```

## aegism_intercept_fnc_ciwsSelfDestruct

`addons/intercept/functions/fn_ciwsSelfDestruct.sqf`

```text
Self-destructs a CIWS round that hits nothing (the "Self-Destruct
Rounds" setting), as a C-RAM round's self-destruct fuze does: once it
has passed the gun's reach -- its CIWS Max Range, or the gun's own config
reach (aegism_intercept_fnc_envelopeBounds) -- so a round that misses
bursts out there instead of flying on. Never later than
AEGISM_SELF_DESTRUCT_MARGIN before its own lifetime (CfgAmmo
timeToLive), when the engine removes it.

The fuze time is the round's flight to the gun's reach under its drag
(CfgAmmo airFriction, the same model as aegism_intercept_fnc_
openFireRange), from the speed it actually left the muzzle at. Each
ammo's lifetime and drag are read once per ammo type and cached
("AEGISM_cacheLifetime"): they differ from one weapon system to the
next, and mods change them (the vanilla 35mm lives 6 s, from BulletBase;
ACE makes it 30 s). The fuze time is worked out per gun, refreshed every
AEGISM_SELF_DESTRUCT_REFRESH s (so a Zeus edit of CIWS Max Range takes
effect), and logged when it changes (SELF-DESTRUCT-FUZE).

One queue per gun turret (turret state "selfDestruct"): a gun's rounds
share one fuze time and leave in order, so they come due in order, and
each frame only looks at the due rounds at its head. A round that has
already hit something, or was fuzed on its target (aegism_intercept_fnc_
interceptHit), is gone by then and skipped. When the queue empties, how
many rounds self-destructed and how many were already gone is logged
(SELF-DESTRUCT).
```

## aegism_intercept_fnc_ciwsSpot

`addons/intercept/functions/fn_ciwsSpot.sqf`

```text
Closed-loop spotting for a CIWS gun, the way a real Phalanx corrects its
own aim: a sample of its rounds is measured as they pass the PREDICTED
target -- the track the aim was solved against when the round was fired
(aegism_intercept_fnc_ciwsRounds) -- and what each round says the gun
NEEDED is folded into a correction the gun's aim carries (aegism_
intercept_fnc_aimWeapon).

Measured against the prediction, a miss is the gun's own error only:
turret lag, the flight-time estimate, drop, zeroing. The target's
evasion -- where it went that the prediction didn't foresee -- is kept
out of it (it's reported separately, as how far the target strayed from
its predicted track). Measured against the real target, a jinking
helicopter's escape looked like a gun error and was fed back into the
aim.

The miss is split on two axes square to the gun's line of sight and to
each other:
    ahead - along the predicted target's crossing motion (+ ahead of it,
        - behind). A lead error of dt seconds misses by crossing speed x
        dt, so the round's needed lead correction is (its correction at
        firing) - ahead / crossing speed. Only measurable when the target
        crossed further than its own size during the round's flight (one
        coming straight down the barrel needs no lead).
    high - the part of "up" square to that crossing motion (+ high).
        Needed elevation correction = (its correction at firing) - high /
        range; aegism_intercept_fnc_aimWeapon applies it on the same
        axis. A target whose crossing motion is itself up/down leaves no
        separate "high" to measure (its weight goes to 0): any error on
        that axis is the lead's.

Estimate: a weighted mean of each round's needed correction, one per
TARGET CLASS (a lead learned on falling shells isn't a helicopter's),
reset when the gun changes ammunition. Each round is weighted by how
precisely it measures: a round's own scatter is the gun's dispersion
(an angle), so a lead sample's uncertainty grows with range / crossing
speed (weight (crossing speed / range)^2), and "high" only exists in
proportion to how much of the vertical its axis carries (weight: the
square of that). Older rounds fade by AEGISM_SPOT_DECAY per new round
(about the last few hundred count), so the correction follows a change
-- the vehicle moving, a different engagement geometry -- instead of
being outvoted by the whole mission's history. It used to be recomputed
from each burst alone: a few rounds, often close in where a metre of
miss is many milliradians, swung it from +1.4 to -12.3 mrad between
bursts.

Safeguards (calibration.hpp): a round that misses where the gun now aims
by more than AEGISM_SPOT_OUTLIER times the median of its recent rounds'
misses is an outlier, left out of the correction, the gun's measured
scatter and the burst's SPOTTING averages (counted there instead); a
round that says the gun needs more than AEGISM_SPOT_MAX_LEAD of lead or
AEGISM_SPOT_MAX_ELEVATION of elevation isn't believed for that; and how
far the real target strayed is only believed up to what it could
accelerate away in the round's flight. Rounds fired only by the last-
ditch rule, off the gate, are never spotted (aegism_intercept_fnc_
ciwsRounds).

Turret state (aegism_intercept_fnc_turretState):
    estimate - target class -> [round class, lead weight, weighted lead
        s, elevation weight, weighted elevation rad]
    corrections - target class -> [lead s, elevation rad]
    spotStats - burstId -> [rounds, sum ahead m, sum high m, sum target
        deviation m, deviation samples, outliers], for aegism_intercept_
        fnc_ciwsBurst's SPOTTING line
    spotScale - target class -> [round class, its last AEGISM_SPOT_
        SCALE_ROUNDS rounds' angular misses about where it aimed then],
        for the outlier check
    scatter - target class -> [round class, rounds, sum of squared
        angular miss square to the line of sight -- each round's miss as
        it would have been with the correction the gun now carries, so
        an error the correction has taken out isn't scatter -- sum of
        squared target deviation m, sum of squared flight time s]
        (fading like the estimate) -- the gun's measured accuracy, for
        aegism_intercept_fnc_openFireRange
```

## aegism_intercept_fnc_ciwsTrack

`addons/intercept/functions/fn_ciwsTrack.sqf`

```text
Keeps a CIWS gun's turret on its intercept point EVERY FRAME for as long
as it has a target, not just while a burst is running, and returns the
gun's current aim for the engagement loop.

Solve and steer: every AEGISM_CIWS_SOLVE_INTERVAL s the full aim is
solved (aegism_intercept_fnc_aimWeapon: lead solve, spotting correction,
gate); every frame in between the turret is steered along the aim
point's own motion since the last solve -- aim point + its velocity x
time since -- re-locked, and the barrel checked against that point
(aegism_intercept_fnc_ciwsGate). A full solve every frame did the same
job at many times the cost; at 20 Hz a smoothly moving aim point is
extrapolated at most 50ms.

Why per frame: between bursts -- and before the first one -- the turret
was only re-aimed at the engagement loop's 0.1s tick, chasing a lead
point that jumped every tick. Against a shell close in and crossing
fast, it trailed by more than the fire gate allows, so the first burst
never opened.

One handler per turret (turret state "tracking"), aiming at its
"trackTarget" [target, weaponInfo, time], refreshed every engagement
tick. It stops once that goes stale for longer than AEGISM_TRACK_STALE
(the engagement was released), or the target dies. A turret that isn't
local to this machine is only steered at the engagement tick (its lock
goes over the network).

Called by the engagement loop each tick: starts the handler if needed,
and solves on the spot if the gun has no fresh aim for this target yet
(the loop then never solves a second time in the same moment).
```

## aegism_intercept_fnc_computeLeadPoint

`addons/intercept/functions/fn_computeLeadPoint.sqf`

```text
Intercept solution for one weapon against one target: where to point so
the round/missile and the target arrive at the same place, and whether
that is possible at all.

The target is projected forward by the weapon's time of flight to the
projected point (velocity plus measured acceleration, zero-effort-miss
style), solved for the moment the two agree (see "Solving" below). All
kinematics come from real config, read once per weapon + magazine
(aegism_intercept_fnc_weaponKinematics):

    gun (ciws) - muzzle velocity v0 from CfgMagazines initSpeed
        (overridden per engine rules by CfgWeapons initSpeed: > 0
        replaces, < 0 multiplies), drag k from CfgAmmo airFriction (the
        engine's a = -k |v| v), and gravity. With a = k v0, the round's
        speed falls as v0/(1 + a t), and its velocity solves
        dv/dt = -k v0/(1 + a t) v + g exactly:
            position(t) = muzzle + aim direction x ln(1 + a t)/k
                          + g x (t + a t^2/2 - ln(1 + a t)/a) / (2a)
        So the round falls (g/2a)(t + a t^2/2 - ln(1 + a t)/a) below its
        launch line -- LESS than the vacuum g t^2/2, because the same
        drag slows its fall -- and it covers the distance to the RAISED
        point along that line: exp(k d) - 1 = a t. The aim point is the
        intercept raised by that fall. (It used to be raised by the
        vacuum drop, with the flight time measured to the un-raised
        point: at 2s of flight that aimed ~4m high, and a round climbing
        to a shell overhead arrived late -- behind it.)
        The one approximation: drag is taken at the round's speed along
        its line; gravity's own small change to that speed is second
        order.
    missile (launcher) - its speed curve learned from its own flights
        this mission, or simulated from config until then (aegism_
        intercept_fnc_missileProfile: launch speed, the motor's thrust
        and fade, drag). No drop: the missile is guided. Pointing
        the launcher at this point instead of the target's current
        position saves the missile a hard turn right off the rail.
    missile launched OFF-BORE (_launchDir given, with the missile's turn
        rate, aegism_intercept_fnc_missileAgility) - a vertical launch
        cell, a turret at its limit, or one fired before it's round: the
        missile first turns from _launchDir onto the intercept at its
        turn rate, then flies straight at it. The turn is an arc in the
        plane of the launch direction and the intercept, through the
        angle between the launch direction and the line from the turn's
        END to the intercept (iterated: the turn carries it sideways),
        covering what the missile flies in that time on its own speed
        profile. Its flight time is the arc plus the straight run. A
        target inside the turn -- the arc carries the missile past it --
        has no solution: an off-bore shot's minimum range, which grows
        with the angle and the missile's speed.

FEASIBLE only if the solution converges inside the weapon's own reach
(weaponInfo maxRange, from config) and within the round's own lifetime
(CfgAmmo timeToLive, e.g. 6s for vanilla bullets, or until an airburst
round bursts: aegism_intercept_fnc_ammoBurst) -- judged at the
meeting point it ends on, not where the target is now: a round or
missile can be fired at a target still beyond its reach and meet it
inside. A target receding
faster than the round can close -- a jet flying away from a gun -- has
no solution: the meeting never settles. The previous version didn't
check this and iterated to NaN (RPT "Error Type Not a Number" in this
file), and CIWS kept firing at targets it could never reach. An
infeasible solution returns the target's current position as the aim
point.

Solving: the meeting time t is where the flight time to the target's
position at t is t itself. Before t is passed, the flight is longer
than t; after, shorter. Until the search has seen a time past the
meeting, it steps on to the flight time (which only moves later); then
by secant steps inside the bracket it has, halving it when a step would
leave it, until the two agree within AEGISM_LEAD_SOLVE_TOLERANCE.
Simply setting t to the flight time over and over (five times, as this
used to) only settles while the target closes slower than the round or
missile flies. A missile coasting late in its flight doesn't: a Stinger
at ~300 m/s on a rocket closing at ~240 swung 17.5, 3.8, 13.2, 5.8,
11.1, 7.1 s about a meeting at 8.7 s, and was fired on the last swing
(predicted 5.5 s; its flights took 9.1 s). Not settled within AEGISM_
LEAD_SOLVE_ITERATIONS, or past the round's lifetime without a time past
the meeting seen: no meeting.

Target acceleration is measured from successive velocity samples cached
on the target per firing System (SQF has no acceleration command) -- a
sample beyond what the target can do (calibration.hpp: a position or
velocity that jumped) is dropped, LEAD-SAMPLE-REJECT; pass
_useAcceleration false for a side-effect-free, velocity-only estimate
(the Site coordinator's envelope check).

Planning ahead (the Site coordinator's layered reserve, aegism_intercept_
fnc_assignEngagements): _delay solves for a shot fired that many seconds
from now, from the target's state projected to that moment, and
_ballistic projects it on gravity alone -- exact for an unguided
artillery round or rocket (CfgAmmo airFriction 0).

2026-10-07, the off-bore meeting search: a try at a time long past the
meeting projects a far rocket (under gravity) to somewhere below the
launcher, a point the turn solve can't fly to (-1). That used to end the
whole search, so every off-bore shot at the edge of a RAM launcher's reach
came back infeasible ("too close to turn onto"), claims were released and
the reserve plan's first step with a shot came late. Now such a try uses
the straight flight time to keep the search going, and only the meeting
found has to be flyable (checked after it settles, which also sets _turn
for that point). 00:41 RPT: two ASSIGN-CLEAR and three NO-SOLUTION lines
with that reason at 7 km.
```

## aegism_intercept_fnc_debugBenchmark

`addons/intercept/functions/fn_debugBenchmark.sqf`

```text
Times AEGIS-M's per-call hot paths on the running game (diag_code
Performance) and writes one BENCHMARK line per function to the RPT, so
the per-second counts in the PERF line (aegism_fnc_perfLog) can be
turned into real milliseconds. Run from the debug console (Local Exec,
singleplayer / Eden Preview / host), looking at a System, with any live
object as the target -- a placed helicopter, or a flying shell.

Timed per call:
    classify bullet / shell - ammo classification (cached after the
        first call, as in play)
    canEngage - one engageability check (the coordinator and standalone
        selection run these)
    aimWeapon - one full aim solve (a CIWS runs these at 20 Hz)
    ciwsTrack steer - one per-frame steer between solves
    turretPoints - muzzle and camera positions
    computeLeadPoint - one intercept solve

Note: aimWeapon and ciwsTrack really aim the turret while they run.
```

## aegism_intercept_fnc_debugProbeMunitions

`addons/intercept/functions/fn_debugProbeMunitions.sqf`

```text
In-game probe, run from the debug console while testing (on the server:
in single player or as host the local console is fine). From then on,
each new ammo type AEGIS-M tracks is probed once, AEGISM_PROBE_AFTER s
into its flight (clear of whatever fired it), and the result logged
(PROBE, RPT and system chat):

Its body. A round counts as hitting a munition where its path comes
within its own radius of the munition's bounding box (aegism_intercept_
fnc_bodyPass) -- all AEGIS-M has for a shape, if nothing finer exists.
Lines are cast across the munition in every LOD lineIntersectsSurfaces
knows (GEOM, FIRE, VIEW, IFIRE, PHYSX) to find whether any of them can
hit this projectile at all, and if one can, the body is measured in it:
its length, width and height, and where along the box it sits.

Found so far (2026-10-06): no LOD of vanilla's R_230mm_HE can be hit.
And a vehicle can't be given a munition as its target: doTarget on a
projectile left assignedTarget empty (so a mod script that reads it,
like POOK's AAA fuse, can't be fed one).

[false] call ... stops it.
```

## aegism_intercept_fnc_debugSetFireHold

`addons/intercept/functions/fn_debugSetFireHold.sqf`

```text
On-demand hard hold/release for a System's launcher/CIWS weapons, meant
to be run from the Arma debug console while testing -- forces a
specific System (or every weapon it has, if no turret path is given) to
stop firing entirely, or releases a hold previously set.

This is a genuine circuit breaker, not a Doctrine/salvo setting: it's
checked in aegism_intercept_fnc_fireWeapon itself, the single narrowest
choke point every real fire command passes through (turret state
"fireHold"), so it guarantees no shot from that turret regardless of
what upstream logic tries to trigger.

Not something a mission should ship with set permanently.
```

## aegism_intercept_fnc_elevationAngle

`addons/intercept/functions/fn_elevationAngle.sqf`

```text
Elevation of one ASL position as seen from another, in degrees above
(positive) or below (negative) the horizontal.
```

## aegism_intercept_fnc_engagementLoop

`addons/intercept/functions/fn_engagementLoop.sqf`

```text
One engagement tick for one role ("launcher" or "ciws") of one System,
run on the server every 0.1 s of the mission clock by a per-frame handler
registered in aegism_system_fnc_moduleInit. Ammo is read live from the vehicle's real
magazines; AEGIS-M counts nothing itself.

NETWORKED (synced to a Site): executes the assignments the Site's
coordinator (aegism_intercept_fnc_assignEngagements) published for this
System and role ("AEGISM_assigned", soonest impact first). It never
picks targets itself. Nothing assigned: returns straight away.

STANDALONE: each of its weapon turrets picks its own target from the
System's own pool (aegism_intercept_fnc_selectTarget) -- a target another
of its turrets in this role is already on is left to that turret -- and
keeps its own engagement state in its turret state ("standalone_<role>",
aegism_intercept_fnc_turretState). A launcher turret whose salvo is away
moves on to its next target while the missiles fly ("inFlight_launcher");
if they all miss, the target is back on its list (MISSED). Nothing in
the pool: returns straight away.

Both paths run the same per-engagement sequence on an engagement state
HashMap (a Site assignment record, or the standalone state) with keys
assignedAt, lastShotAt, roundsFired, nextAttemptAt, interceptors:
    1. Aim -- a launcher solves here (aegism_intercept_fnc_aimWeapon); a
       CIWS gun's per-frame tracker (aegism_intercept_fnc_ciwsTrack) is
       handed the target and its current aim used. Every tick from the
       moment of assignment, so the turret is already on target when the
       crew finishes reacting.
    2. Crew reaction time since assignment (CIWS capped at
       AEGISM_CIWS_REACTION_CAP: automated fire control). Once in
       combat -- the vehicle or its Site has fired within the Site's
       live window (Warning Lasts After Last Shot) -- scaled by the
       crew's Reaction Once in Combat: the first target of an
       engagement gets the full reaction, each next one less.
    3. Fire cadence:
         launcher - doctrine salvoSize per engagement, the launcher's
             shot interval between shots (aegism_intercept_fnc_
             launcherInterval; both crew-modulated), and never while
             its weapon is still readying its next round or loading its
             next magazine (aegism_intercept_fnc_weaponReload,
             RELOADING): the engine shows the new magazine's count
             before it can fire it
         ciws - sustained bursts (aegism_intercept_fnc_ciwsBurst) of a
             random doctrine ciwsBurstMin..ciwsBurstMax seconds at the
             gun's own rate of fire, and ciwsBurstPause (crew-modulated)
             before firing again at the SAME target. A gun whose last
             target is gone goes straight on to the next: the pause
             after every kill cost ~1s per shell in a salvo. A running
             burst is cut short if the target changes or LOS is lost.
    4. LOS from this System (a Site contact may have been detected by a
       sibling with a different view), re-checked every
       AEGISM_LOS_REUSE s.
    5. Alignment from step 1.
    6. Fire (aegism_intercept_fnc_fireWeapon). A failed crew
       reliability roll costs a launcher one fire cycle, and a gun its
       crew's reaction (nextAttemptAt). A Site
       launcher's lost cycle holds the whole turret ("holdUntil") and
       flags the assignment "crewFailed": the coordinator re-tasks the
       contact to another weapon rather than leaving it with a crew that
       just failed to shoot.

Every silent wait is logged once per engagement (REACTING, SLEWING
every AEGISM_SLEW_LOG_INTERVAL s, LOS-BLOCKED on change), so an assigned
weapon that isn't firing always says why in the RPT.

Optional Cost/Value Judgment (standalone): the crew holds fire on a
contact if firing would leave fewer rounds than there are pooled
contacts of strictly higher threat value.

2026-10-07:
- A turret is cued before its first target too ("lockAt" 0 = cued, never
  aimed), not only between targets.
- Measured shot spacing ("spacing") only takes a shot that came within
  AEGISM_SPACING_READY_SLACK (0.5 s, my figure) of the launcher being held
  by its own cycle ("cycleHeldAt", stamped at every reloading exit). In the
  00:41 RPT the RAM launchers, now firing for the edge of their reach,
  waited 1-3 s between their first rockets; those gaps (4.3-6.2 s, under
  the old "twice the estimate" limit) pushed their spacing to about 4 s
  for a real 3.1, the reserve plan judged them unable to reach the back of
  the salvo, and nine rockets went to the Patriots while each RAM launcher
  ended with 4 missiles.
```

## aegism_intercept_fnc_envelopeBounds

`addons/intercept/functions/fn_envelopeBounds.sqf`

```text
The range and height limits of one weapon under the resolved doctrine --
the intersection aegism_intercept_fnc_inEnvelope tests against (see its
header for the rules). Split out so a caller testing many positions for
one weapon (the Site coordinator's layered-reserve plan) resolves them
once.
```

## aegism_intercept_fnc_fireModeStats

`addons/intercept/functions/fn_fireModeStats.sqf`

```text
The config numbers of the fire mode a turret's weapon is in right now:
its CfgWeapons dispersion and reloadTime. The mode comes from weaponState
each call (it can change); the numbers are cached per weapon + mode
("AEGISM_cacheModes"). weaponState reports a weapon with no modes[] of
its own under its own class name, which isn't a sub-class -- the weapon
class itself is then the mode.
```

## aegism_intercept_fnc_fireWeapon

`addons/intercept/functions/fn_fireWeapon.sqf`

```text
Fires a System's own real weapon: one missile for a launcher, or opens
one sustained burst for a CIWS gun (aegism_intercept_fnc_ciwsBurst, at
the gun's own rate of fire). AEGIS-M never spawns projectiles:
ballistics, guidance and damage are the game's own.

The caller (aegism_intercept_fnc_engagementLoop) has already aimed the
turret and confirmed alignment; this function only rolls crew
reliability and fires, via BIS_fnc_fire (a real single fire command --
fireAtTarget hands the decision to AI judgement and was observed firing
several missiles per call).

Crew reliability is rolled here, once per missile or per CIWS burst. A
failed roll returns 0, which the engagement loop treats as a lost fire
cycle (it waits one shot interval / burst pause before trying again).

Before firing it writes a capture context on the turret ("capture" in
aegism_intercept_fnc_turretState, naming the weapon) and makes sure the
vehicle has AEGIS-M's persistent Fired handler (aegism_intercept_fnc_
firedHandler); aegism_intercept_fnc_onSystemFired then hands a launched
missile its target
(setMissileTarget), records it as an in-flight interceptor, and starts
its proximity fuse.

Crew locality: the engagement pipeline runs on the server, and a
missile can only be given its target where it's simulated -- where the
crew is local. An AI crew simulated on another machine (a headless
client, or a player's AI group) is moved to the server (setGroupOwner)
and this fire cycle skipped; a PLAYER in the turret can't be, so its
missiles fly without AEGIS-M's target. Logged once per turret
(NONLOCAL).

Third-party scripted missile guidance: if that mod is loaded and the
ammo declares its guidance class explicitly with enabled=1, the target
is written to the variable its own Fired handler reads, on both the
turret's gunner and the vehicle. That mod's own AI-guidance setting must
still allow AI shots for it to take effect.
```

## aegism_intercept_fnc_firedHandler

`addons/intercept/functions/fn_firedHandler.sqf`

```text
Makes sure a System vehicle has AEGIS-M's persistent "Fired" event
handler (aegism_intercept_fnc_onSystemFired), here on the server where
its weapons are fired from: added if it has none, and again if something
removed it -- another mod's removeAllEventHandlers "Fired" would
otherwise leave every missile it fires with no target given and no fuse
(EH-RESTORED).

Called as soon as the vehicle is a System and every couple of seconds
after (aegism_system_fnc_guardSystems), and before every fire command
(aegism_intercept_fnc_fireWeapon). It used to be added only by the first
fire command to get past its crew's reliability roll, so a launcher that
hadn't fired yet had none, and a missile it launched by itself went
unseen: POOK's S-400 was one missile down before its first AEGIS-M shot,
with nothing logged (2026-10-06).
```

## aegism_intercept_fnc_gunnerLock

`addons/intercept/functions/fn_gunnerLock.sqf`

```text
Keeps a launcher turret's gunner locked on the aircraft it's assigned --
as a real crew locks on before launch -- or lets go of it. Called every
tick the launcher works an engagement (aegism_intercept_fnc_
engagementLoop), from the moment it's assigned.

AEGIS-M aims and fires the turret itself, with the crew's own targeting
off (aegism_fnc_setWeaponAiSuppressed), so the gunner never has a target
of its own. The game only warns a target of an incoming missile
(IncomingMissile) launched locked on it or aimed at it by AI -- a missile
fired without one gives the aircraft no launch warning, and its crew
never reacts (no flares, no evasion). reveal + doTarget gives the gunner
the target (logged, LOCK-ON): the aircraft gets its lock warning while
the launcher reacts and slews, and its missile warning at launch
(MISSILE-WARNING, aegism_intercept_fnc_fireWeapon).

The lock takes the weapon's own time (CfgWeapons weaponLockDelay: 0.5 s
for ACE's SAM launchers, 1.5 s for the vanilla MIM-145, 3 s for the
vanilla RIM-116), and a missile fired before it's complete leaves
unlocked: a Defender, with no sensor of its own to lock with, given its
target at the instant of launch, only ever gave a "locking" warning.
So this returns how much longer the lock needs, and the launcher holds
fire until it's done ("locking").

The gunner's "TARGET" AI, off since AEGIS-M took the turret (aegism_fnc_
setWeaponAiSuppressed), is back on while it's locked: with it off a
Defender -- whose target only comes from the Site's datalink -- held one
for 12 s and never locked (no missile warning at launch). Its
"AUTOTARGET" stays off, so it doesn't pick a target of its own, and its
"FIREWEAPON" off, so it can't fire on its own: a gunner holding a target
fired at it by itself without that (in testing, some 3.5 s after being
given it -- UNCOMMANDED-FIRE). A munition is never locked (nothing locks
on a projectile): a turret moving from an aircraft to a munition lets
go, as does a turret handed back to its crew.
```

## aegism_intercept_fnc_inEnvelope

`addons/intercept/functions/fn_inEnvelope.sqf`

```text
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
```

## aegism_intercept_fnc_interceptHit

`addons/intercept/functions/fn_interceptHit.sqf`

```text
Detonates an interceptor that has reached its target (triggerAmmo: real
splash), and a MUNITION target with it (aegism_detect_fnc_
destroyMunition) -- the engine has no projectile-vs-projectile
collision, so an incoming round has no hitpoints for the splash to act
on. An aircraft target is left to real splash damage.

Against a munition, both blasts -- the interceptor's, and the warhead of
the munition it destroyed -- also take any other tracked munition within
their radius (aegism_detect_fnc_blastMunitions, BLAST-KILL): the rockets
flying beside it in a salvo.

An interceptor that's already gone -- the game's own proximity fuse set
it off within reach of its target, before AEGIS-M's fuse saw the pass
(aegism_intercept_fnc_interceptorPFH) -- is credited the same way, from
where it was and what it was (_at, _ammo).

Logged as INTERCEPT, with where: the distance from the vehicle that
fired it, and the height above the ground.
```

## aegism_intercept_fnc_interceptorLost

`addons/intercept/functions/fn_interceptorLost.sqf`

```text
Self-destructs an AEGIS-M launcher missile that no longer has the target
it was fired at (aegism_intercept_fnc_interceptorPFH): the target is gone
before it got there (another weapon, or its own end), or its seeker has
turned to something else. Left to fly, its seeker takes whatever it finds
next -- a missile fired at a rocket killed by another weapon went on to
shoot down the aircraft that fired the rocket, a target the Site wasn't
allowed to engage. As a real SAM that loses its target does, it
detonates where it is (triggerAmmo) -- and any tracked munition within
its blast goes with it (aegism_detect_fnc_blastMunitions).

Logged as INTERCEPTOR-LOST.
```

## aegism_intercept_fnc_interceptorPFH

`addons/intercept/functions/fn_interceptorPFH.sqf`

```text
Per-frame proximity/direct-hit tracker for one AEGIS-M launcher missile
(started by aegism_intercept_fnc_onSystemFired). Necessary because the
engine has no projectile-vs-projectile collision at all: a missile
passing straight through an incoming munition does nothing unless
something scripted detonates both. (CIWS rounds are tracked together per
gun by aegism_intercept_fnc_ciwsRounds.)

Hit: against a MUNITION target, the missile's path coming within its
own radius -- its blast (CfgAmmo indirectHitRange) or its proximity fuse
(proximityExplosionDistance), whichever is larger -- of the target's
body, its box (aegism_intercept_fnc_bodyPass); against an aircraft,
within its blast of the aircraft's centre.

Arming: no detonation until the missile has flown its own CfgAmmo
fuseDistance from where it was fired (e.g. 100m for the MIM-145 SAM).

Closest approach is computed on RELATIVE motion between frames (both
the missile and the target move), not against the target's current
position only -- at a 1500 m/s closing speed that difference is ~25m
per frame.

A guided missile is tracked for its whole flight: it routinely opens
distance during boost or a turn and closes again. An unguided one stops
being tracked once it has closed and started opening.

On a hit: aegism_intercept_fnc_interceptHit. The engine's own proximity
fuse (CfgAmmo proximityExplosionDistance, set on most vanilla SAMs) may
detonate the missile first; this handler then sees it gone, and credits
the kill if the stretch it was on that frame came within its radius of
the munition's body.

Lost target: a guided missile whose target is gone before it gets there
(another weapon killed it first), or whose seeker has turned to
something else, follows another incoming munition its launcher's Site
is tracking if that's what its seeker took -- otherwise it
self-destructs (aegism_intercept_fnc_interceptorLost). Left free, its
seeker took the next thing it found, which shot down an aircraft the
Site wasn't allowed to engage.

Turn rate: a guided missile's body direction is followed every frame,
and its rotation summed over AEGISM_TURN_WINDOW s windows -- the fastest
window is the flight's fastest SUSTAINED turn (a window that long
averages out frame-to-frame jitter and a last-instant jink). The body
direction, not the velocity: gravity bends a slow missile's path just
off the rail without it steering at all. At the end of the flight it's
folded into the missile's turn rate (aegism_intercept_fnc_
recordMissileTurn, MISSILE-TURN) -- what an off-bore launch is planned
with (aegism_intercept_fnc_launchSolution).

Speed: sampled every second after launch, and folded into the missile's
learned speed curve however the flight ends (aegism_intercept_fnc_
recordMissileSpeed, MISSILE-SPEED). An intercept also logs the length
of the path it actually flew (summed frame by frame) against the
straight line, for the log's check of the prediction. A missile whose
seeker changed to another munition (above) isn't measured for its turn
rate; its speeds still count.
```

## aegism_intercept_fnc_launchSolution

`addons/intercept/functions/fn_launchSolution.sqf`

```text
How one launcher gets a missile onto one target, from what the launcher
and the missile can actually do. A missile doesn't have to leave
pointing at its target: a vertical launch cell can't point at all, a
turret stops at its limits, and one still swinging round could, as a
last resort, fire now and let the missile turn.

Straight solution first (aegism_intercept_fnc_computeLeadPoint): the
intercept, and the direction a missile flying straight would leave on.
Then the ways to launch:
    "slew" - swing the turret to the closest direction it can reach
        (aegism_intercept_fnc_turretCanPoint -- its elevation and
        traverse limits) and launch there: its swing time (aegism_
        intercept_fnc_turretSlewTime) plus the flight. On the intercept
        direction itself it's a straight launch ("onBore").
    "now" (_considerNow) - launch along the barrel as it points now,
        before the turret is round -- ONLY to make an intercept it
        otherwise couldn't: swinging first has no solution, or its swing
        plus the flight lands after the target does (_timeToImpact). At
        the start of an engagement, with time in hand, the turret always
        swings fully first.
    "fixed" - a mount that can't move at all (a vertical launch cell,
        a hull-fixed launcher): along its barrel, whatever it's pointed
        at.
On an axis the mount can't move, the barrel's own direction is used,
not the config limits.
A launch off the intercept direction by more than AEGISM_LAUNCH_ON_BORE
(the aim's own on-target tolerance, aegism_intercept_fnc_aimWeapon) is
off-bore, and needs the missile (aegism_intercept_fnc_missileAgility):
    - the target within its post-launch cone -- and, on a launcher that
      can move, within the doctrine's limit for the way it launches:
      Max Off-Bore Launch While Swinging (20 deg by default) firing
      "now", before the turret is round -- it never fires wildly off the
      target when it could swing round instead -- and Max Off-Bore
      Launch At Turret Limit (30 deg by default) for "slew", the turret
      as close as it can get: at its elevation or traverse limit (a
      Spartan's RAM turret stops at 40 deg, and high-arc rockets come
      down steeper than that), or a mount that can't move on one axis.
      A fixed mount (a vertical launch cell) is only limited by the
      missile: off-bore is the only way it fires.
    - with its turn rate known: the turn flown (computeLeadPoint's
      off-bore solve -- flight time, and a minimum range inside which it
      can't turn in time)
    - its turn rate NOT known yet (a missile the game guides, before
      one of AEGIS-M's has been seen turning): flown as if straight.
      Only accepted where there's no better choice -- the turret has to
      get as close as it can first, and firing "now" isn't considered
      -- as before the turn was modelled; the missile's first turning
      flight calibrates it (MISSILE-TURN).
Swinging first is the way, unless only "now" makes the intercept; a
fixed mount only has one. (The straight solution is taken at the moment
of launch for "now"; for "slew" the target keeps moving during the
swing, which the off-bore solve accounts for and a straight launch
approximates.)

Modes: with _considerNow, the firing decision (per engagement tick) and
the coordinator's check -- both need to know a late target can still be
reached by firing now; with _withSlew false, the coordinator's reserve
plan, for a shot at a future moment (_delay s from now: the turret will
have had time).
```

## aegism_intercept_fnc_launcherInterval

`addons/intercept/functions/fn_launcherInterval.sqf`

```text
Seconds between two missiles from one launcher turret, before crew
temperament scaling.

A positive "Seconds Between Missiles" (Site setting, or the vehicle's own
override) is used as given. 0, the default, is Auto: the launcher's own
rate of fire, the reloadTime of the fire mode it is in (aegism_intercept_
fnc_fireModeStats). That is the weapon's own authored fire rate and it
already scales with the missile it carries -- vanilla MIM-145 Defender
4s, Mk49 Spartan (RIM-116) 2s, Mk21 Centurion (RIM-162) 1s -- and it
covers mod launchers without a table here.

Logs the interval (and where it came from) whenever it changes for a
turret (FIRE-RATE).
```

## aegism_intercept_fnc_lockTurret

`addons/intercept/functions/fn_lockTurret.sqf`

```text
Points one specific turret of a vehicle at an ASL position, or hands it
back to its crew, with lockCameraTo -- the same command ACE's Hunter-
Killer uses to slew a gunner's turret (ace_hunterkiller_fnc_slew:
"_vehicle lockCameraTo [_posASL, _turret, true]"; released with objNull,
as ace_aircraft does).

Replaces lookAt, which is an order to a UNIT: given the vehicle it goes
to the effective commander, so on a crewed vehicle like the Cheetah only
the commander's optic traversed and the main gun never moved.
lockCameraTo addresses the turret by its path, whoever crews it.

The lock is PERSISTENT (temporary = false) and released explicitly
(objNull, by aegism_intercept_fnc_engagementLoop). ACE passes temporary
= true because its gunner is usually a player who should be able to take
the turret back; here the gunner is AI, and with temporary = true SAM
turrets sat 30-60 degrees off their assigned target for 15s at a time --
apparently the crew's own aiming reclaiming the turret.

lockCameraTo must run where the turret is local (ACE routes it with
CBA_fnc_turretEvent). The engagement loops run on the server, where AI
crews normally are; a turret owned elsewhere (headless client, player
gunner) gets the command sent to its owner.
```

## aegism_intercept_fnc_missileAgility

`addons/intercept/functions/fn_missileAgility.sqf`

```text
What a missile can do AFTER it leaves the rail -- what decides whether a
launcher can fire at something it isn't pointing at (a vertical launch
cell, a turret at its limit, or one still swinging round; aegism_
intercept_fnc_launchSolution). Not the lock cone before launch
(missileLockCone): AEGIS-M fires by script and hands the missile its
target after launch.

    guidance - who steers it:
        "ace" - ACE's scripted guidance: the ammo declares its own
            ace_missileguidance class with enabled = 1, and ACE's
            setting lets AI shots be guided (ace_missileguidance_
            enabled 2) -- as ACE's own Fired handler requires
        "engine" - the game's own (any other guided missile)
        "none" - unguided, or can't be steered: a missile with
            maneuvrability 0 (how ACE hands a missile to its own
            guidance -- ACE's RIM-116 and Stinger) when ACE isn't
            guiding AI shots flies straight
    turn rate - degrees per second it can turn its flight:
        ace - the ammo's ACE pitchRate / yawRate, the lower (ACE turns
            the missile at up to these; 30 if unset, ACE's own default)
        engine - MEASURED: the game's maneuvrability has no unit, so
            the rate comes from AEGIS-M's own missiles in flight
            (aegism_intercept_fnc_interceptorPFH, MISSILE-TURN): the
            fastest sustained turn seen on a flight that had to turn --
            once two have, the second fastest, so one bad flight can't
            set it (aegism_intercept_fnc_recordMissileTurn). 0 until one
            has.
    post-launch cone - degrees off its flight a target can be and
        still be guided to:
        ace - 180 when it locks on after launch (the SAM default):
            ACE flies it at the target's position, not its seeker's
            view; its seekerAngle (a half-angle) if it must lock on
            before launch
        engine - CfgAmmo missileKeepLockedCone (missileLockCone if
            unset; 180 if neither -- the same fallback as aegism_
            intercept_fnc_weaponKinematics)
Logged once per missile (AGILITY).
```

## aegism_intercept_fnc_missileFlightKey

`addons/intercept/functions/fn_missileFlightKey.sqf`

```text
The key a missile's learned speed curve is kept under (aegism_intercept_
fnc_recordMissileSpeed, aegism_intercept_fnc_missileProfile): its flight
config -- launch speed, thrust, burn time, motor delay, airFriction,
lifetime and maxSpeed (aegism_intercept_fnc_weaponKinematics) -- not its
weapon. Missiles that fly alike learn together: POOK's SA-8 has six
one-missile launchers, each its own weapon, magazine and ammo class.
```

## aegism_intercept_fnc_missileFlightTime

`addons/intercept/functions/fn_missileFlightTime.sqf`

```text
Seconds a launcher's missile flies toward a point a given distance away,
on its speed curve learned from its own flights, or simulated from
config until then (aegism_intercept_fnc_missileProfile) -- until it gets
there, or until its lifetime (CfgAmmo timeToLive) runs out if that's
sooner. The same flight aegism_intercept_fnc_computeLeadPoint solves
with.

Used to rule out, without solving anything, a target too far out for a
missile to meet inside its reach: in the time the missile takes to fly to
the edge of its reach, the target can close at most speed x t + g t^2 / 2
(aegism_intercept_fnc_canEngage, and the Site coordinator's reserve
plan).
```

## aegism_intercept_fnc_missileProfile

`addons/intercept/functions/fn_missileProfile.sqf`

```text
A launcher's missile's flight from launch: how far it has flown and how
fast it's going every AEGISM_PROFILE_STEP s, to the end of its lifetime.
Every missile flight AEGIS-M predicts is read from it (aegism_intercept_
fnc_missileProfileAt): the lead solver, the coordinator's in-time checks.
Per weapon + magazine.

LEARNED once its own flights have shown it (aegism_intercept_fnc_
recordMissileSpeed): every second after launch that at least AEGISM_
SPEED_MIN_SAMPLES flights have reached, its speed is the median of their
real speeds then (the last AEGISM_SPEED_SAMPLES of them). Between those
seconds, and from launch to the first, the config simulation's own curve
is scaled to them; past the last, scaled as at the last. So it flies
whatever the missile really does -- a missile that stops at its maxSpeed
(POOK's PAC-2 and PAC-3, at 1750 m/s) and one that doesn't (the
MIM-145, ~1390 m/s past its 850; the 9M317 and 9M331), one a mod flies by
script -- which no single rule from config got right. Rebuilt when a
flight adds to it ("AEGISM_cacheMissileLearned"). Learned per flight
config (its launch speed, motor, drag, lifetime and maxSpeed), not per
weapon: missiles that fly alike learn together -- POOK's SA-8 has six
one-missile launchers, each its own weapon, magazine and ammo, which
would otherwise never see a second flight.

SIMULATED from its config until then, once and cached ("AEGISM_cache
MissileProfile"). The engine's rules for a missile (BI wiki, CfgAmmo
Config Reference; values from aegism_intercept_fnc_weaponKinematics):
    launch - its initSpeed
    motor - lights initTime s after launch; thrust is an acceleration
        (m/s^2), at full for the first 75% of thrustTime, then fading
        linearly to nothing at thrustTime
    drag - along its nose, a = AEGISM_MISSILE_DRAG x airFriction x v^2:
        airFriction is each missile's own; the multiplier is the
        engine's, in no config. A community fit to recorded NLAW, Titan,
        RPG, DAGR and ASRAAM flights (BI forums, 2016) put it at 0.002;
        AEGIS-M's own missiles' speed every second in flight (2026-10-06
        tests, MISSILE-SPEED) fit 0.0022 (RIM-162), 0.00224 (Stinger)
        and 0.00228 (RIM-116) -- and 0.0025 for the MIM-145, whose
        real speed levels off near 1390 m/s. 13 missile types, POOK's
        among them, then flew within 5% of the simulation's times
    maxSpeed - NOT applied, though the wiki calls it the top speed
        (AEGISM_PROFILE_SPEED_CAP): some missiles stop at it and some
        don't (above); the learned curve settles which
Not simulated: gravity on a climb, speed lost turning (sideAirFriction).
Midpoint steps: within a metre of a 0.5 ms step over 30 s of the
RIM-116's and MIM-145's flights. Logged once per missile
(MISSILE-PROFILE, Verbose).
```

## aegism_intercept_fnc_missileProfileAt

`addons/intercept/functions/fn_missileProfileAt.sqf`

```text
One reading off a missile's simulated flight (aegism_intercept_fnc_
missileProfile), interpolated between its steps:

    "distance" - metres it has flown _value s after launch
    "time" - seconds it takes to fly _value metres
    "speed" - m/s it's going _value s after launch

Past the end of its simulated life it carries on at its last speed: a
caller that cares compares the time with the missile's lifetime itself
(the lead solver's feasibility, aegism_intercept_fnc_missileFlightTime).
```

## aegism_intercept_fnc_munitionSize

`addons/intercept/functions/fn_munitionSize.sqf`

```text
Reads a CfgAmmo entry's indirectHitRange (blast radius, metres) as a
real-config proxy for a munition's physical size/destructive class --
used both to size an incoming contact's own munition (how big is the
missile bearing down on us) and an interceptor's loaded ammo (how big
a warhead does this launcher's weapon carry), so aegism_intercept_fnc_
assignEngagements can match one against the other without a mission
designer hand-tuning a "small/medium/large" tier per class.

indirectHitRange is what the engine uses for splash damage, so it's set
consistently across vanilla and modded explosive ammo, and scales with
warhead size. hit (direct-hit damage) is NOT used here -- it's noisy
across ammo roles. Plain (non-explosive) gun ammo returns 0.

Cached per ammo class ("AEGISM_cacheMunitionSize"): the coordinator
sizes every contact every cycle.
```

## aegism_intercept_fnc_onSystemFired

`addons/intercept/functions/fn_onSystemFired.sqf`

```text
Body of the single persistent "Fired" event handler every AEGIS-M System
vehicle gets (aegism_intercept_fnc_firedHandler). It must
live on the VEHICLE: a unit's own "Fired" event never triggers for a
vehicle-mounted weapon.

aegism_intercept_fnc_fireWeapon writes a capture context on the firing
TURRET ("capture" in aegism_intercept_fnc_turretState: [target, role,
interceptors, expiresAt, targetIsMunition, turretPath, weapon, launch
plan [off-bore deg, predicted flight s, fired at]]) and this
handler consumes it for the rounds that turret actually produces. The
turret is found from the Fired event's gunner; if that doesn't lead to a
context for this weapon, the turret whose context names this weapon.
(Contexts used to be keyed by weapon class alone, so two turrets with
the same weapon took each other's rounds.)
    launcher - exactly one round per fire command: the missile is given
        its target (setMissileTarget -- without it a missile fired by
        script has no lock and flies unguided or seeks whatever its
        seeker finds), recorded in the assignment's interceptors list
        (so aegism_intercept_fnc_assignEngagements can tell "still in
        flight" from "missed"), and handed to its proximity fuse
        (aegism_intercept_fnc_interceptorPFH), with its launch plan for
        the turn measurement. Context cleared after.
    ciws - every round of the burst, until the context expires, goes to
        the gun's round tracker (aegism_intercept_fnc_ciwsRounds): fuzed
        against a MUNITION target, and every AEGISM_SPOT_EVERY-th round
        measured for spotting against the track it was aimed with. A
        round against an aircraft that isn't spotted isn't tracked at all
        (the engine's own collision handles the hit). With Self-Destruct
        Rounds on, every round also goes to its gun's self-destruct
        queue (aegism_intercept_fnc_ciwsSelfDestruct).

Rounds from other weapons, or after the context expired, are ignored.
```

## aegism_intercept_fnc_openFireRange

`addons/intercept/functions/fn_openFireRange.sqf`

```text
How far out one gun turret opens fire on a target: the longest intercept
distance at which ONE BURST is at least doctrine ciwsOpenFireChance
likely to put a round within the hit radius -- from what's measurable,
not from the fire modes' AI hit-probability values:

    a round's miss at intercept distance d scatters square to the line
    of sight with a per-axis RMS of
        sigma(d)^2 = (s d)^2 + (u t(d))^2 / 3
    s - the gun's angular scatter: its OWN measured misses (every
        spotted round's miss square to the line of sight, over its range,
        aegism_intercept_fnc_ciwsSpot) for this kind of target, blended
        with a prior worth AEGISM_SCATTER_PRIOR_ROUNDS rounds: the
        current fire mode's CfgWeapons dispersion (read as the RMS
        angle, its widest reading) plus the barrel being anywhere inside
        its fire gate when it fires (dispersion + hit radius / d, spread
        evenly over that disc). The prior alone is optimistic -- turret
        tracking isn't in it -- so the range comes in as the gun's own
        misses are measured: ~2.4km for a Phalanx against a shell before
        it has fired, ~1.3-1.8km at the 7-10 mrad its rounds have
        measured in play.
    u - how fast the real target strays from its predicted track, per
        second of the round's flight (measured the same way; 3D, so a
        third of it per axis)
    t(d) - the round's flight time to d: (exp(k d) - 1) / (k v0)
        (CfgMagazines initSpeed, CfgAmmo airFriction)
    one round hits if its miss is within r, the hit radius: the
        target's size to the gun (aegism_intercept_fnc_aimWeapon -- a
        munition's body as seen along the line of fire plus the round's
        own blast or proximity radius, as its fuse counts a hit; an
        aircraft's half-size):
        p = 1 - exp(-r^2 / (2 sigma^2))
    a burst is N rounds: the gun's measured rate of fire (else its fire
        mode's reloadTime) x the doctrine's mean burst length, and hits
        with 1 - (1 - p)^N

Capped by the round's reach in its own lifetime (CfgAmmo timeToLive, or
until an airburst round bursts, aegism_intercept_fnc_ammoBurst:
ln(1 + k v0 T) / k). A munition target isn't engaged inside the round's
arming distance (CfgAmmo fuseDistance) -- the scripted fuse can't
detonate before it.

Cached per turret, target class and hit radius for AEGISM_OPEN_FIRE_
REFRESH s (the gun's measured scatter moves slowly; recomputing on every
measured round -- ~17 a second while firing -- redid the search at every
aim solve). Logged when it
moves by more than AEGISM_OPEN_FIRE_LOG_CHANGE (OPEN-FIRE-RANGE, with
every input). Doctrine ciwsOpenFireChance 0: no limit short of the
round's reach.
```

## aegism_intercept_fnc_planAhead

`addons/intercept/functions/fn_planAhead.sqf`

```text
Works out, between the Site coordinator's turns, the launcher shots of
the munitions whose look its last run put off (it had worked out AEGISM_
PLAN_STEPS new steps already, aegism_intercept_fnc_assignEngagements):
the questions kept on the Site ("AEGISM_planLeft") are asked, soonest
impact first, for AEGISM_PLAN_BUDGET s a frame, and what's still
unanswered is kept for the next frame. Nothing is decided here -- the
answers go into the Site's plan cache, where the coordinator's next turn
finds them.

A salvo coming into view costs several short frames this way instead of
one long one. The coordinator's first way of spreading it was to run
itself again the next frame: with its whole sweep of every contact and
weapon each time, that cost four times what it saved (85 of 121 runs in
10 s, 2.4 s of server time, 2026-10-06). Its second was to cut its own
questions short and decide nothing for those munitions until this had
answered them: under a salvo the newest rockets waited 15-20 s for their
first look (2026-10-06). Now a run never waits on this: a munition it
looks at, it works out in full, with whatever this has ready.

A question whose munition is urgent by now (AEGISM_URGENT_TTI) is dropped:
the coordinator looks at those on every run.
```

## aegism_intercept_fnc_planShot

`addons/intercept/functions/fn_planShot.sqf`

```text
The earliest shot one launcher can make at one incoming munition from a
given moment on that meets it before a given time (its impact): the Site
coordinator's question for a launcher that isn't ready yet, and its
layered reserve's for every free munition (aegism_intercept_fnc_
assignEngagements).

Found by stepping along the munition's projected path every AEGISM_
RESERVE_PLAN_STEP s from the start -- a feasible intercept, its meeting
point inside the envelope (the munition itself may still be beyond it
when the missile leaves, aegism_intercept_fnc_canEngage), landing in
time -- and only as far as the first shot.

Each step's answer is kept per munition and launcher, in game time (the
plan cache: [scanned at, position, velocity, step -> [fire at, intercept
at], or [] for no shot, known stretch]), so a later question from
another start re-solves nothing already worked out. The whole path used
to be solved up front -- an intercept solve (aegism_intercept_fnc_
launchSolution) for every step in the envelope, for every munition and
launcher -- and a salvo coming into view together cost ~100 ms in one
frame. A ballistic path is fixed, and so is a parked launcher's
envelope; the steps are thrown away if the munition strays AEGISM_PLAN_
CACHE_TOLERANCE m from the path they were worked out on (a rocket still
burning, a missile turning), or after AEGISM_PLAN_CACHE_MAX_AGE s.

The same question is asked of every free munition and launcher again and
again, and for most the answer hasn't changed. So each path also keeps
what is known of one unbroken stretch of its steps ([first step, last
step, first step in it with a shot at all (-1: none), the soonest any of
its shots lands]), and a question goes straight past the part of it with
nothing in it. Walking every step again -- up to one for every second to
impact, for a munition no launcher could take -- cost about 0.2 ms a
question, and under a salvo was the largest share of the coordinator's
time (2026-10-06).

The coordinator's own questions are always answered in full: nothing is
decided on a shot half worked out. The new steps worked out are counted
for it (_plan), and past AEGISM_PLAN_STEPS of them in a run it puts off
whole munitions. Only the work done ahead between its turns (aegism_
intercept_fnc_planAhead) is cut short, when its frame's time is up: []
is returned and the question kept for the next frame.
```

## aegism_intercept_fnc_recordMissileSpeed

`addons/intercept/functions/fn_recordMissileSpeed.sqf`

```text
One AEGIS-M missile's flight (aegism_intercept_fnc_interceptorPFH),
folded into its learned speed curve: its real speed 1, 2, 3... s after
launch joins the samples for that second ("AEGISM_missileSpeedSamples",
per flight config, aegism_intercept_fnc_missileFlightKey, from the start
of each mission), and its
profile is rebuilt from them (aegism_intercept_fnc_missileProfile) --
the speeds AEGIS-M predicts its flights with from then on.

Every flight counts, however it ended: a miss, a lost target, a
retarget or the game's own proximity fuse fly the same speeds as a hit
(the RIM-162's engine-fused kills left it with no speed data at all
while only intercepts counted). Speeds, not flight times: a time also
takes in an off-bore launch's turn, which the lead solver lays out
itself -- a factor measured on flight times counted it twice, and ACE's
RIM-116 was predicted ~9% long once it applied (2026-10-06). This
replaces that factor.

Safeguards (calibration.hpp): a speed outside AEGISM_SPEED_RATIO_MIN-MAX
times the config simulation's at that second is a measuring problem,
not the missile, and isn't used; each second keeps its last AEGISM_
SPEED_SAMPLES; the curve uses a second's median once AEGISM_SPEED_MIN_
SAMPLES flights have reached it, so one odd flight can't move it.

Logged per flight (MISSILE-SPEED, Verbose): its real speed every second
against what was predicted (the curve in use before this flight), and
for an intercept its flight time against the predicted time for the
path it flew -- to check each new missile.
```

## aegism_intercept_fnc_recordMissileTurn

`addons/intercept/functions/fn_recordMissileTurn.sqf`

```text
One AEGIS-M missile's flight, measured (aegism_intercept_fnc_
interceptorPFH), folded into its missile's turn rate: the fastest
sustained turn seen on a flight that had to turn -- launched more than
AEGISM_LAUNCH_ON_BORE degrees off the intercept, so it turned as hard as
it could. A flight launched straight at the intercept only makes small
corrections, which say little about how hard it can turn; it's counted
but doesn't set the rate. The rate only ever rises: each turning flight's
fastest turn is something the missile did.

Safeguards (calibration.hpp), since one bad flight would otherwise set
it for the rest of the mission: a flight whose seeker changed target
isn't used (its turns weren't all toward one intercept), nor a turn
faster than AEGISM_TURN_RATE_MAX (a tumble or a glitch); and once two
turning flights are in, the rate is the second fastest -- no single
flight sets it beyond what another has confirmed.

A missile the game guides has no turn rate in config (maneuvrability has
no unit), so this is where aegism_intercept_fnc_missileAgility gets it.
For an ACE-guided missile it's a check on ACE's own configured rate.

Logged per flight (MISSILE-TURN), with the predicted flight time against
the real one.
```

## aegism_intercept_fnc_selectTarget

`addons/intercept/functions/fn_selectTarget.sqf`

```text
Target selection for one turret of a STANDALONE System (no Site synced
-- a networked System gets its assignment from aegism_intercept_fnc_
assignEngagements instead). Filters the candidates to those on the
doctrine allowlist that at least one of the turret's ready weapons can
engage (aegism_intercept_fnc_canEngage), picks the best per the
doctrine's targetPriority rule, and returns the weapon for it.

A gun keeps its current target while it can still engage it, its own
aim has a solution, and that aim is inside its open-fire range (aegism_
intercept_fnc_openFireRange) -- as a Site's claim does -- instead of
re-picking every tick: under Soonest Impact the shells of one salvo
trade places constantly, and a standalone Praetorian swung 40-127
degrees between six of them in 12s without firing. That check comes
FIRST and alone: only if the current target has to go are the other
candidates evaluated (each one is a full intercept solve). Launchers
always re-pick (the engagement loop reuses a launcher's pick for a
moment and excludes targets its missiles are already flying at).

A gun prefers targets it could open fire on now (intercept inside its
open-fire range) over any it could only track, then the priority rule
decides -- so it doesn't sit holding fire on a far shell while a nearer
one passes through its reach.
```

## aegism_intercept_fnc_targetBody

`addons/intercept/functions/fn_targetBody.sqf`

```text
A target's body as AEGIS-M knows it: its model's bounding box, in its
own model space (x right, y forward, z up), and half its diagonal (the
sphere that holds all of it).

The box is taken from the model's collision (Geometry) layer where it
has one, else the visual layer's. For projectiles the two have always
been identical, and no LOD of one can be hit by a line
(lineIntersectsSurfaces; aegism_intercept_fnc_debugProbeMunitions found
none on R_230mm_HE, 2026-10-06), so the box is the only shape there is
for a munition. How true it is depends on the model: FZA's Hellfire is
0.24 x 1.63 x 0.26 m, about the missile; vanilla's 230 mm rocket is
2.29 x 11.96 x 2.29 m, far wider and longer than the rocket.

A munition is hit where a round's path comes within the round's own
radius of the box (aegism_intercept_fnc_bodyPass), not of the sphere: the
sphere of that rocket's box is 6.19 m, and every round passing within
it -- a .50 with no blast at all -- counted as a kill.

Cached per type ("AEGISM_cacheBody"): it's read every frame. Each type's
boxes are logged once (TARGET-SIZE).
```

## aegism_intercept_fnc_targetHitRadius

`addons/intercept/functions/fn_targetHitRadius.sqf`

```text
A target's physical half-size: half the diagonal of its model's bounding
box (aegism_intercept_fnc_targetBody), a sphere that holds the whole body.

Optionally, as seen along a line of fire: the radius of a disc with the
box's area as seen from that direction (its projected area: each pair of
faces' area times how squarely the line meets them). A munition's body
is its box (aegism_intercept_fnc_bodyPass), and a round has to come
within its own radius of that, not of the sphere -- so this is what a
gun's fire gate (aegism_intercept_fnc_aimWeapon) and open-fire range
(aegism_intercept_fnc_openFireRange) work with against a munition. Side
on, vanilla's 230 mm rocket (2.29 x 11.96 x 2.29 m) is a 2.95 m disc; nose
on, 1.29 m; its sphere is 6.19 m.

The sphere still sizes an aircraft (the engine's own collision decides
hits on those) and CIWS spotting's sense of "through the target"
(aegism_intercept_fnc_ciwsSpot).
```

## aegism_intercept_fnc_threatValue

`addons/intercept/functions/fn_threatValue.sqf`

```text
Pure lookup: maps a classified contact class to a threat-value score
used both by aegism_intercept_fnc_selectTarget's "highestValue" target-
priority rule and by aegism_intercept_fnc_engagementLoop's cost/value
judgment gate (AEGISM_Module_Site's "Enable Cost/Value Judgment"
Personality option) -- kept as a single shared table so the two can
never drift apart from each other.

Missiles outrank platforms since a missed missile is an immediate kill
risk to the defended asset, while a missed aircraft can be re-engaged
on a later pass.
```

## aegism_intercept_fnc_timeToImpact

`addons/intercept/functions/fn_timeToImpact.sqf`

```text
Seconds until a contact reaches the Site: the urgency the coordinator
orders engagements by ("Soonest Impact" Target Priority), queues a
launcher's targets by, and checks every queued shot against.

    unguided munition (artilleryShell, rocket, bomb) - the time its
        drag-free ballistic path comes down through each protected
        vehicle's height (later root of z0 + vz*t - g*t^2/2 = z), the
        soonest across them. An MLRS rocket's arc is decided at launch,
        so this is right from the first detection -- distance / closing
        speed (the old estimate) badly misjudged a rocket still climbing.
    anything else (guided missile, aircraft) - distance to the nearest
        protected vehicle / closing speed toward it.

1e10 when the contact isn't coming (receding, or never descends to the
Site's height).
```

## aegism_intercept_fnc_turretCanPoint

`addons/intercept/functions/fn_turretCanPoint.sqf`

```text
Whether a turret can physically point along a world direction, and the
closest direction it CAN point along: the direction taken into the
vehicle's own model space (so a vehicle on a slope is handled) and
checked against the turret config's own limits (cached, aegism_
intercept_fnc_turretConfig):
    elevation - minElev / maxElev
    traverse - minTurn / maxTurn, degrees from the vehicle's forward,
        positive to the LEFT (verified on the Ghost Hawk's door guns:
        left 15 to 160, right -160 to -15); a span of 360 or more turns
        all the way round
The closest reachable direction clamps each axis to its nearest limit --
where a fixed-bearing or fixed launcher actually sends its missile
(aegism_intercept_fnc_launchSolution).

Why: a CIWS whose aim point was beyond its travel could never get its
barrel within tolerance, so it held fire on that target until the target
landed. The Praetorian 1C (B_AAA_System_01_F, maxElev 85) sat with its
barrel pinned 1.5-4 degrees short of shells coming down steeply beside
it for over 5s each, while other shells it could have reached got
through.
```

## aegism_intercept_fnc_turretConfig

`addons/intercept/functions/fn_turretConfig.sqf`

```text
One turret's config, resolved once per vehicle type + turret path and
cached ("AEGISM_cacheTurrets"). CBA_fnc_getTurret walks the turret tree
in SQF, and turretPoints/turretCanPoint/barrelDirection each did that on
every call -- every frame for a CIWS.

    muzzleGun / muzzleLauncher - the memory point rounds/missiles leave
        from: gunBeg then missileBeg for a gun, the reverse for a
        launcher -- the first that exists in the model ("" if neither)
    camera - the aiming camera lockCameraTo points: uavCameraGunnerPos
        (unmanned turret) or memoryPointGunnerOptics ("" if neither)
    minElev / maxElev - elevation limits, degrees
    barrelPairs - [beginning, end] memory point names of the barrel
        (gunBeg/gunEnd, missileBeg/missileEnd) that both exist
    traverseRate / elevateRate - how fast it turns, degrees per second:
        maxHorizontalRotSpeed / maxVerticalRotSpeed, in the config's own
        unit of 45 degrees per second (0 if not set). Logged once per
        vehicle type and turret (TURRET-RATE).
    minTurn / maxTurn - traverse limits, degrees from the vehicle's
        forward, POSITIVE TO THE LEFT: the Ghost Hawk's left door gun
        is minTurn 15, maxTurn 160, initTurn 90, its right one -160,
        -15, -90 (vanilla Heli_Transport_01 config). A span of 360 or
        more turns all the way round.
    mount - what the turret can do at all: "trainable" (traverses and
        elevates), "elevating" (fixed bearing), "traversing" (fixed
        elevation) or "fixed" (neither -- a vertical launch cell, a
        hull-fixed launcher). An axis moves if its limits span more
        than zero and its rate is set. A weapon on the driver's path
        ([-1]) reads the vehicle's own config, which has neither.
```

## aegism_intercept_fnc_turretPoints

`addons/intercept/functions/fn_turretPoints.sqf`

```text
World positions of a turret's muzzle (where rounds/missiles leave) and
of its aiming camera (what lockCameraTo points), from the turret's own
config memory points (resolved once per vehicle type, aegism_intercept_
fnc_turretConfig).

    muzzle - gunBeg for a gun, missileBeg for a launcher (falling back
        to the other if one is missing)
    camera - uavCameraGunnerPos for an unmanned turret, otherwise
        memoryPointGunnerOptics

Why both: lockCameraTo points the CAMERA at the aim point, and the
barrel runs parallel to it but offset (often by about a metre), so every
round passed the target by that offset -- CIWS rounds landing about a
metre low at all ranges. Solving the lead from the muzzle and shifting
the camera's lock point by (camera - muzzle) makes the barrel line itself
pass through the aim point.

Missing memory points fall back to the turret crewman's eye position
(or the vehicle's position if the turret is empty).
```

## aegism_intercept_fnc_turretSlewTime

`addons/intercept/functions/fn_turretSlewTime.sqf`

```text
Seconds a turret needs to swing its barrel from where it points now to a
world direction: the traverse and elevation it has to cover (in the
vehicle's own frame), each at the turret's own config rate (aegism_
intercept_fnc_turretConfig), whichever takes longer -- the two axes
turn together. The elevation to cover is clamped to the turret's own
limits (a barrel stopped at its limit is as close as it gets). A turret
that doesn't turn all the way round (minTurn / maxTurn span under 360)
can't swing across the gap: its traverse goes the way round inside its
limits, which may be the long way.

Used to judge whether a gun can get onto a target before it lands
(aegism_intercept_fnc_canEngage): a Cheetah handed MLRS warheads 0.7s
from impact with its barrel 30-112 degrees away chased each in turn,
holding fire (LAST-DITCH-HOLD), while carriers it still had time for
came down unengaged.
```

## aegism_intercept_fnc_turretState

`addons/intercept/functions/fn_turretState.sqf`

```text
One weapon turret's runtime state: a HashMap, created on first use, kept
in the System's "AEGISM_turrets" (turret path -> state). Everything AEGIS-M
tracks per turret lives here, instead of one string-keyed object variable
per value (which cost a format call per read, several per aim).

Keys (all optional; readers use getOrDefault):
    lockAt - last time the turret was locked on an aim point
    ciwsAimAt - last CIWS aim (a launcher on a shared turret yields to it)
    aim_ciws / aim_launcher - latest alignment record, per role:
        [angle, tolerance, time, target, feasible, aligned, aimPoint]
    solve - CIWS: latest full aim solve, steered from every frame
        (aegism_intercept_fnc_ciwsTrack)
    trend - launcher: [angle, target, ticks not closing]
    settle - CIWS: [target, best angle, time it last improved]
    lastDitchLogged / lastDitchHeld - CIWS: target last logged
    correction - CIWS spotting correction [lead s, elevation rad]
    track - CIWS: [time, position, velocity, acceleration] the aim was
        solved against, and trackTof: its flight time
    estimate - CIWS spotting estimates, target class -> HashMap
    spotStats - CIWS: burstId -> per-burst spotting stats
    spotSeq - CIWS: rounds fired, for spotting every Nth one
    burst - CIWS: [endsAt, target, burstId]
    tickAt - CIWS: last engagement tick that worked this turret
    trackTarget / tracking - CIWS per-frame tracker target and flag
    rounds / roundsRunning - CIWS rounds in flight (aegism_intercept_fnc_
        ciwsRounds)
    magazineId - CIWS: [magazine id, owner, ammo] for direct fire
    shotAt, holdUntil, spacing, shots, intervalLogged - launcher timing
    capture - fire context for the rounds this turret produces
    fireHold - debug hold (aegism_intercept_fnc_debugSetFireHold)
    standalone_launcher / standalone_ciws - a standalone System's own
        engagement state for this turret, and inFlight_launcher: its
        salvos still flying
```

## aegism_intercept_fnc_weaponKinematics

`addons/intercept/functions/fn_weaponKinematics.sqf`

```text
Everything AEGIS-M reads from config about what a weapon fires, read once
per weapon + magazine and cached ("AEGISM_cacheKinematics"): the lead
solver, aim, fuse and burst all used to re-read these on every call --
ten or more config lookups per aim, every frame.

    v0 - launch speed: CfgMagazines initSpeed, overridden per engine
        rules by CfgWeapons initSpeed (> 0 replaces, < 0 multiplies)
    drag - |CfgAmmo airFriction| (guns; the lead solver's drag model)
    thrust, thrustTime, initTime - a missile's motor: CfgAmmo thrust
        (m/s^2), how long it burns, and how long after launch it lights
    missileFriction - a missile's CfgAmmo airFriction, which is positive
        (a bullet's is negative); 0 with artilleryLock, which the engine
        says ignores it
    timeToLive - how long the round flies (0 = unset): CfgAmmo
        timeToLive, or, for a round that turns into an airburst or
        another round first, until then (aegism_intercept_fnc_ammoBurst)
    lockCone - CfgAmmo missileLockCone (180 if unset)
    fuseDistance - CfgAmmo fuseDistance (arming distance)
    guided - CfgAmmo simulation is shotMissile
    blastRadius - CfgAmmo indirectHitRange
    maxSpeed - CfgAmmo maxSpeed (logged; aegism_intercept_fnc_
        missileProfile doesn't apply it)
    proximity - CfgAmmo proximityExplosionDistance: the round's own
        proximity fuse, m (0 = none)
    burstAt, burstRadius - an airburst round: when it bursts, s, and its
        blast, m (0 = none; aegism_intercept_fnc_ammoBurst)

A missile's flight is simulated from these by aegism_intercept_fnc_
missileProfile.

Each new entry is logged once (KINEMATICS), so the values the solver
works with are in the RPT.
```

## aegism_intercept_fnc_weaponReload

`addons/intercept/functions/fn_weaponReload.sqf`

```text
Whether a turret's weapon can fire right now, and how long until it can,
from the engine's own reload state (weaponState [vehicle, turret,
weapon], Arma 3 2.06+):
    magazineReloadPhase - 1 -> 0 while it loads its next magazine, 0
        once loaded
    roundReloadPhase - 1 -> 0 while it readies the next round (-1 with
        no magazine)

The time left is the phase times how long that reload REALLY takes,
measured here from how fast the phase itself falls (turret state
"reload|<weapon>"); until a tenth of one reload has been watched
(AEGISM_RELOAD_MEASURE_PHASE) it's the config's time -- CfgWeapons
magazineReloadTime, or the fire mode's reloadTime (aegism_intercept_fnc_
fireModeStats). The config's time alone ran short: POOK's 9K332 (reloadTime
6.5) fired every 9.7-10 s, and its S-400 launcher (reloadTime 25) took 37
and 42 s over two reloads, its "ready in" slipping 0.4 s every second.
The coordinator booked each a queue it could never fire, releasing the
claims one after another as their turn failed to come (2026-10-06).
Logged when first measured for a weapon (RELOAD-TIME).

A launcher that has just fired the last missile of a magazine already
shows the next magazine's full count while it's still loading it, and a
fire command then fires nothing: POOK's 9K331 fired six times into its
reload, each taken for a missed shot, and its targets got through
(2026-10-06). POOK's launchers reload for minutes (the S-125's
magazineReloadTime is 900 s).
```

## aegism_intercept_fnc_surfaceStrike

`addons/intercept/functions/fn_surfaceStrike.sqf`

```text
Surface strikes (2026-10-07). From the user: "It was more for launchers
and CIWS, setMissileTargetPos should work for the launchers, just need
CIWS and sams to account for LOFT, ballistic trajectories and the like,
laptop option only and requires another tick box".

Deliberately NOT run through the coordinator, claims or the engagement
loop: all of that is built round an airborne target object (envelope
heights, open-fire range from hit probability, the guns' minimum
elevation, fuses and kill credit), and none of it could be tested for a
point on the ground. A strike is its own small state machine, one
per-frame handler an order:

  aim       surfaceShot solved twice a second, the turret sent there
            (lockTurret); on when the barrel is within 3 deg (launcher) or
            0.3 deg (gun) and the weapon is ready. After 8 s a launcher
            fires as it stands (off-bore), a gun gives up.
  launched  a launcher: the fire command given; "away" when the vehicle's
            Fired handler has taken the capture, failed after 2 s.
  burst     a gun: fired every frame the weapon is ready, as
            aegism_intercept_fnc_ciwsBurst does, for the vehicle's
            ciwsBurstMin.

The turret: "strikeUntil" in its state is kept a second ahead while the
handler runs; aegism_intercept_fnc_engagementLoop skips its idle cue and
holds its engagements ("held") while it's set. "strikeAbort" (Cease Fire)
ends it.

The Fired handler (aegism_intercept_fnc_onSystemFired) sees a capture with
role "strike": a missile goes to aegism_intercept_fnc_strikeMissile, a
gun's rounds are ignored. That branch sits before the Site is marked as
having fired, so a strike doesn't start its alarm.

No crew reaction and no reliability roll: an operator's order, fired when
the weapon is on. One missile or one burst an order.

First test, 13:55 RPT 2026-10-07 (user: "vanilla missiles it works, ace
it does not"):
- game-guided missiles: work (setMissileTargetPos, AGL, every frame).
- ACE RIM-116 (IR seeker) on the plain helper object
  ("Land_HelipadEmpty_F", server-local): eight strikes, each within 1-4 m
  of its point, 6.1 s of flight.
- ACE Patriot: 1263 m off after 55 s. Its seeker is ACE's "DopplerRadar"
  (fnc_seekerType_Doppler, fnc_doppler_onFired, fnc_shouldFilterRadarHit):
  at launch a target that isn't AllVehicles or a CfgAmmo object is thrown
  away; in flight it only keeps a CfgAmmo target as given (anything else
  is searched for again among its lockableTypes, "Air"); and it drops a
  target with ground behind it unless the target's own velocity along the
  line of sight is over minimumSpeedFilter (10 m/s).
  So such a missile is now given a chemlight to chase (a CfgAmmo object,
  harmless, lives 15 min; ACE_G_Chemlight_IR if there is one), moved to
  the loft point every frame like the other helper and given 25 m/s
  toward the missile every frame (along the line of sight, so the
  navigation sees no crossing speed), and shared with reportRemoteTarget
  for a launcher whose own radar is on. UNTESTED.
- Not seen yet: a gun's strike; the Stinger (same IR seeker as the
  RIM-116, so it should be the same).
```

## aegism_intercept_fnc_surfaceShot

`addons/intercept/functions/fn_surfaceShot.sqf`

```text
The check and the aim for a surface strike, used by the order, the strike
itself and a terminal's "has a shot".

Launcher: guided missiles only, with a blast radius (indirectHitRange) of
at least AEGISM_STRIKE_MIN_BLAST, 8 m -- the user: "smaller calibre
missiles like stingers probably should not have surface strike
capability". The game's config has no calibre for a missile; its warhead
is what tells them apart (Titan AA / 70 mm 6 m, RIM-116 10, Zephyr 12,
RIM-162 13, MIM-145 / S-750 30; read 2026-10-07), and 8 is my cut between
the Stinger and the RIM-116. Within its envelope's reach and not under
max(its minimum range, 300 m); the turret is pointed at the first loft
point, or as near as it reaches (the missile turns).

Gun: within the weapon's reach; aimed by aegism_intercept_fnc_compute
LeadPoint exactly as at an air target -- so its drag and drop are the
solver's -- on a server-local object moved to the point
("AEGISM_surfaceProbe"); the turret has to be able to point there; and a
line from the muzzle to 1 m above the point clear of the GROUND only
(terrainIntersectAtASL; the user: "the only thing that should obstruct
the guns is terrain, dont care for trees or structures"), ground nearer
than 15 m to the point counting as the point itself.

All figures in strike.hpp are mine.
```

## aegism_intercept_fnc_strikeMissile

`addons/intercept/functions/fn_strikeMissile.sqf`

```text
Flies a strike's missile. Every frame the object it chases is put above
the aim point by

  1.5 m + min(0.35 x max(0, ground still to cover - 400 m), 3000 m)

For pure pursuit of that point the path from d0 out is about
h(d) = 0.35 d ln(d0 / d): from 5 km it peaks near 640 m, and it arrives
steeply. Inside 400 m there's no loft, so it's flown straight at the
point and isn't still being turned as it lands.

It's set off when it has passed the point (came within 300 m and is going
away) having come within 20 m; a miss is set off 2 s after passing, as a
lost interceptor is. Otherwise the ground does it. The missile is listed
in "AEGISM_strikeMissiles" for the terminals' map.
```
