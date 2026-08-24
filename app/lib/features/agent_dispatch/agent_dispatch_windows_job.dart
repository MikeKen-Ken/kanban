import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Worker 专用 Windows Job Object。
///
/// 关闭最后一个 Job 句柄时，Windows 会终止 Job 内尚未退出的所有进程。
class AgentDispatchWindowsJob {
  AgentDispatchWindowsJob._(this._handle);

  /// `JobObjectExtendedLimitInformation`；KILL_ON_JOB_CLOSE 不能走 Basic。
  static const _jobObjectExtendedLimitInformation = 9;
  static const _jobObjectLimitKillOnJobClose = 0x00002000;

  /// 允许 Cursor 本地运行时用 CREATE_BREAKAWAY_FROM_JOB 自建沙箱 Job。
  static const _jobObjectLimitBreakawayOk = 0x00000800;
  static const _processTerminate = 0x0001;
  static const _processSetQuota = 0x0100;

  /// x64 上 `JOBOBJECT_EXTENDED_LIMIT_INFORMATION` 为 144 字节。
  static const _extendedLimitInformationSize = 144;
  static const _limitFlagsOffset = 16;

  /// 关闭 Job 时杀掉仍在 Job 内的进程，同时允许子进程主动脱离。
  static const jobLimitFlags =
      _jobObjectLimitKillOnJobClose | _jobObjectLimitBreakawayOk;

  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _createJobObject =
      _kernel32.lookupFunction<_CreateJobObjectNative, _CreateJobObjectDart>(
          'CreateJobObjectW');
  static final _setInformationJobObject = _kernel32.lookupFunction<
      _SetInformationJobObjectNative,
      _SetInformationJobObjectDart>('SetInformationJobObject');
  static final _openProcess = _kernel32
      .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
  static final _assignProcessToJobObject = _kernel32.lookupFunction<
      _AssignProcessToJobObjectNative,
      _AssignProcessToJobObjectDart>('AssignProcessToJobObject');
  static final _closeHandle = _kernel32
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  static final _getLastError = _kernel32
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  int _handle;

  /// 无法绑定时返回 null，让调用方继续使用 `taskkill /T` 作为降级。
  static AgentDispatchWindowsJob? tryAttach(
    int processId, {
    void Function(String message)? onWarning,
  }) {
    if (!Platform.isWindows) return null;

    var jobHandle = 0;
    var processHandle = 0;
    var attached = false;
    Pointer<Uint8>? limitInfo;
    try {
      jobHandle = _createJobObject(
          Pointer<Void>.fromAddress(0), Pointer<Utf16>.fromAddress(0));
      if (jobHandle == 0) {
        onWarning?.call(
          'Unable to create Windows Job Object (error ${_getLastError()}); Worker will use normal process cleanup',
        );
        return null;
      }

      limitInfo = calloc<Uint8>(_extendedLimitInformationSize);
      (limitInfo + _limitFlagsOffset).cast<Uint32>().value = jobLimitFlags;
      if (_setInformationJobObject(
            jobHandle,
            _jobObjectExtendedLimitInformation,
            limitInfo.cast<Void>(),
            _extendedLimitInformationSize,
          ) ==
          0) {
        onWarning?.call(
          'Unable to configure Windows Job Object (error ${_getLastError()}); Worker will use normal process cleanup',
        );
        return null;
      }

      processHandle = _openProcess(
        _processTerminate | _processSetQuota,
        0,
        processId,
      );
      if (processHandle == 0 ||
          _assignProcessToJobObject(jobHandle, processHandle) == 0) {
        onWarning?.call(
          'Unable to add Worker to Windows Job Object (error ${_getLastError()}); Worker will use normal process cleanup',
        );
        return null;
      }
      attached = true;
      return AgentDispatchWindowsJob._(jobHandle);
    } catch (_) {
      onWarning?.call(
          'Windows Job Object initialization failed; Worker will use normal process cleanup');
      return null;
    } finally {
      if (limitInfo != null) calloc.free(limitInfo);
      if (processHandle != 0) _closeHandle(processHandle);
      if (jobHandle != 0 && !attached) _closeHandle(jobHandle);
    }
  }

  /// 释放句柄并让 Windows 终止仍在运行的 Worker 进程树。
  void dispose() {
    if (_handle == 0) return;
    _closeHandle(_handle);
    _handle = 0;
  }
}

typedef _CreateJobObjectNative = IntPtr Function(Pointer<Void>, Pointer<Utf16>);
typedef _CreateJobObjectDart = int Function(Pointer<Void>, Pointer<Utf16>);
typedef _SetInformationJobObjectNative = Uint32 Function(
  IntPtr,
  Uint32,
  Pointer<Void>,
  Uint32,
);
typedef _SetInformationJobObjectDart = int Function(
    int, int, Pointer<Void>, int);
typedef _OpenProcessNative = IntPtr Function(Uint32, Uint32, Uint32);
typedef _OpenProcessDart = int Function(int, int, int);
typedef _AssignProcessToJobObjectNative = Uint32 Function(IntPtr, IntPtr);
typedef _AssignProcessToJobObjectDart = int Function(int, int);
typedef _CloseHandleNative = Uint32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();
