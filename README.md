# mpv360.lua

## Interactive 360° Video Viewer for mpv

This script enables interactive viewing of 360° videos in the [mpv](https://mpv.io/) media player. It supports multiple projection formats (equirectangular, dual fisheye, dual half-equirectangular, half-equirectangular, cylindrical, Equi-Angular Cubemap) with full camera control through mouse and keyboard inputs.

## Features

- Equirectangular, Dual Fisheye, Dual Half-Equirectangular, Half-Equirectangular, Cylindrical, Equi-Angular Cubemap
- Six degrees of freedom movement with mouse look and keyboard navigation
- Linear, Mitchell-Netravali and Lanczos filtering
- Left/Right eye selection for dual eye (stereo) formats
- SBS output (Both eyes) for dual eye (stereo) formats
- GLSL shader for optimal performance

## Installation

1. Place the files in your mpv config directory:
   - **Linux/macOS**: `~/.config/mpv/`
   - **Windows**: `%APPDATA%/mpv/`
2. Optionally configure keybindings in `mpv360.conf`

## Configuration

By default, the script doesn't bind any keys. Only script messages are bound.

To enable keybindings:

- Use the default configuration (`mpv360.conf`) or create a custom one.
- Alternatively you can use `input.conf` to bind keys, look at commands table in
  script for available commands.

  Example:

  ```
  Ctrl+r script-binding mpv360/reset-view
  ```

## Usage

- Press configured `toggle` key (default: `Ctrl+e`) to enable/disable 360° mode
- Press `show-help` (default: `Ctrl+t`) to see all controls
- `Ctrl+Left Click` to enable mouse look, `ESC` or `Ctrl+Left Click` to exit
- Use configured keys for camera control (default: `Ctrl+<arrows>`)
- For SBS output, select `Both` eye (`Ctrl+E` to switch eye).
