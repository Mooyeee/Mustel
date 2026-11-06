package local.mustel.intellij;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.channels.Channels;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Publishes a descriptor and a Unix domain socket that Mustel uses to query and control Flutter runs.
 */
final class BridgeServer {
    private static final Logger LOG = Logger.getLogger(BridgeServer.class.getName());
    private static final Gson GSON = new Gson();
    private static final int MAX_REQUEST_CHARS = 16_384;

    private final SessionRegistry registry;
    private final Path bridgeDirectory;
    private final Path socketPathOverride;
    private final ExecutorService executor = Executors.newCachedThreadPool(runnable -> {
        Thread thread = new Thread(runnable, "Mustel bridge");
        thread.setDaemon(true);
        return thread;
    });

    private ServerSocketChannel server;
    private Path socketPath;
    private Path descriptorPath;

    BridgeServer(SessionRegistry registry) {
        this(registry, defaultBridgeDirectory(), null);
    }

    BridgeServer(SessionRegistry registry, Path bridgeDirectory, Path socketPathOverride) {
        this.registry = registry;
        this.bridgeDirectory = bridgeDirectory;
        this.socketPathOverride = socketPathOverride;
    }

    synchronized void start() throws IOException {
        if (server != null) {
            return;
        }

        long pid = ProcessHandle.current().pid();
        long uid = currentUid();
        Files.createDirectories(bridgeDirectory);
        Files.setPosixFilePermissions(bridgeDirectory, PosixFilePermissions.fromString("rwx------"));

        socketPath = socketPathOverride != null
            ? socketPathOverride
            : Paths.get("/tmp", "mustel-" + uid + "-" + pid + ".sock");
        Files.deleteIfExists(socketPath);

        ServerSocketChannel channel = ServerSocketChannel.open(StandardProtocolFamily.UNIX);
        channel.bind(UnixDomainSocketAddress.of(socketPath));
        Files.setPosixFilePermissions(socketPath, PosixFilePermissions.fromString("rw-------"));
        server = channel;

        descriptorPath = bridgeDirectory.resolve("intellij-" + pid + ".json");
        String descriptor = GSON.toJson(new Descriptor(socketPath.toString(), pid));
        Files.writeString(
            descriptorPath,
            descriptor,
            StandardCharsets.UTF_8,
            StandardOpenOption.CREATE,
            StandardOpenOption.TRUNCATE_EXISTING,
            StandardOpenOption.WRITE
        );
        Files.setPosixFilePermissions(descriptorPath, PosixFilePermissions.fromString("rw-------"));

        executor.submit(this::acceptLoop);
        LOG.info("Mustel bridge listening on " + socketPath);
    }

    synchronized void stop() {
        ServerSocketChannel channel = server;
        server = null;
        if (channel != null) {
            try {
                channel.close();
            } catch (IOException error) {
                LOG.log(Level.WARNING, "Could not close the Mustel bridge socket", error);
            }
        }

        executor.shutdownNow();
        try {
            executor.awaitTermination(1, TimeUnit.SECONDS);
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
        }

        if (socketPath != null) {
            try {
                Files.deleteIfExists(socketPath);
            } catch (IOException error) {
                LOG.log(Level.WARNING, "Could not remove the Mustel bridge socket", error);
            }
            socketPath = null;
        }
        if (descriptorPath != null) {
            try {
                Files.deleteIfExists(descriptorPath);
            } catch (IOException error) {
                LOG.log(Level.WARNING, "Could not remove the Mustel bridge descriptor", error);
            }
            descriptorPath = null;
        }
    }

    private void acceptLoop() {
        while (true) {
            ServerSocketChannel channel = server;
            if (channel == null || !channel.isOpen()) {
                return;
            }
            try {
                SocketChannel connection = channel.accept();
                if (executor.isShutdown()) {
                    connection.close();
                    return;
                }
                executor.submit(() -> handle(connection));
            } catch (IOException error) {
                if (channel.isOpen()) {
                    LOG.log(Level.WARNING, "Mustel bridge accept failed", error);
                }
                return;
            }
        }
    }

    private void handle(SocketChannel connection) {
        try (connection) {
            try {
                BufferedReader reader = new BufferedReader(new InputStreamReader(
                    Channels.newInputStream(connection),
                    StandardCharsets.UTF_8
                ));
                String line = reader.readLine();
                if (line == null) {
                    return;
                }
                if (line.length() > MAX_REQUEST_CHARS) {
                    respond(connection, error("Bridge request is too large."));
                    return;
                }

                JsonObject request = JsonParser.parseString(line).getAsJsonObject();
                respond(connection, handleRequest(request));
            } catch (Throwable failure) {
                boolean expected = failure instanceof IllegalArgumentException
                    || failure instanceof IllegalStateException;
                LOG.log(expected ? Level.FINE : Level.WARNING, "Mustel bridge request failed", failure);
                try {
                    respond(connection, error(failure.getMessage()));
                } catch (IOException ignored) {
                    // The client may have disconnected before we could reply.
                }
            }
        } catch (IOException ignored) {
            // The connection could not be closed cleanly.
        }
    }

    private JsonObject handleRequest(JsonObject request) throws Exception {
        String type = request.has("type") ? request.get("type").getAsString() : "";
        if ("list".equals(type)) {
            JsonObject response = new JsonObject();
            response.addProperty("ok", true);
            response.add("sessions", GSON.toJsonTree(registry.list()));
            return response;
        }

        if (!"command".equals(type)) {
            throw new IllegalArgumentException("Unsupported bridge request.");
        }

        String sessionId = request.has("sessionId") ? request.get("sessionId").getAsString() : null;
        String command = request.has("command") ? request.get("command").getAsString() : null;
        if (sessionId == null || command == null) {
            throw new IllegalArgumentException("A debug session and command are required.");
        }
        if (!"hotReload".equals(command) && !"hotRestart".equals(command)) {
            throw new IllegalArgumentException("Unsupported debug command.");
        }

        registry.perform(sessionId, command);
        JsonObject response = new JsonObject();
        response.addProperty("ok", true);
        return response;
    }

    private static void respond(SocketChannel connection, JsonObject response) throws IOException {
        BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(
            Channels.newOutputStream(connection),
            StandardCharsets.UTF_8
        ));
        writer.write(GSON.toJson(response));
        writer.write("\n");
        writer.flush();
    }

    private static JsonObject error(String message) {
        JsonObject response = new JsonObject();
        response.addProperty("ok", false);
        response.addProperty("error", message == null ? "Bridge request failed." : message);
        return response;
    }

    private static long currentUid() throws IOException {
        Object uid = Files.getAttribute(Paths.get(System.getProperty("user.home")), "unix:uid");
        return ((Number) uid).longValue();
    }

    private static Path defaultBridgeDirectory() {
        return Paths.get(
            System.getProperty("user.home"),
            "Library",
            "Application Support",
            "Mustel",
            "Bridge"
        );
    }

    private record Descriptor(String socketPath, long pid) {
    }
}
