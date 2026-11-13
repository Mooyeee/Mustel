package local.mustel.intellij;

import com.intellij.execution.configurations.GeneralCommandLine;
import com.intellij.execution.ui.RunContentDescriptor;
import com.intellij.execution.ui.RunContentManager;
import com.intellij.openapi.application.ApplicationManager;
import com.intellij.openapi.fileEditor.FileDocumentManager;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.project.ProjectManager;
import io.flutter.run.daemon.DaemonApi;
import io.flutter.run.daemon.FlutterApp;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Finds running Flutter apps in the IDE and forwards reload/restart commands to them.
 */
public final class FlutterSessionRegistry implements SessionRegistry {
    public record SessionInfo(String id, String name, String workspace, String projectPath) {
    }

    @Override
    public List<SessionInfo> list() {
        List<SessionInfo> sessions = new ArrayList<>();
        ApplicationManager.getApplication().invokeAndWait(() -> {
            for (Project project : ProjectManager.getInstance().getOpenProjects()) {
                for (FlutterApp app : FlutterApp.allFromProjectProcess(project)) {
                    if (!app.isStarted()) {
                        continue;
                    }
                    sessions.add(new SessionInfo(
                        idFor(project, app),
                        displayName(project, app),
                        workspace(project),
                        projectPath(project, app)
                    ));
                }
            }
        });
        return sessions;
    }

    @Override
    public void perform(String sessionId, String command) throws Exception {
        FlutterApp app = find(sessionId);
        if (app == null || !app.isStarted()) {
            throw new IllegalStateException("The selected Flutter run is no longer active.");
        }
        if ("hotReload".equals(command) && !app.appSupportsHotReload()) {
            throw new IllegalStateException("This Flutter run does not support hot reload.");
        }

        AtomicReference<CompletableFuture<DaemonApi.RestartResult>> futureRef = new AtomicReference<>();
        ApplicationManager.getApplication().invokeAndWait(() -> {
            FileDocumentManager.getInstance().saveAllDocuments();
            if ("hotReload".equals(command)) {
                futureRef.set(app.performHotReload(true, "Mustel"));
            } else {
                futureRef.set(app.performRestartApp("Mustel"));
                app.device().bringToFront();
            }
        });

        CompletableFuture<DaemonApi.RestartResult> future = futureRef.get();
        if (future == null) {
            throw new IllegalStateException("Could not start the Flutter command.");
        }

        DaemonApi.RestartResult result = future.get(110, TimeUnit.SECONDS);
        if (!result.ok()) {
            throw new IllegalStateException(
                result.getMessage() == null ? "The Flutter command failed." : result.getMessage()
            );
        }
    }

    private FlutterApp find(String sessionId) {
        AtomicReference<FlutterApp> result = new AtomicReference<>();
        ApplicationManager.getApplication().invokeAndWait(() -> {
            for (Project project : ProjectManager.getInstance().getOpenProjects()) {
                for (FlutterApp app : FlutterApp.allFromProjectProcess(project)) {
                    if (!app.isStarted()) {
                        continue;
                    }
                    if (idFor(project, app).equals(sessionId)) {
                        result.set(app);
                        return;
                    }
                }
            }
        });
        return result.get();
    }

    private static String idFor(Project project, FlutterApp app) {
        return project.getLocationHash() + ":" + System.identityHashCode(app);
    }

    private static String displayName(Project project, FlutterApp app) {
        for (RunContentDescriptor descriptor : RunContentManager.getInstance(project).getAllDescriptors()) {
            if (descriptor.getProcessHandler() == app.getProcessHandler()) {
                String name = descriptor.getDisplayName();
                if (name != null && !name.isBlank()) {
                    return name;
                }
            }
        }
        return project.getName() + " · " + app.device().deviceName();
    }

    private static String workspace(Project project) {
        String path = project.getBasePath();
        return path == null ? "" : path;
    }

    /**
     * Returns the Flutter app package for the run. The project base path is the
     * folder opened in the IDE, which in a pub workspace can be the outer root,
     * so prefer the app's own pub root.
     */
    private static String projectPath(Project project, FlutterApp app) {
        GeneralCommandLine command = app.getCommand();
        if (command != null) {
            File workDirectory = command.getWorkDirectory();
            String workPath = workDirectory == null ? null : workDirectory.getPath();
            String target = targetPath(command.getParametersList().getList());
            if (workPath != null && target != null) {
                Path targetPath = Paths.get(workPath).resolve(target).normalize();
                String root = pubspecRoot(targetPath);
                if (root != null) {
                    return root;
                }
            }
            if (workPath != null) {
                String root = pubspecRoot(Paths.get(workPath));
                if (root != null) {
                    return root;
                }
            }
        }
        return workspace(project);
    }

    private static String targetPath(List<String> arguments) {
        for (int index = 0; index < arguments.size(); index++) {
            String argument = arguments.get(index);
            if ("-t".equals(argument) || "--target".equals(argument)) {
                int next = index + 1;
                if (next < arguments.size()) {
                    return arguments.get(next);
                }
            }
            if (argument.startsWith("--target=")) {
                return argument.substring("--target=".length());
            }
            if (argument.startsWith("-t") && argument.length() > 2) {
                return argument.substring(2);
            }
        }
        return null;
    }

    private static String pubspecRoot(Path start) {
        Path directory = Files.isDirectory(start) ? start : start.getParent();
        while (directory != null) {
            if (Files.isRegularFile(directory.resolve("pubspec.yaml"))) {
                return directory.toString();
            }
            directory = directory.getParent();
        }
        return null;
    }
}
