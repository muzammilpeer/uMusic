# ADR 0001: Apple Platform Baseline

- Status: Provisional
- Date: 2026-08-09

## Context

SwiftUI navigation, concurrency, Core Data, background URLSession, AVFoundation, and Core ML must behave consistently while supporting useful older hardware.

## Decision

Use iOS/iPadOS 17 and macOS 14 as the provisional minimum. Nominate an oldest supported physical iPhone before accepting performance budgets.

## Alternatives

- Newer-only targets reduce compatibility work but unnecessarily shrink private-device support.
- Older targets increase availability branches and validation cost before a concrete need exists.

## Consequences

Sprint 1 must centralize availability adaptations. This ADR becomes Accepted only after product-owner confirmation and minimum-device nomination.

