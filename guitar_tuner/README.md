# GuitarTune Pro

A Flutter acoustic/electric guitar tuner with microphone-based live pitch detection.

## Features
- Standard, half-step/full-step down, Drop D, Drop C, Double Drop D
- Open D, Open D minor, Open G, Open C, Open E, Open A, DADGAD
- C Standard, Baritone B, Nashville
- Chromatic mode, selectable strings, live Hz and cents meter
- Local microphone pitch analysis; no account or internet connection required

## Build
The GitHub Actions workflow **Build GuitarTune Pro APK** creates a Flutter Android project, applies this app source, and builds a release APK. Download it from the workflow run's Artifacts section.

## Accuracy notes
The tuner uses windowed autocorrelation with parabolic peak interpolation and short median smoothing. Real-world accuracy depends on microphone response, ambient noise, string harmonics and the instrument. For best results, use a quiet room, mute unused strings and pluck gently. A displayed cent value is an estimate, not a laboratory calibration guarantee.
