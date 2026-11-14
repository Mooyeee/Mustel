import * as fs from "node:fs";
import * as path from "node:path";

export interface DebugSessionLike {
  workspaceFolder?: { uri: { fsPath: string } };
  configuration: Record<string, unknown>;
}

/**
 * Finds the Flutter app package for a debug session.
 *
 * `workspaceFolder` is the folder that the user opened in VS Code, which in a
 * pub workspace or monorepo is often the outer root rather than the app. The
 * `program` path from the launch configuration is inside the app package, so
 * walking up to its nearest pubspec identifies the actual app.
 */
export function projectPathFor(session: DebugSessionLike): string {
  const workspace = session.workspaceFolder?.uri.fsPath ?? "";
  const cwd = resolvePath(workspace, session.configuration.cwd) ?? workspace;
  const program = resolvePath(cwd, session.configuration.program);
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

export function resolvePath(base: string, value: unknown): string | undefined {
  if (typeof value !== "string" || value.length === 0) {
    return undefined;
  }
  const expanded = value.replace(/\$\{workspaceFolder\}/g, base);
  return path.isAbsolute(expanded)
    ? path.normalize(expanded)
    : path.resolve(base, expanded);
}

export function findPackageRoot(start: string, boundary: string): string | undefined {
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

export function isPubPackage(directory: string): boolean {
  try {
    return fs.statSync(path.join(directory, "pubspec.yaml")).isFile();
  } catch {
    return false;
  }
}
