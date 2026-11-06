package local.mustel.intellij;

import com.intellij.openapi.project.Project;
import com.intellij.openapi.startup.StartupActivity;
import org.jetbrains.annotations.NotNull;

/**
 * Starts the bridge as soon as an IDE project finishes opening.
 */
public final class MustelBridgeStartupActivity implements StartupActivity.DumbAware {
    @Override
    public void runActivity(@NotNull Project project) {
        MustelBridgeService.getInstance().start();
    }
}
