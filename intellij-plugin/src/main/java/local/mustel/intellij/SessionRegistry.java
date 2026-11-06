package local.mustel.intellij;

import java.util.List;

interface SessionRegistry {
    List<FlutterSessionRegistry.SessionInfo> list();

    void perform(String sessionId, String command) throws Exception;
}
