part of 'webdav_sync_service.dart';

mixin _WebDavSyncScheduler on _WebDavSyncHost {
  /// 取消进行中的同步（含排队中的 pull/push）；本地防抖推送定时器不受影响
  ///
  /// 返回是否确实发出了取消请求。底层传输为协作式中止，当前 HTTP 可能仍跑完，
  /// 但不会再提交成功/失败状态，并可立即再次触发同步。
  bool cancelSync() {
    final inFlight = _syncInFlight || _pushInFlight;
    final hasPending = _pullPending || _pushPending;
    if (status != SyncStatus.syncing && !inFlight && !hasPending) {
      return false;
    }

    _pullPending = false;
    _pullPendingUserInitiated = false;
    _pushPending = false;
    _pushPendingForce = false;

    if (inFlight) {
      _cancelRequested = true;
      _syncRunId++;
      print('已请求取消同步');
    } else {
      print('已取消排队中的同步');
    }

    if (status == SyncStatus.syncing) {
      _setStatus(SyncStatus.idle);
    }
    return true;
  }

  void _ensureNotCancelled([int? runId]) {
    if (_cancelRequested || (runId != null && runId != _syncRunId)) {
      throw const SyncCancelledException();
    }
  }

  bool _shouldCommit(int runId) => !_cancelRequested && runId == _syncRunId;

  void _clearCancelFlag() {
    _cancelRequested = false;
  }

  bool _isRateLimitedError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('429') ||
        message.contains('toomanyrequests') ||
        message.contains('too many requests') ||
        message.contains('rate limit') ||
        message.contains('ratelimit');
  }

  int _pollIntervalSeconds(WebDavConfig config) =>
      WebDavConfig.clampPollIntervalSeconds(config.pollIntervalSeconds);

  Duration? _remainingCooldown([DateTime? now]) {
    final until = _cooldownUntil;
    if (until == null) return null;
    final remaining = until.difference(now ?? DateTime.now());
    if (remaining <= Duration.zero) return null;
    return remaining;
  }

  bool _canStartAutoSync(WebDavConfig config) {
    final now = DateTime.now();
    if (_remainingCooldown(now) != null) return false;
    final last = _lastAttemptAt;
    if (last == null) return true;
    return now.difference(last).inSeconds >= _pollIntervalSeconds(config);
  }

  void _noteAttempt() {
    _lastAttemptAt = DateTime.now();
  }

  void _noteSuccess() {
    _consecutiveFailures = 0;
    _cooldownUntil = null;
  }

  void _noteFailure(Object error) {
    _consecutiveFailures++;
    final rateLimited = _isRateLimitedError(error);
    // 限流从 60s 起跳；普通失败从 30s 起跳；指数退避，上限 10 分钟
    final baseSeconds = rateLimited ? 60 : 30;
    final shift = (_consecutiveFailures - 1).clamp(0, 4);
    final seconds = (baseSeconds * (1 << shift))
        .clamp(baseSeconds, WebDavConfig.maxPollIntervalSeconds);
    _cooldownUntil = DateTime.now().add(Duration(seconds: seconds));
  }

  void _scheduleAfterCooldown(void Function() action) {
    final wait = _remainingCooldown() ?? Duration.zero;
    _cooldownRetryTimer?.cancel();
    _cooldownRetryTimer = Timer(wait, action);
  }

  void schedulePush() {
    final gen = ++_pushScheduleGen;
    _debounceTimer?.cancel();
    unawaited(_armPushDebounce(gen));
    schedulePendingUploadCountRefresh();
  }

  /// 本地变更后短防抖刷新待同步数量，避免与看板突变锁死锁
  void schedulePendingUploadCountRefresh() {
    final gen = ++_pendingCountGen;
    _pendingCountTimer?.cancel();
    _pendingCountTimer = Timer(const Duration(milliseconds: 200), () {
      if (gen != _pendingCountGen) return;
      unawaited(refreshPendingUploadCount());
    });
  }

  /// 相对 SyncBase 统计待上传 JSON 数；未配置同步时为 0
  Future<int> refreshPendingUploadCount() async {
    final config = await _loadConfig();
    if (!config.enabled || !config.isConfigured) {
      _setPendingUploadCount(0);
      return 0;
    }
    try {
      final workspace = await _captureWorkspace();
      final baseline = await _syncBaseStore.load();
      final count = countPendingSyncUploads(
        workspace: workspace,
        baseline: baseline,
      );
      _setPendingUploadCount(count);
    } on Object catch (e) {
      print('刷新待同步数量失败：$e');
    }
    return pendingUploadCount;
  }

  void _setPendingUploadCount(int value) {
    if (pendingUploadCount == value) return;
    pendingUploadCount = value;
    if (!_pendingCountController.isClosed) {
      _pendingCountController.add(value);
    }
  }

  Future<void> _armPushDebounce(int gen) async {
    final config = await _loadConfig();
    if (gen != _pushScheduleGen) return;

    final seconds = WebDavConfig.clampPushDebounceSeconds(
      config.pushDebounceSeconds,
    );
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(seconds: seconds), () {
      if (gen != _pushScheduleGen) return;
      final wait = _remainingCooldown();
      if (wait != null) {
        _scheduleAfterCooldown(() {
          unawaited(_pushNow());
        });
        return;
      }
      unawaited(_pushNow());
    });
  }

  void _drainPendingWork({bool forceFallback = false}) {
    final pull = _pullPending;
    final pullUser = _pullPendingUserInitiated;
    final push = _pushPending;
    final pushForce = _pushPendingForce || forceFallback;
    _pullPending = false;
    _pullPendingUserInitiated = false;
    _pushPending = false;
    _pushPendingForce = false;

    if (!pull && !push) return;

    final wait = _remainingCooldown();
    void run() {
      if (pull) {
        unawaited(_pullAndMerge(userInitiated: pullUser));
      } else if (push) {
        unawaited(_pushNow(force: pushForce));
      }
    }

    // 手动同步排队立即执行；自动推送仍遵守冷却
    if (wait != null && !(pull && pullUser)) {
      _scheduleAfterCooldown(run);
      return;
    }
    Timer.run(run);
  }

  void startPolling() {
    stopPolling();
    _pollingEnabled = true;
    _armNextPoll();
  }

  void _armNextPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_pollingEnabled) return;
    unawaited(_scheduleNextPoll());
  }

  Future<void> _scheduleNextPoll() async {
    if (!_pollingEnabled) return;
    final config = await _loadConfig();
    if (!_pollingEnabled || !config.enabled || !config.autoPull) return;

    final interval = Duration(seconds: _pollIntervalSeconds(config));
    var delay = interval;
    final cooldown = _remainingCooldown();
    if (cooldown != null && cooldown > delay) {
      delay = cooldown;
    }

    if (!_pollingEnabled) return;
    _pollTimer = Timer(delay, () async {
      try {
        if (!_pollingEnabled) return;
        final latest = await _loadConfig();
        if (!_pollingEnabled || !latest.enabled || !latest.autoPull) return;
        if (_canStartAutoSync(latest)) {
          await _pullAndMerge();
        }
      } finally {
        if (_pollingEnabled) {
          _armNextPoll();
        }
      }
    });
  }

  void stopPolling() {
    _pollingEnabled = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
