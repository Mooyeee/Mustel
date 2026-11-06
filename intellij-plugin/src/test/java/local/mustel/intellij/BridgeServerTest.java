package local.mustel.intellij;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.junit.Test;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.channels.Channels;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public final class BridgeServerTest {
    @Test
    public void listsSessionsAndRunsCommands() throws Exception {
        Path directory = Files.createTempDirectory("mustel-bridge-test");
        Path socket = Path.of("/tmp", "mustel-test-" + ProcessHandle.current().pid() + ".sock");
        FakeRegistry registry = new FakeRegistry();
        BridgeServer server = new BridgeServer(registry, directory, socket);

        server.start();
        try {
            JsonObject list = send(socket, "{\"type\":\"list\"}");
            assertTrue(list.get("ok").getAsBoolean());
            assertEquals(
                "session-1",
                list.getAsJsonArray("sessions").get(0).getAsJsonObject().get("id").getAsString()
            );

            JsonObject command = send(
                socket,
                "{\"type\":\"command\",\"sessionId\":\"session-1\",\"command\":\"hotReload\"}"
            );
            assertTrue(command.get("ok").getAsBoolean());
            assertEquals("hotReload", registry.lastCommand);

            JsonObject missing = send(
                socket,
                "{\"type\":\"command\",\"sessionId\":\"missing\",\"command\":\"hotReload\"}"
            );
            assertFalse(missing.get("ok").getAsBoolean());
        } finally {
            server.stop();
            Files.deleteIfExists(directory);
        }
    }

    private static JsonObject send(Path socket, String request) throws Exception {
        try (SocketChannel channel = SocketChannel.open(StandardProtocolFamily.UNIX)) {
            channel.connect(UnixDomainSocketAddress.of(socket));
            BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
                Channels.newOutputStream(channel),
                StandardCharsets.UTF_8
            ));
            writer.write(request);
            writer.write("\n");
            writer.flush();

            BufferedReader reader = new BufferedReader(new InputStreamReader(
                Channels.newInputStream(channel),
                StandardCharsets.UTF_8
            ));
            return JsonParser.parseString(reader.readLine()).getAsJsonObject();
        }
    }

    private static final class FakeRegistry implements SessionRegistry {
        private String lastCommand;

        @Override
        public List<FlutterSessionRegistry.SessionInfo> list() {
            return List.of(new FlutterSessionRegistry.SessionInfo("session-1", "App", "/tmp/app"));
        }

        @Override
        public void perform(String sessionId, String command) {
            if (!"session-1".equals(sessionId)) {
                throw new IllegalArgumentException("Unknown session");
            }
            lastCommand = command;
        }
    }
}
