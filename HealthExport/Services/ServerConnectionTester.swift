import Foundation

enum ServerConnectionTester {
    static func testConnection(
        server: DestinationServer,
        secret: String?
    ) async -> ConnectionTestResult {
        switch ServerURLBuilder.uploadURL(for: server) {
        case .success(let url):
            return await performTest(url: url, server: server, secret: secret)
        case .failure(let error):
            return ConnectionTestResult(success: false, statusCode: nil, message: error.localizedDescription)
        }
    }

    private static func performTest(
        url: URL,
        server: DestinationServer,
        secret: String?
    ) async -> ConnectionTestResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        applyAuth(to: &request, server: server, secret: secret)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ConnectionTestResult(
                    success: false,
                    statusCode: nil,
                    message: "No HTTP response received."
                )
            }

            let success = (200 ... 299).contains(http.statusCode) || http.statusCode == 405
            let message: String
            if success {
                message = "Connection successful (HTTP \(http.statusCode))."
            } else {
                message = "Server responded with HTTP \(http.statusCode)."
            }
            return ConnectionTestResult(success: success, statusCode: http.statusCode, message: message)
        } catch {
            let nsError = error as NSError
            if server.usesInsecureHTTP, nsError.domain == NSURLErrorDomain,
                nsError.code == NSURLErrorAppTransportSecurityRequiresSecureConnection
            {
                return ConnectionTestResult(
                    success: false,
                    statusCode: nil,
                    message:
                        "HTTP blocked by App Transport Security. Use HTTPS or a local network host."
                )
            }
            return ConnectionTestResult(
                success: false,
                statusCode: nil,
                message: error.localizedDescription
            )
        }
    }

    static func applyAuth(
        to request: inout URLRequest,
        server: DestinationServer,
        secret: String?
    ) {
        guard let secret, !secret.isEmpty else { return }
        switch server.auth.type {
        case .none:
            break
        case .bearer:
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        case .customHeader:
            if let headerName = server.auth.headerName, !headerName.isEmpty {
                request.setValue(secret, forHTTPHeaderField: headerName)
            }
        }
    }
}
