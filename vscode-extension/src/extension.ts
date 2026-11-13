import * as fs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import * as vscode from "vscode";

interface BridgeRequest {
  id?: string;
  type: "list" | "command";
  sessionId?: string;
  command?: "hotReload" | "hotRestart";
}

interface DebugSessionInfo {
  id: string;
  name: string;
  workspace: string;
  projectPath: string;
  type: string;
}

const bridgeDirectory = path.join(
  os.homedir(),
  "Library",
  "Application Support",
  "Mustel",
  "Bridge",
);
const socketPath = `/tmp/mustel-${process.getuid?.() ?? "user"}-${process.pid}.sock`;
const descriptorPath = path.join(bridgeDirectory, `extension-${process.pid}.json`);

let server: net.Server | undefined;
const debugSessions = new Map<string, vscode.DebugSession>();

export function activate(context: vscode.ExtensionContext): void {
  const activeSession = vscode.debug.activeDebugSession;
  if (activeSession?.type === "dart") {
    debugSessions.set(activeSession.id, activeSession);
  }
  context.subscriptions.push(
    vscode.debug.onDidStartDebugSession((session) => {
      if (session.type === "dart") {
        debugSessions.set(session.id, session);
      }
    }),
    vscode.debug.onDidTerminateDebugSession((session) => {
      debugSessions.delete(session.id);
    }),
  );

  fs.mkdirSync(bridgeDirectory, { recursive: true, mode: 0o700 });
  fs.chmodSync(bridgeDirectory, 0o700);

  try {
    fs.unlinkSync(socketPath);
  } catch (error) {
    if (!isMissingFile(error)) {
      throw error;
    }
  }

  server = net.createServer((connection) => {
    connection.setEncoding("utf8");
    let requestData = "";
    let replied = false;
    connection.on("error", (error) => {
      console.error(`Mustel bridge client error: ${error.message}`);
    });
    connection.on("data", (chunk: string) => {
      if (replied) {
        return;
      }
      requestData += chunk;
      if (requestData.length > 16_384) {
        replied = true;
        connection.end(`${JSON.stringify({ ok: false, error: "Bridge request is too large." })}\n`);
        return;
      }

      const newline = requestData.indexOf("\n");
      if (newline === -1) {
        return;
      }

      const requestLine = requestData.slice(0, newline);
      replied = true;
      void handleRequest(requestLine)
        .then((response) => connection.end(`${JSON.stringify(response)}\n`))
        .catch((error: unknown) => {
          const message = error instanceof Error ? error.message : String(error);
          connection.end(`${JSON.stringify({ ok: false, error: message })}\n`);
        });
    });
  });

  server.on("error", (error) => {
    void vscode.window.showErrorMessage(`Mustel bridge failed: ${error.message}`);
  });
  server.listen(socketPath, () => {
    try {
      fs.chmodSync(socketPath, 0o600);
      const descriptor = JSON.stringify({ socketPath, pid: process.pid });
      fs.writeFileSync(descriptorPath, descriptor, { mode: 0o600 });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      void vscode.window.showErrorMessage(`Could not publish the Mustel bridge: ${message}`);
      server?.close();
      removeIfPresent(socketPath);
      removeIfPresent(descriptorPath);
    }
  });

  context.subscriptions.push({
    dispose: () => {
      server?.close();
      removeIfPresent(socketPath);
      removeIfPresent(descriptorPath);
    },
  });
}

export function deactivate(): void {
  server?.close();
  removeIfPresent(socketPath);
  removeIfPresent(descriptorPath);
}

async function handleRequest(line: string): Promise<Record<string, unknown>> {
  let request: BridgeRequest;
  try {
    request = JSON.parse(line) as BridgeRequest;
  } catch {
    throw new Error("Invalid bridge request JSON.");
  }

  if (request.type === "list") {
    return { ok: true, sessions: listDebugSessions() };
  }
  if (request.type !== "command") {
    throw new Error("Unsupported bridge request.");
  }

  if (!request.sessionId || !request.command) {
    throw new Error("A debug session and command are required.");
  }
  if (request.command !== "hotReload" && request.command !== "hotRestart") {
    throw new Error("Unsupported debug command.");
  }

  const session = debugSessions.get(request.sessionId);
  if (!session) {
    throw new Error("The selected Dart/Flutter debug session is no longer active.");
  }

  await session.customRequest(request.command);
  return { ok: true };
}

function listDebugSessions(): DebugSessionInfo[] {
  return [...debugSessions.values()].map((session) => ({
      id: session.id,
      name: session.name,
      workspace: session.workspaceFolder?.uri.fsPath ?? "",
      projectPath: projectPathFor(session),
      type: session.type,
    }));
}

/**
 * Finds the Flutter app package for a debug session.
 *
 * `workspaceFolder` is the folder that the user opened in VS Code, which in a
 * pub workspace or monorepo is often the outer root rather than the app. The
 * `program` path from the launch configuration is inside the app package, so
 * walking up to its nearest pubspec identifies the actual app.
 */
function projectPathFor(session: vscode.DebugSession): string {
  const workspace = session.workspaceFolder?.uri.fsPath ?? "";
  const configuration = session.configuration as {
    cwd?: unknown;
    program?: unknown;
  };
  const cwd = resolvePath(workspace, configuration.cwd) ?? workspace;
  const program = resolvePath(cwd, configuration.program);
  if (program) {
    const packageRoot = findPackageRoot(path.dirname(program), workspace);
    if (packageRoot) {
      return packageRoot;
    }
  }
  if (isPubPackage(cwd)) {
    return cwd;
  }
  return workspace;
}

function resolvePath(base: string, value: unknown): string | undefined {
  if (typeof value !== "string" || value.length === 0) {
    return undefined;
  }
  const expanded = value.replace(/\$\{workspaceFolder\}/g, base);
  return path.isAbsolute(expanded)
    ? path.normalize(expanded)
    : path.resolve(base, expanded);
}

function findPackageRoot(start: string, boundary: string): string | undefined {
  const stop = path.resolve(boundary || start);
  let directory = path.resolve(start);
  while (directory === stop || directory.startsWith(stop + path.sep)) {
    if (isPubPackage(directory)) {
      return directory;
    }
    if (directory === stop) {
      return undefined;
    }
    const parent = path.dirname(directory);
    if (parent === directory) {
      return undefined;
    }
    directory = parent;
  }
  return undefined;
}

function isPubPackage(directory: string): boolean {
  try {
    return fs.statSync(path.join(directory, "pubspec.yaml")).isFile();
  } catch {
    return false;
  }
}

function isMissingFile(error: unknown): boolean {
  return typeof error === "object"
    && error !== null
    && "code" in error
    && error.code === "ENOENT";
}

function removeIfPresent(filePath: string): void {
  try {
    fs.unlinkSync(filePath);
  } catch (error) {
    if (!isMissingFile(error)) {
      void vscode.window.showErrorMessage(
        `Could not remove Mustel bridge file "${filePath}": ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
}
