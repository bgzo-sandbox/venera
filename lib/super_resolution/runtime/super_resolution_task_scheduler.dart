import 'dart:async';
import 'dart:collection';

/// Lightweight scheduler for super resolution tasks.
///
/// It solves two runtime problems for the reader:
/// - repeated requests for the same cache key should share one in-flight task
/// - expensive image processing should not spawn unlimited concurrent work
class SuperResolutionTaskScheduler {
  SuperResolutionTaskScheduler({this.maxConcurrentTasks = 2});

  /// Hard cap for concurrently running processing jobs.
  final int maxConcurrentTasks;

  final Map<String, Future<Object?>> _inflightTasks = {};
  final Queue<_QueuedSuperResolutionTask> _taskQueue =
      Queue<_QueuedSuperResolutionTask>();
  int _runningTasks = 0;

  int get runningTasks => _runningTasks;

  int get queuedTasks => _taskQueue.length;

  /// Enqueues work and dedupes by request key.
  ///
  /// Callers that schedule the same key while the task is still running receive
  /// the same future instead of launching duplicate processing. When the
  /// generic type [T] is nullable, an in-flight task that completed with a
  /// `null` result is replayed as `null` without casting errors.
  Future<T> schedule<T>(String key, Future<T> Function() task) {
    final inflight = _inflightTasks[key];
    if (inflight != null) {
      // Replay the in-flight result. For nullable [T] a completed `null` is
      // replayed as `null` without casting errors; for non-nullable [T] the
      // original task can never complete with `null`, so the cast is safe.
      return inflight
          .then<dynamic>((value) => value)
          .then<T>((value) => value as T);
    }

    final completer = Completer<T>();
    _inflightTasks[key] = completer.future.then<Object?>((value) => value);

    _taskQueue.add(
      _QueuedSuperResolutionTask(() async {
        _runningTasks++;
        try {
          final result = await task();
          completer.complete(result);
        } catch (e, s) {
          completer.completeError(e, s);
        } finally {
          _inflightTasks.remove(key);
          _runningTasks--;
          _startNextTask();
        }
      }),
    );

    _startNextTask();
    return completer.future;
  }

  void _startNextTask() {
    if (_runningTasks >= maxConcurrentTasks || _taskQueue.isEmpty) {
      return;
    }

    final task = _taskQueue.removeFirst();
    task.run();
  }
}

/// Internal queue item wrapper so scheduling state stays separate from task
/// execution logic.
class _QueuedSuperResolutionTask {
  _QueuedSuperResolutionTask(this.run);

  final Future<void> Function() run;
}
