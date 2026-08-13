#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

/// Returns true if this process should continue starting the app.
/// If another instance is already running, returns false so the caller can
/// forward `astralgame://` via app_links and exit.
bool EnsureSingleInstance();

#endif  // RUNNER_SINGLE_INSTANCE_H_
