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
  it("\u5F15\u7528 cmd \u53C2\u6570\u65F6\u52A0\u500D\u5F15\u53F7\u5E76\u8F6C\u4E49 %，\u907F\u514D\u73AF\u5883\u53D8\u91CF\u5C55\u5F00", () => {
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

  it("\u6279\u5904\u7406\u8D70 cmd.exe /d /s /v:off，\u6574\u884C\u518D\u5305\u4E00\u5C42\u5F15\u53F7", () => {
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

  it("\u6309 PATHEXT \u89E3\u6790\u65E0\u6269\u5C55\u540D\u7684 .cmd", () => {
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

  it("\u9A8C\u8BC1\u547D\u4EE4\u80FD\u8FD0\u884C PATH \u4E2D\u7684 .cmd，\u4E14 && \u4E0D\u4F1A\u88AB\u5F53\u6210\u989D\u5916\u547D\u4EE4", async () => {
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
