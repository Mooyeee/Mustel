import Foundation

struct MachineProtocolDecoder {
    func decode(_ line: String) -> [MachineOutput] {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        let messages: [[String: Any]]
        if let array = json as? [[String: Any]] {
            messages = array
        } else if let message = json as? [String: Any] {
            messages = [message]
        } else {
            return []
        }

        return messages.compactMap { message in
            if let event = message["event"] as? String {
                let params = message["params"] as? [String: Any] ?? [:]
                return .event(
                    name: event,
                    appID: params["appId"] as? String,
                    error: params["error"].map(Self.describe),
                    trace: params["trace"] as? String
                )
            }
            if let rawID = message["id"] {
                return .response(
                    id: String(describing: rawID),
                    error: message["error"].map(Self.describe)
                )
            }
            return nil
        }
    }

    static func describe(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return String(describing: value)
    }
}
