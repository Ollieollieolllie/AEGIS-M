# Changelog

What changed in each released version of AEGIS-M, newest first.

## 1.0.0 (2026-10-09)

The first full release.

### Added

- **Carried Site terminal.** A terminal laptop that is an inventory item
  keeps its connection when it is picked up. Whoever carries it opens it
  from the action menu (**AEGIS-M: Site Terminal (carried)**), in vehicles
  too, and nobody else can use it meanwhile. Put down, it is a terminal
  again where it lies; in a crate, a vehicle or a body it stays connected
  until it is taken out.
- **Fixed in Place**, a laptop option in Eden and Zeus (off by default):
  the laptop can't be picked up.
- **Infinite Ammo**, a Site setting and a vehicle override (off by
  default): launchers and guns are kept topped up. Switched on in
  mid-mission, it refills what was already fired. The time between shots
  doesn't change.
- `ACE-GUIDANCE` in the RPT, once, when ACE's missile guidance isn't what
  flies the missiles.

### Changed

- **ACE3 is heavily recommended, not required.** AEGIS-M is built and
  tested with ACE's missile guidance. Without it the game's own guidance
  flies the missiles, with less reach and accuracy.
- **Surface Strike without ACE.** A launcher whose missile locks on after
  launch (MIM-145 Defender, S-750 Rhea, RIM-162 Centurion) is refused, and
  the terminal says why. Other launchers still strike, less accurately.
- **Alarms are heard out to their Alarm Range.** They used to fade out by
  about 600 m, whatever the range was set to.

### Fixed

- A launcher that shares its turret with a gun (the Cheetah's missiles)
  was counted as cover for an incoming munition while the gun held another
  target, and then never fired. It isn't counted while the gun holds one.
- A missile the game guides that lost its lock flew on past its target.
  It is now ended once it has passed.
- A surface strike's missile that the game guides flew straight on. It is
  now given the strike point as its target.

## 0.1.0 (2026-10-07)

Initial release.
