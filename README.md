# Sonexis

<p align="center">
  <img src="docs/logo.png" width="128">
</p>

<p align="center">
  A node-based audio processing platform for macOS.
</p>

<p align="center">
  <a href="https://sonexis.ink">Website</a> •
  <a href="https://sonexis.ink/download">Download</a>
</p>

---

## Overview

Sonexis is a macOS application that allows users to build custom audio processing pipelines and apply them to audio from any application on their system.

Users create effect graphs visually by connecting audio nodes together. These graphs can contain built-in DSP effects, custom routing configurations, and third-party plugins, allowing everything from simple equalization to complex multi-branch processing chains.

The project began as an attempt to solve a simple problem: most macOS audio software is either designed for professional production workflows or limited to a small set of audio enhancements. Sonexis was built to make advanced audio processing accessible through a flexible visual interface.

Today Sonexis has been downloaded by over 1,000 users.

![Screenshot](docs/main-window.png)

## Features

* Visual node-based audio graph editor
* Real-time audio processing
* System-wide audio routing
* Support for complex multi-branch processing chains
* Third-party plugin integration
* Live graph editing while audio is running
* Preset management and graph persistence

## Technical Challenges

Building Sonexis required solving several problems beyond traditional desktop application development.

### Real-Time DSP

Audio processing occurs under strict latency constraints. Every effect must execute within the available audio callback window without introducing audible artifacts.

### Dynamic Graph Execution

Users can freely modify processing graphs while audio is actively running. Sonexis performs graph validation and applies updates without interrupting playback.

### Audio Routing on macOS

System-wide audio processing is not directly supported by macOS. Sonexis uses a custom routing architecture that allows audio from external applications to be processed through user-defined graphs.

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

Built by Skanda Vyas.
