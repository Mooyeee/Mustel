import * as assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import test, { type TestContext } from "node:test";
import { projectPathFor } from "../src/projectPath";

function temporaryDirectory(t: TestContext): string {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "mustel-vscode-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

function writePubspec(directory: string): void {
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, "pubspec.yaml"), "name: app\n");
}

function session(workspace: string, configuration: Record<string, unknown> = {}) {
  return {
    workspaceFolder: { uri: { fsPath: workspace } },
    configuration,
  };
}

test("uses the workspace when the program lives in its lib directory", (t) => {
  const workspace = temporaryDirectory(t);
  writePubspec(workspace);

  assert.equal(
    projectPathFor(session(workspace, { program: "lib/main.dart" })),
    workspace,
  );
});

test("finds a nested app package from the program path", (t) => {
  const workspace = temporaryDirectory(t);
  const app = path.join(workspace, "apps", "selfcare_app");
  writePubspec(app);

  assert.equal(
    projectPathFor(session(workspace, { program: "apps/selfcare_app/lib/main.dart" })),
    app,
  );
});

test("resolves a relative cwd before resolving the program", (t) => {
  const workspace = temporaryDirectory(t);
  const app = path.join(workspace, "apps", "app");
  writePubspec(app);

  assert.equal(
    projectPathFor(
      session(workspace, {
        cwd: "apps/app",
        program: "lib/main.dart",
      }),
    ),
    app,
  );
});

test("expands ${workspaceFolder} in cwd and program", (t) => {
  const workspace = temporaryDirectory(t);
  const app = path.join(workspace, "apps", "app");
  writePubspec(app);

  assert.equal(
    projectPathFor(
      session(workspace, {
        cwd: "${workspaceFolder}/apps/app",
        program: "${workspaceFolder}/apps/app/lib/main.dart",
      }),
    ),
    app,
  );
});

test("supports an absolute program path", (t) => {
  const workspace = temporaryDirectory(t);
  const app = path.join(workspace, "packages", "app");
  writePubspec(app);

  assert.equal(
    projectPathFor(
      session(workspace, {
        program: path.join(app, "lib", "main.dart"),
      }),
    ),
    app,
  );
});

test("falls back to cwd when the launch config has no program", (t) => {
  const workspace = temporaryDirectory(t);
  const app = path.join(workspace, "apps", "app");
  writePubspec(app);

  assert.equal(
    projectPathFor(session(workspace, { cwd: "apps/app" })),
    app,
  );
});

test("falls back to the workspace when no pubspec exists", (t) => {
  const workspace = temporaryDirectory(t);

  assert.equal(
    projectPathFor(session(workspace, { program: "lib/main.dart" })),
    workspace,
  );
});

test("does not resolve a package outside the workspace boundary", (t) => {
  const workspace = temporaryDirectory(t);
  const outside = path.join(path.dirname(workspace), "outside-app");
  writePubspec(outside);
  t.after(() => fs.rmSync(outside, { recursive: true, force: true }));

  assert.equal(
    projectPathFor(session(workspace, { program: "../outside-app/lib/main.dart" })),
    workspace,
  );
});
