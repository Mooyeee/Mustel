package local.mustel.intellij;

import com.intellij.openapi.Disposable;
import com.intellij.openapi.application.ApplicationManager;
import com.intellij.openapi.diagnostic.Logger;

/**
 * Owns the bridge server for the lifetime of the IDE application.
 */
public final class MustelBridgeService implements Disposable {
    private static final Logger LOG = Logger.getInstance(MustelBridgeService.class);

    private BridgeServer server;

    public static MustelBridgeService getInstance() {
        return ApplicationManager.getApplication().getService(MustelBridgeService.class);
    }

    public synchronized void start() {
        if (server != null) {
            return;
        }
        try {
            BridgeServer bridgeServer = new BridgeServer(new FlutterSessionRegistry());
            bridgeServer.start();
            server = bridgeServer;
        } catch (Exception error) {
            LOG.warn("Could not start the Mustel bridge", error);
        }
    }

    @Override
    public synchronized void dispose() {
        if (server != null) {
            server.stop();
            server = null;
        }
    }
}
