# Sonexis

<p align="center">
  <img src="docs/logo.png" width="128">
</p>

<p align="center">
  Shape your system audio.
</p>

<p align="center">
  <a href="https://sonexis.ink">Website</a> •
</p>

---

## Overview

Sonexis is a macOS application that allows users to build custom audio processing pipelines and apply them to audio from any application on their system.

Users create effect graphs visually by connecting audio nodes together. These graphs can contain built-in DSP effects, custom routing configurations, and third-party plugins, allowing everything from simple equalization to complex multi-branch processing chains.

Today Sonexis has been downloaded by over 1,000 users.

## Architecture

At a high level, Sonexis consists of:

* Graph editor for creating processing pipelines
* Audio engine responsible for graph execution
* DSP effect framework
* Plugin hosting layer
* Audio routing subsystem

```text
Application Audio
        │
        ▼
 Audio Routing
        │
        ▼
 Processing Graph
        │
 ┌──────┼──────┐
 ▼      ▼      ▼
EQ   Reverb  Delay
 └──────┼──────┘
        ▼
 Audio Output
```

## Download

Sonexis is available for macOS.

https://sonexis.ink

## Author

Built by Skanda Vyas Srinivasan.
