# Onboarding Transition Timing Design

## Goal

Make the transition from the first-launch intro to the onboarding flow feel more immediate by speeding up the intro icon shrink-and-fade segment and letting the onboarding UI appear earlier, while keeping the existing hero expansion phase unchanged.

## Constraints

- Do not change the intro hero expansion timing or feel before the shrink begins.
- Only adjust the intro exit segment that starts after the expansion phase.
- Keep the onboarding reveal layered under the intro so both states briefly coexist during handoff.
- Preserve the existing manual onboarding behavior outside the intro-driven transition.

## Design

### Intro exit timing

- Keep the current expansion window untouched.
- Compress the timing after the expansion window so the hero begins shrinking sooner relative to the full transition and reaches its small handoff state earlier.
- Start content fade and overlay fade earlier than before so the intro stops lingering after the hero has already committed to the transition.

### Onboarding reveal timing

- Use the existing `externalRevealProgress` path as the source of truth for intro-driven reveal timing.
- Map that progress into separate reveal curves for onboarding shell opacity, top bar, first-step content, and first-step actions.
- Begin the onboarding shell fade-in during the intro shrink phase instead of waiting until the intro is almost fully gone.

### Validation

- Widget tests must prove the expansion phase is still visually intact early in the transition.
- Widget tests must prove onboarding becomes visible earlier while the intro overlay is still partially visible.
- Run targeted widget tests for intro-to-onboarding handoff behavior.
