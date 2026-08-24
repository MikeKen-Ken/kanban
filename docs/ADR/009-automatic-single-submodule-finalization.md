# ADR-009: Automatic finalization of one changed submodule

- Status: accepted
- Date: 2026-08-24

## Decision

Agent Dispatch treats the configured repository as a workspace. When its normal
two-phase finalization finds exactly one dirty direct Git submodule and the
parent repository has no changed path other than that submodule gitlink, it
commits the submodule first and then commits the parent gitlink update. Both
commits carry the session/card trailers.

If zero or multiple submodules are dirty, the parent has other changes, or a
sensitive path is involved, Dispatch does not infer a multi-repository scope.
It preserves the worktree and stops for manual resolution.

## Consequences

Users keep one workspace path for common submodule projects. The existing
single-repository flow remains unchanged, while ambiguous multi-repository
commits remain blocked rather than being silently combined.
