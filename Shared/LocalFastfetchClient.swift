import Foundation

enum LocalFastfetchClient {
    static func fetchSync(variant: String = "full", timeout: TimeInterval = 3) -> String? {
        guard let url = URL(string: "http://127.0.0.1:\(ServerConfig.port)/\(variant)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data {
                result = String(data: data, encoding: .utf8)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 1)
        return result
    }
}
