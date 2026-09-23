import Foundation
import Network

final class LocalFastfetchServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.redwanh.fastfetchwidget.server")
    private let lock = NSLock()
    private var fullText = "Waiting for fastfetch to run..."
    private var compactText = "Waiting for fastfetch to run..."
    private var logoText = "Waiting for fastfetch to run..."

    func update(full: String, compact: String, logo: String) {
        lock.lock()
        fullText = full
        compactText = compact
        logoText = logo
        lock.unlock()
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: "127.0.0.1",
                port: NWEndpoint.Port(rawValue: ServerConfig.port)!
            )
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("Failed to start local fastfetch server: \(error)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self else { return }

            let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?
                .split(separator: "\r\n").first ?? ""

            self.lock.lock()
            let body: String
            if requestLine.contains("/compact") {
                body = self.compactText
            } else if requestLine.contains("/logo") {
                body = self.logoText
            } else {
                body = self.fullText
            }
            self.lock.unlock()

            let bodyData = Data(body.utf8)
            let header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
            var response = Data(header.utf8)
            response.append(bodyData)

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
