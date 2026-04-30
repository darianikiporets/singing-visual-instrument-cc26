# Prime Spiral Synth

> **Hearing Hidden Mathematics**

An interactive audiovisual instrument built in Godot 4.  
Prime numbers are converted into melodies. Their positions in the Ulam spiral are visualised in real time.  
Every sequence is unique. Every prime has a sound.

---

## Video Demo

https://youtu.be/isDyfyyxkjw?si=M8E5p38K997t2vOs

## What It Does

The project maps prime numbers to musical notes using mathematical rules:

- `prime % scale_length` → selects a note within the chosen scale
- `prime / 20` (clamped) → selects the octave
- Frequency = `440 × 2^((midi − 69) / 12)`

The **Ulam spiral** arranges integers in a square spiral path starting from 1 at the centre. Prime numbers cluster into unexpected diagonal lines — a pattern mathematics cannot fully explain. This project makes those patterns audible.

---

## Features

| Feature | Description |
|---|---|
| Prime melody generator | Sequences of primes mapped to notes |
| Custom input | Type your own primes: `2,3,5,11,17,29` |
| Random mode | Shuffled selection from first 50 primes |
| 8 visual/audio modes | Prime Melody, Chaos, Harmonic, Ambient, Constellation, Fractal, Drum, Duet |
| 5 scales | Major, Minor, Pentatonic, Chromatic, Random |
| 3 waveforms | Sine, Square, Saw — switchable live |
| Keyboard instrument | Every key Q–M plays a different prime note |
| Mouse click | Click any prime on the spiral to play it |
| Twin prime lines | Pairs like (3,5) (11,13) connected by glowing lines |
| Constellation mode | Played primes connected like a star map |
| Fractal mode | Geometry drawn on each active prime |
| Zoom + Pan | Scroll wheel to zoom, right-click drag to pan |
| Bass drone | Continuous root tone following the melody |
| Delay effect | Echo on all modes except Chaos |
| Statistics panel | Live count of primes played, highest prime, average gap, BPM |
| Fullscreen | F11 for performance mode |
| Info panel | Explains prime numbers in-app |

---

## Controls

### Keyboard
| Key | Action |
|---|---|
| `SPACE` | Generate random prime sequence |
| `1` | Sine wave |
| `2` | Square wave |
| `3` | Saw wave |
| `Q W E R T Y U I O P` | Play primes 2 3 5 7 11 13 17 19 23 29 |
| `A S D F G H J K L` | Play primes 31 37 41 43 47 53 59 61 67 |
| `Z X C V B N M` | Play primes 71 73 79 83 89 97 101 |
| `ENTER` | Play typed sequence |

### Mouse
| Action | Result |
|---|---|
| Left click on prime | Play that note |
| Scroll wheel | Zoom in / out |
| Right click + drag | Pan the spiral |
| Hover over prime | Show tooltip |

### Buttons
| Button | Action |
|---|---|
| PLAY | Play typed sequence |
| RANDOM | Generate and play random sequence |
| MODE | Cycle through 8 modes |
| SCALE | Cycle through 5 scales |
| WAVE | Cycle through 3 waveforms |
| DRONE | Toggle bass drone |
| TWINS | Toggle twin prime lines |
| ? | Open info panel |
| BACK | Return to menu |

---

## Modes

| Mode | Description |
|---|---|
| **Prime Melody** | Standard mapping, sine wave, moderate tempo |
| **Chaos** | Faster, saw wave, random pitch variation, more particles |
| **Harmonic** | Chords — root + fifth + third simultaneously |
| **Ambient** | Slow, sine wave, relaxing colours |
| **Constellation** | Played primes connected by glowing lines |
| **Fractal** | Geometric shape drawn on active prime each note |
| **Drum** | Short percussive envelope, square wave |
| **Duet** | Layered tones, chord mode with delay |

---


## How to Run

1. Open Godot 4
2. Import project folder
3. Set `control.tscn` as the main scene
4. Press F5 to run

---

## Live Performance Script

1. Open — explain concept: *"Prime numbers have hidden structure. This project makes it audible."*
2. Press PLAY — sequence starts, spiral lights up
3. Switch MODE to Constellation — primes connect like stars
4. Switch MODE to Chaos — faster, louder, more visual
5. Press BACK → type `2,3,5,11,17,29` → PLAY — your own sequence
6. Press F11 — fullscreen, pure performance
7. Play QWERTY keys — live instrument moment
8. Press ? — show info panel, explain to audience

---

*Numbers are not silent.*


Author: Daria Nikiporets
