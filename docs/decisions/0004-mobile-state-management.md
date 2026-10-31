# ADR 0004: State management in the mobile app

- Status: accepted for Milestone 0, to be revisited at the start of Milestone 1
- Date: 2026-10-31

## Context

`apps/mobile` has one placeholder screen and no state. The task asks for a documented choice anyway, so that Milestone 1 starts from a decision instead of a default.

The state Milestone 1 will hold: the recording in progress, a list of jobs with durable status (queued, processing, completed, retryable, failed, cancelled), pairing status with the Mac, and settings. Job status must survive the app being killed, so its source of truth is local storage, not memory.

Options considered: Flutter's built-in tools (`ChangeNotifier`, `ValueNotifier`, `ListenableBuilder`, constructor injection), Riverpod, and Bloc.

## Decision

Use Flutter's built-in tools and constructor injection. Add no state-management package now.

This is the simplest option that fits. The durable job state lives in a repository class backed by local storage, and the UI listens to a `ChangeNotifier` that wraps it. Widgets get dependencies through constructors, so widget tests pass fakes without a service locator. The spike app already works this way: `SpikeApp` takes its `run` function as a constructor argument, and its widget test passes a fake.

## When to revisit

Move to Riverpod at the start of Milestone 1 if any of these become true:

- More than three screens need the same live state, so passing it through constructors becomes repetitive.
- A screen needs to combine several asynchronous sources (job list, pairing status, settings) and the hand-written combination logic grows past one small class.
- Disposal of listeners becomes a source of bugs.

Riverpod is the planned next step, rather than Bloc, because it provides dependency injection and asynchronous state without extra event classes per screen.
