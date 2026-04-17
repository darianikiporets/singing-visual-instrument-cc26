# singing-visual-instrument-cc26


**Did you know that your voice could become a real universe?**

Singing Visual Instrument is an interactive audio-visual project built in Godot.
It transforms the user's voice into a dynamic visual and performative experience.

Using real-time microphone input, the system analyses pitch and volume and converts them into:
1)Colour and atmosphere
2)Visual pulses triggered by new notes
3)A dancing character reacting to sound

The result is a living, evolving “universe” generated entirely by your voice.

## Concept

This project explores the idea of using the human voice as both a *musical instrument* and a *creative controller*.

Instead of pressing buttons or playing keys, the user **sings, speaks, or makes sounds** to:

*Generate visuals*  
*Control animation*  
*Influence mood and energy*  


##  Controls

Speak or sing into the microphone;  
Louder sounds → stronger movement and larger visuals;  
Higher pitch → energetic, chaotic animation;  
Lower pitch → calm, smooth motion;  

## Features

Microphone input (real-time)  
Amplitude (volume) analysis  
Pitch detection (approximate)  
Mood-based colour system:  
 Cool colours (blue/purple) → calm / “minor”  
 Warm colours (red/orange/yellow) → energetic / “major”  
Visual pulses triggered by new notes  
Animated character reacting to sound  
Interactive system (not pre-recorded)  

## How It Works

### 1. Audio Input

The microphone captures real-time audio using Godot’s audio system.

### 2. Signal Analysis

* The amplitude (volume) is calculated from the audio buffer
* The pitch is approximated and used to classify sound

### 3. Event System

When a **new note is detected**, the system:

* Triggers visual pulses
* Updates the environment
* Changes the character’s animation

### 4. Visual Mapping

* Volume → size, intensity, movement
* Pitch → animation style
* Mood → background colour

---

## Visual Design

The visual system is inspired by the idea of a **living universe**:

Background colour shifts based on mood
Pulses appear when new sounds are detected
A character “dances” in response to audio
Motion and colour create a sense of rhythm and flow

---

## Project Structure

/scenes

* MainMenu.tscn
* Game.tscn
* Dancer.tscn
* Pulse.tscn

/scripts

* audio_manager.gd
* visual_manager.gd
* dancer.gd

---

## Performance

This project is designed for *live performance*.

## Video Demo

(Insert YouTube video link here)

## Technologies Used

* Godot Engine
* GDScript
* AudioStreamMicrophone
* Real-time audio processing


## Future Improvements

* More accurate pitch detection
* Additional dance animations
* Multiple characters / clones
* Advanced audio effects (reverb, delay)
* Custom UI controls


## Author

Daria Nikiporets

---

## 💬 Final Note

This project demonstrates how **simple human input -> the voice can become a powerful tool for creative expression**, combining sound, visuals, and interaction into one unified system.
