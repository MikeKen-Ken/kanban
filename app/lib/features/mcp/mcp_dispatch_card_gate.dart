/// Agent 调度批次的一轮一卡程序闸门。
///
/// Worker 持有批次 token，并在每次启动全新 Agent 会话前重置闸门。
/// AI 不接触 token；它仍按 Skill 正常调用 `pick_next_card`，但每个会话最多成功一次。
class McpDispatchCardGate {
  McpDispatchCardGate._();

  static final McpDispatchCardGate instance = McpDispatchCardGate._();

  String? _activeWorkerToken;
  bool _sessionOpen = false;
  bool _pickClaimed = false;
  int _deniedPickCount = 0;
  String? _pickedProjectId;
  String? _pickedCardId;

  String? get activeWorkerToken => _activeWorkerToken;

  void beginBatch(String workerToken) {
    _activeWorkerToken = workerToken;
    _resetSession(open: false);
  }

  void endBatch(String workerToken) {
    if (_activeWorkerToken != workerToken) return;
    _activeWorkerToken = null;
    _resetSession(open: false);
  }

  bool beginAgentSession(String workerToken) {
    if (_activeWorkerToken != workerToken) return false;
    _resetSession(open: true);
    return true;
  }

  McpDispatchPickPermission authorizePick() {
    if (_activeWorkerToken == null) return McpDispatchPickPermission.allowed;
    if (!_sessionOpen) return McpDispatchPickPermission.sessionNotOpen;
    if (_pickClaimed) {
      _deniedPickCount += 1;
      return McpDispatchPickPermission.alreadyClaimed;
    }
    _pickClaimed = true;
    return McpDispatchPickPermission.allowed;
  }

  void recordPickedCard({required String projectId, required String cardId}) {
    if (_activeWorkerToken == null || !_sessionOpen || !_pickClaimed) return;
    _pickedProjectId = projectId;
    _pickedCardId = cardId;
  }

  McpDispatchSessionStatus? sessionStatus(String workerToken) {
    if (_activeWorkerToken != workerToken) return null;
    return McpDispatchSessionStatus(
      sessionOpen: _sessionOpen,
      pickClaimed: _pickClaimed,
      deniedPickCount: _deniedPickCount,
      projectId: _pickedProjectId,
      cardId: _pickedCardId,
    );
  }

  void _resetSession({required bool open}) {
    _sessionOpen = open;
    _pickClaimed = false;
    _deniedPickCount = 0;
    _pickedProjectId = null;
    _pickedCardId = null;
  }
}

enum McpDispatchPickPermission { allowed, sessionNotOpen, alreadyClaimed }

class McpDispatchSessionStatus {
  const McpDispatchSessionStatus({
    required this.sessionOpen,
    required this.pickClaimed,
    required this.deniedPickCount,
    this.projectId,
    this.cardId,
  });

  final bool sessionOpen;
  final bool pickClaimed;
  final int deniedPickCount;
  final String? projectId;
  final String? cardId;

  Map<String, dynamic> toJson() => {
        'sessionOpen': sessionOpen,
        'pickClaimed': pickClaimed,
        'deniedPickCount': deniedPickCount,
        if (projectId != null) 'projectId': projectId,
        if (cardId != null) 'cardId': cardId,
      };
}
