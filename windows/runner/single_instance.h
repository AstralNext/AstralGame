#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

/// Returns true if this process should continue starting the app.
/// If another instance is already running, forwards any join URI to
/// `%TEMP%\astral_game_pending_uri.txt`, brings the existing window to
/// the front, and returns false.
bool EnsureSingleInstance();

#endif  // RUNNER_SINGLE_INSTANCE_H_
