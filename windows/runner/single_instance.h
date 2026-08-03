#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

/// Returns true if this process should continue starting the app.
/// If another instance is already running, brings its window to the front
/// and returns false.
bool EnsureSingleInstance();

#endif  // RUNNER_SINGLE_INSTANCE_H_
