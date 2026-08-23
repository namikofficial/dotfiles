---
name: android-verification
description: Cost-aware Android verification using JVM tests, screenshots, headless AVDs, and Maestro.
compatibility: opencode
---

Start with host-side checks. Use Roborazzi or existing Compose screenshot tooling when configured. Use one named headless AVD with ADB/Maestro only for device-bound behavior. Do not start a visible emulator or claim physical-device evidence without observing it.
