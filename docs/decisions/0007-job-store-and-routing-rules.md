# ADR 0007: Job store format and routing rules

- Status: accepted
- Date: 2026-11-01

## Context

Milestone 1 started before the go/no-go table was filled in, at the user's request. The job store and the routing policy don't depend on which models pass the gates, so they come first. Their size thresholds do depend on the spike, so they ship unset.

## Decision: job store

- Jobs are stored in one JSON file (`apps/mobile/lib/src/jobs/job_store.dart`). A job list is small (one entry per recording or transcript), so a database adds a native dependency without a need for queries.
- Every change is written to `jobs.json.tmp` and renamed over `jobs.json`. A crash leaves the old or the new file, not a partial one.
- A change is persisted before `update` returns. The caller marks a job `processing` and only then starts work, so a crash always leaves a job that the next open can find.
- On open, every job still in `processing` becomes `retryable` with the error "interrupted", and that change is written before the store is used.
- A file that can't be parsed throws `JobStoreCorrupt` and is left as it is. The store never replaces it with an empty list.
- Adding a job whose ID already exists returns the stored job. Repeating a submit creates no duplicate.
- Retry defaults are 5 attempts, a 30 s first delay, doubling each attempt, capped at 30 minutes. These are starting values, not measured ones. They are `RetryPolicy` parameters, so tests and a later settings screen can change them.

## Decision: routing rules

`route()` in `apps/mobile/lib/src/routing/routing_policy.dart` applies these rules in order. "The Mac is usable" means the user allows Mac use and a Mac is paired.

| Situation | Mac online | Mac paired but offline | No Mac, or Mac use off |
| --- | --- | --- | --- |
| Phone model not installed | run on Mac | wait for Mac | cannot run |
| Last phone run gave invalid output | run on Mac | wait for Mac | cannot run |
| Last phone run failed | run on Mac | wait for Mac | cannot run |
| Input over the phone size limit | run on Mac | run on phone | run on phone |
| Otherwise | run on phone | run on phone | run on phone |

- The phone is the default. A job the phone can run never waits for the Mac, so the app stays useful when the Mac is off.
- An oversized job runs on the phone when the Mac is not online. The phone result can still be validated, and an invalid result then follows the second row.
- The size limits (`maxPhoneAudioSeconds`, `maxPhoneTranscriptWords`) are null until the spike measures what the phone handles. A null limit never moves a job.
- The function reads nothing but its input. Tests check the decisions above and four invariants over every input combination: same input gives the same route; nothing goes to or waits for the Mac when Mac use is off or no Mac is paired; a job goes to the Mac only when it is online; and a first attempt with a ready phone model always runs somewhere.

## Consequences

- After the go/no-go table is filled in, setting the two limits is a one-line change with a test.
- A JSON file holds all jobs in memory. If the job count grows into the thousands, revisit the format.
