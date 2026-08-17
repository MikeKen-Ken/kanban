import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { runVerificationCommand } from "./verification_runner.ts";
import {
  buildWindowsCmdInvocation,
  flutterSdkBinDirs,
  quoteCmdArg,
  resolveWindowsExecutable,
} from "./windows_spawn.ts";

describe("windows_spawn", () => {
  it("引用 cmd 参数时加倍引号并转义 %，避免环境变量展开", () => {
    assert.equal(quoteCmdArg("hello && echo x"), '"hello && echo x"');
    assert.equal(quoteCmdArg("%PATH%"), '"%%PATH%%"');
    assert.equal(quoteCmdArg('say "hi"'), '"say ""hi"""');
  });

  it("lists FLUTTER_ROOT bin as a search dir", () => {
    assert.deepEqual(
      flutterSdkBinDirs({ FLUTTER_ROOT: String.raw`D:\sdk\flutter` }),
      [join(String.raw`D:\sdk\flutter`, "bin")],
    );
    assert.deepEqual(flutterSdkBinDirs({}), []);
    assert.deepEqual(
      flutterSdkBinDirs({ LOCALAPPDATA: String.raw`C:\Users\me\AppData\Local` }),
      [join(String.raw`C:\Users\me\AppData\Local`, "flutter", "bin")],
    );
  });

  it("批处理走 cmd.exe /d /s /v:off，整行再包一层引号", () => {
    const invocation = buildWindowsCmdInvocation(
      String.raw`C:\src\flutter\bin\flutter.bat`,
      ["test", "targeted.dart"],
    );
    assert.match(invocation.command, /cmd\.exe$/i);
    assert.deepEqual(invocation.args.slice(0, 4), ["/d", "/s", "/v:off", "/c"]);
    assert.equal(
      invocation.args[4],
      `""C:\\src\\flutter\\bin\\flutter.bat" "test" "targeted.dart""`,
    );
  });

  it("按 PATHEXT 解析无扩展名的 .cmd", () => {
    if (process.platform !== "win32") return;
    const dir = mkdtempSync(join(tmpdir(), "kanban-win-spawn-"));
    const cmdPath = join(dir, "kanban-verify-probe.cmd");
    writeFileSync(cmdPath, "@echo off\r\necho RAN\r\nexit /b 0\r\n");
    const found = resolveWindowsExecutable("kanban-verify-probe", {
      ...process.env,
      Path: dir,
      PATH: dir,
      PATHEXT: ".COM;.EXE;.BAT;.CMD",
    });
    assert.equal(found?.toLowerCase(), cmdPath.toLowerCase());
  });

  it("prefers FLUTTER_ROOT bin over PATH", () => {
    if (process.platform !== "win32") return;
    const dir = mkdtempSync(join(tmpdir(), "kanban-flutter-root-"));
    const bin = join(dir, "bin");
    mkdirSync(bin, { recursive: true });
    const flutterBat = join(bin, "flutter.bat");
    writeFileSync(flutterBat, "@echo off\r\n");
    const found = resolveWindowsExecutable("flutter", {
      Path: dir,
      PATH: dir,
      FLUTTER_ROOT: dir,
      PATHEXT: ".COM;.EXE;.BAT;.CMD",
    });
    assert.equal(found?.toLowerCase(), flutterBat.toLowerCase());
  });

  it("验证命令能运行 PATH 中的 .cmd，且 && 不会被当成额外命令", async () => {
    if (process.platform !== "win32") return;
    const dir = mkdtempSync(join(tmpdir(), "kanban-win-verify-"));
    writeFileSync(
      join(dir, "kanban-verify-probe.cmd"),
      "@echo off\r\necho RAN\r\nexit /b 0\r\n",
    );
    const originalPath = process.env.Path ?? process.env.PATH ?? "";
    process.env.Path = `${dir};${originalPath}`;
    process.env.PATH = process.env.Path;
    try {
      const result = await runVerificationCommand(
        {
          executable: "kanban-verify-probe",
          args: ["hello && echo PWNED"],
        },
        process.cwd(),
      );
      assert.equal(result.passed, true, result.output);
      assert.match(result.output, /RAN/);
      assert.doesNotMatch(result.output, /PWNED/);
    } finally {
      process.env.Path = originalPath;
      process.env.PATH = originalPath;
    }
  });
});
