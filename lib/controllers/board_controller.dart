import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/kanban_models.dart';
import '../webdav_sync/webdav_config.dart';
import '../webdav_sync/webdav_sync_service.dart';

class BoardController extends ChangeNotifier {
  BoardController._({
    required BoardRepository repository,
    required WebDavSyncService syncService,
  })  : _repository = repository,
        _syncService = syncService;

  final BoardRepository _repository;
  final WebDavSyncService _syncService;

  KanbanBoard? board;
  WebDavConfig webDavConfig = WebDavConfig.empty;
  bool isLoading = true;
  String? errorMessage;

  SyncStatus get syncStatus => _syncService.status;
  String? get syncError => _syncService.lastError;
  DateTime? get lastSyncedAt => _syncService.lastSyncedAt;
  Stream<SyncStatus> get syncStatusStream => _syncService.statusStream;

  static Future<BoardController> create() async {
    final prefs = await SharedPreferences.getInstance();
    final repository = BoardRepository(prefs);
    late BoardController controller;
    final syncService = WebDavSyncService(
      loadConfig: () async => controller.webDavConfig,
      loadBoard: () async => controller.board ?? repository.loadBoard(),
      saveBoard: (b) async {
        await repository.saveBoard(b);
        controller.board = b;
      },
    );
    controller = BoardController._(
      repository: repository,
      syncService: syncService,
    );
    await controller._init();
    return controller;
  }

  Future<void> _init() async {
    try {
      webDavConfig = await _repository.loadWebDavConfig();
      board = await _repository.loadBoard();
      if (webDavConfig.enabled && webDavConfig.isConfigured) {
        await _syncService.pullAndMerge();
        board = await _repository.loadBoard();
        _syncService.startPolling();
      }
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _persistAndSync(KanbanBoard next) async {
    board = next;
    await _repository.saveBoard(next);
    notifyListeners();
    _syncService.schedulePush();
  }

  KanbanBoard _bump(KanbanBoard current) {
    return current.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      revision: current.revision + 1,
    );
  }

  Future<void> updateTitle(String title) async {
    if (board == null) return;
    await _persistAndSync(_bump(board!.copyWith(title: title)));
  }

  Future<void> addColumn(String title) async {
    if (board == null) return;
    final columns = [...board!.columns];
    columns.add(
      KanbanColumn(
        id: const Uuid().v4(),
        title: title,
        order: columns.length,
        cards: [],
      ),
    );
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> renameColumn(String columnId, String title) async {
    if (board == null) return;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      return col.copyWith(title: title);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> deleteColumn(String columnId) async {
    if (board == null) return;
    final columns =
        board!.columns.where((col) => col.id != columnId).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> addCard(String columnId, String title, {String? description}) async {
    if (board == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      final cards = [
        ...col.cards,
        KanbanCard(
          id: const Uuid().v4(),
          title: title,
          description: description,
          order: col.cards.length,
          createdAt: now,
        ),
      ];
      return col.copyWith(cards: cards);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> updateCard(
    String columnId,
    String cardId, {
    String? title,
    String? description,
  }) async {
    if (board == null) return;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      final cards = col.cards.map((card) {
        if (card.id != cardId) return card;
        return card.copyWith(
          title: title ?? card.title,
          description: description ?? card.description,
        );
      }).toList();
      return col.copyWith(cards: cards);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> deleteCard(String columnId, String cardId) async {
    if (board == null) return;
    final columns = board!.columns.map((col) {
      if (col.id != columnId) return col;
      final cards = col.cards.where((c) => c.id != cardId).toList();
      return col.copyWith(cards: cards);
    }).toList();
    await _persistAndSync(_bump(board!.copyWith(columns: columns)));
  }

  Future<void> moveCard({
    required String cardId,
    required String fromColumnId,
    required String toColumnId,
    required int toIndex,
  }) async {
    if (board == null) return;
    KanbanCard? moving;
    final stripped = board!.columns.map((col) {
      if (col.id != fromColumnId) return col;
      final remaining = <KanbanCard>[];
      for (final card in col.cards) {
        if (card.id == cardId) {
          moving = card;
        } else {
          remaining.add(card);
        }
      }
      return col.copyWith(cards: remaining);
    }).toList();

    if (moving == null) return;

    final inserted = stripped.map((col) {
      if (col.id != toColumnId) return col;
      final cards = [...col.cards];
      final index = toIndex.clamp(0, cards.length);
      cards.insert(index, moving!);
      return col.copyWith(cards: cards);
    }).toList();

    await _persistAndSync(_bump(board!.copyWith(columns: inserted)));
  }

  Future<void> saveWebDavConfig(WebDavConfig config) async {
    webDavConfig = config;
    await _repository.saveWebDavConfig(config);
    if (config.enabled && config.isConfigured) {
      _syncService.startPolling();
      await _syncService.pullAndMerge();
      board = await _repository.loadBoard();
    } else {
      _syncService.stopPolling();
    }
    notifyListeners();
  }

  Future<bool> testWebDav(WebDavConfig config) {
    return _syncService.testConnection(config);
  }

  Future<void> syncNow() async {
    await _syncService.pullAndMerge();
    board = await _repository.loadBoard();
    notifyListeners();
  }

  @override
  void dispose() {
    _syncService.dispose();
    super.dispose();
  }
}
