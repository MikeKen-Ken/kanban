import 'dart:io';

import 'package:path/path.dart' as p;

/// Agent 调度批次的一轮一卡程序闸门。
///
/// 按项目各持有一条 Worker 批次。Worker 持有批次 token，并在每次启动全新
/// Worker 使用私有 token 原子领卡；Agent 只接触绑定 cardId 的临时端点。
class McpDispatchCardGate {
  McpDispatchCardGate._();

  static final McpDispatchCardGate instance = McpDispatchCardGate._();

  final _slotsByToken = <String, _McpDispatchSlot>{};
  final _tokenByProject = <String, String>{};

  /// 仅一条批次时返回其 token；并行时为 null。测试与旧调用可用来判断「是否空闲」。
  String? get activeWorkerToken =>
      _slotsByToken.length == 1 ? _slotsByToken.keys.first : null;

  int get openSessionCount =>
      _slotsByToken.values.where((slot) => slot.sessionOpen).length;

  /// 当前恰好一轮会话开启时，返回该会话所属项目；否则 null。
  String? get singleOpenSessionProjectId {
    String? projectId;
    for (final slot in _slotsByToken.values) {
      if (!slot.sessionOpen) continue;
      if (projectId != null) return null;
      projectId = slot.projectId;
    }
    return projectId;
  }

  void beginBatch(
    String workerToken, {
    required String projectId,
    String? repoPath,
  }) {
    final existingToken = _tokenByProject[projectId];
    if (existingToken != null) {
      _slotsByToken.remove(existingToken);
    }
    _slotsByToken[workerToken] = _McpDispatchSlot(
      workerToken: workerToken,
      projectId: projectId,
      repoPath: repoPath?.trim().isEmpty == true ? null : repoPath?.trim(),
    );
    _tokenByProject[projectId] = workerToken;
  }

  void endBatch(String workerToken) {
    final slot = _slotsByToken.remove(workerToken);
    if (slot == null) return;
    if (_tokenByProject[slot.projectId] == workerToken) {
      _tokenByProject.remove(slot.projectId);
    }
  }

  bool beginAgentSession(String workerToken, {String? sessionId}) {
    final slot = _slotsByToken[workerToken];
    if (slot == null) return false;
    slot.resetSession(open: true, sessionId: sessionId);
    return true;
  }

  McpDispatchPickPermission authorizePick(
    String projectId, {
    String? workerToken,
  }) {
    final token = _tokenByProject[projectId];
    if (token == null) return McpDispatchPickPermission.allowed;
    final slot = _slotsByToken[token];
    if (slot == null) return McpDispatchPickPermission.allowed;
    if (workerToken == null || workerToken != token) {
      return McpDispatchPickPermission.dispatchLocked;
    }
    if (!slot.sessionOpen) return McpDispatchPickPermission.sessionNotOpen;
    if (slot.pickClaimed || slot.pickInFlight) {
      slot.deniedPickCount += 1;
      return McpDispatchPickPermission.alreadyClaimed;
    }
    slot.pickInFlight = true;
    return McpDispatchPickPermission.allowed;
  }

  /// 领卡失败时释放 in-flight，允许本轮重试；已成功领取则不改。
  void releasePickAttempt(String projectId, {String? workerToken}) {
    final token = _tokenByProject[projectId];
    if (token == null) return;
    if (workerToken != null && token != workerToken) return;
    final slot = _slotsByToken[token];
    if (slot == null || slot.pickClaimed) return;
    slot.pickInFlight = false;
  }

  void recordPickedCard({
    required String projectId,
    required String cardId,
    String? workerToken,
  }) {
    final token = _tokenByProject[projectId];
    if (token == null) return;
    if (workerToken != null && token != workerToken) return;
    final slot = _slotsByToken[token];
    if (slot == null || !slot.sessionOpen) return;
    if (!slot.pickInFlight && !slot.pickClaimed) return;
    slot.pickInFlight = false;
    slot.pickClaimed = true;
    slot.pickedProjectId = projectId;
    slot.pickedCardId = cardId;
  }

  /// 非调度会话返回 null（允许测试直接调实现）；调度中则必须是本轮已领取的卡。
  String? authorizePickedCard(String cardId) {
    if (_slotsByToken.isEmpty) return null;
    final id = cardId.trim();
    for (final slot in _slotsByToken.values) {
      if (!slot.sessionOpen) continue;
      if (slot.pickedCardId == id) return null;
    }
    return 'This tool can be called only for the card claimed in the current Worker round';
  }

  /// scoped 端点必须同时匹配 token 与 cardId。
  String? authorizeScopedCard({
    required String workerToken,
    required String cardId,
  }) {
    final slot = _slotsByToken[workerToken];
    if (slot == null || !slot.sessionOpen) {
      return 'The dispatch session does not exist or is closed';
    }
    if (slot.pickedCardId != cardId.trim()) {
      return 'This tool can operate only on the card bound to this session';
    }
    return null;
  }

  /// 完整 MCP 不得修改当前被 dispatch 锁定的卡片。
  String? rejectFullMcpMutation(String cardId, {required String operation}) {
    final slot = _slotForPickedCard(cardId);
    if (slot == null) return null;
    return 'The card is locked by Agent Dispatch. The full MCP cannot call $operation; use the scoped tool for this session.';
  }

  String? projectIdForToken(String workerToken) =>
      _slotsByToken[workerToken]?.projectId;

  String? sessionIdForToken(String workerToken) =>
      _slotsByToken[workerToken]?.sessionId;

  String? cardIdForToken(String workerToken) =>
      _slotsByToken[workerToken]?.pickedCardId;

  String? repoPathForToken(String workerToken) =>
      _slotsByToken[workerToken]?.repoPath;

  /// pending 不持久化 token；私有工具按当前活跃批次的 project/repo 绑定鉴权。
  bool authorizesPending({
    required String workerToken,
    required String projectId,
    required String? repoPath,
  }) {
    final slot = _slotsByToken[workerToken.trim()];
    if (slot == null || slot.projectId != projectId) return false;
    return _normalizeRepo(slot.repoPath) == _normalizeRepo(repoPath);
  }

  void recordBaselineCommitRef(String workerToken, String? commitRef) {
    final slot = _slotsByToken[workerToken];
    if (slot == null) return;
    final value = commitRef?.trim();
    slot.baselineCommitRef = (value == null || value.isEmpty) ? null : value;
  }

  String? baselineCommitRefForCard(String cardId) =>
      _slotForPickedCard(cardId)?.baselineCommitRef;

  String? repoPathForPickedCard(String cardId) {
    final slot = _slotForPickedCard(cardId);
    return slot?.repoPath;
  }

  String? pendingCommitRefForCard(String cardId) {
    return _slotForPickedCard(cardId)?.pendingCommitRef;
  }

  void recordPendingCommitRef({
    required String cardId,
    required String commitRef,
  }) {
    final slot = _slotForPickedCard(cardId);
    if (slot == null) return;
    slot.pendingCommitRef = commitRef.trim();
  }

  void closeAgentSession(String workerToken) {
    final slot = _slotsByToken[workerToken];
    if (slot == null) return;
    slot.sessionOpen = false;
    slot.pickInFlight = false;
  }

  _McpDispatchSlot? _slotForPickedCard(String cardId) {
    final id = cardId.trim();
    for (final slot in _slotsByToken.values) {
      if (slot.sessionOpen && slot.pickedCardId == id) return slot;
    }
    return null;
  }

  McpDispatchSessionStatus? sessionStatus(String workerToken) {
    final slot = _slotsByToken[workerToken];
    if (slot == null) return null;
    return McpDispatchSessionStatus(
      sessionOpen: slot.sessionOpen,
      pickClaimed: slot.pickClaimed,
      deniedPickCount: slot.deniedPickCount,
      projectId: slot.pickedProjectId ?? slot.projectId,
      cardId: slot.pickedCardId,
      sessionId: slot.sessionId,
      baselineCommitRef: slot.baselineCommitRef,
    );
  }

  void debugReset() {
    _slotsByToken.clear();
    _tokenByProject.clear();
  }
}

String? _normalizeRepo(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final normalized = p.normalize(p.absolute(trimmed));
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

class _McpDispatchSlot {
  _McpDispatchSlot({
    required this.workerToken,
    required this.projectId,
    this.repoPath,
  });

  final String workerToken;
  final String projectId;
  final String? repoPath;
  bool sessionOpen = false;
  bool pickInFlight = false;
  bool pickClaimed = false;
  int deniedPickCount = 0;
  String? pickedProjectId;
  String? pickedCardId;
  String? pendingCommitRef;
  String? baselineCommitRef;
  String? sessionId;

  void resetSession({required bool open, String? sessionId}) {
    sessionOpen = open;
    this.sessionId = sessionId;
    pickInFlight = false;
    pickClaimed = false;
    deniedPickCount = 0;
    pickedProjectId = null;
    pickedCardId = null;
    pendingCommitRef = null;
    baselineCommitRef = null;
  }
}

enum McpDispatchPickPermission {
  allowed,
  dispatchLocked,
  sessionNotOpen,
  alreadyClaimed,
}

class McpDispatchSessionStatus {
  const McpDispatchSessionStatus({
    required this.sessionOpen,
    required this.pickClaimed,
    required this.deniedPickCount,
    this.projectId,
    this.cardId,
    this.sessionId,
    this.baselineCommitRef,
  });

  final bool sessionOpen;
  final bool pickClaimed;
  final int deniedPickCount;
  final String? projectId;
  final String? cardId;
  final String? sessionId;
  final String? baselineCommitRef;

  Map<String, dynamic> toJson() => {
        'sessionOpen': sessionOpen,
        'pickClaimed': pickClaimed,
        'deniedPickCount': deniedPickCount,
        if (projectId != null) 'projectId': projectId,
        if (cardId != null) 'cardId': cardId,
        if (sessionId != null) 'sessionId': sessionId,
        if (baselineCommitRef != null) 'baselineCommitRef': baselineCommitRef,
      };
}
