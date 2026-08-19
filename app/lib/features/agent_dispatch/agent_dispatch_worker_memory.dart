import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Windows `MEMORYSTATUSEX`（kernel32 `GlobalMemoryStatusEx`）。
final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

/// 读取本机物理内存总量（MB）；非 Windows 或调用失败时返回 null。
int? readWindowsTotalPhysicalMemoryMb() {
  if (!Platform.isWindows) return null;
  Pointer<_MemoryStatusEx>? status;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final globalMemoryStatusEx = kernel32.lookupFunction<
        Int32 Function(Pointer<_MemoryStatusEx>),
        int Function(Pointer<_MemoryStatusEx>)>('GlobalMemoryStatusEx');
    status = calloc<_MemoryStatusEx>();
    status.ref.dwLength = sizeOf<_MemoryStatusEx>();
    if (globalMemoryStatusEx(status) == 0) return null;
    final bytes = status.ref.ullTotalPhys;
    if (bytes <= 0) return null;
    return bytes ~/ (1024 * 1024);
  } catch (_) {
    return null;
  } finally {
    if (status != null) calloc.free(status);
  }
}
