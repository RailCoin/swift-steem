@testable import Steem
import XCTest

class TestTask: SessionDataTask {
    var resumed = false
    func resume() {
        self.resumed = true
    }
}

class TestSession: SessionAdapter {
    var nextResponse: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    var lastRequest: URLRequest?

    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> SessionDataTask {
        self.lastRequest = request
        completionHandler(self.nextResponse.0, self.nextResponse.1, self.nextResponse.2)
        return TestTask()
    }
}

struct TestRequest: Request {
    typealias Response = Any

    var params: Any?
    var method = "test"

    func response(from result: Any) throws -> Response {
        return result
    }
}

struct TestIdGenerator: IdGenerator {
    mutating func next() -> Int {
        return 42
    }
}

let testUrl = URL(string: "https://example.com")!
let session = TestSession()
let client = Client(address: testUrl)

func jsonResponse(_ dict: Any) -> (Data?, URLResponse?, Error?) {
    let data = try! JSONSerialization.data(withJSONObject: dict, options: [])
    let response = HTTPURLResponse(url: testUrl, statusCode: 200, httpVersion: "1.1", headerFields: [
        "content-length": String(data.count),
        "content-type": "application/json",
    ])
    return (data, response, nil)
}

func errorResponse(code: Int, message: String) -> (Data?, URLResponse?, Error?) {
    let data = message.data(using: .utf8)!
    let response = HTTPURLResponse(url: testUrl, statusCode: code, httpVersion: "1.1", headerFields: [
        "content-length": String(data.count),
        "content-type": "text/plain",
    ])
    return (data, response, nil)
}

class ClientTest: XCTestCase {
    override func setUp() {
        client.idgen = TestIdGenerator()
        client.session = session
    }

    func testRequest() {
        let test = expectation(description: "Handler called")
        session.nextResponse = jsonResponse(["id": 42, "result": "foo"])
        client.send(request: TestRequest()) { response, error in
            XCTAssertNil(error)
            XCTAssertEqual(response as? String, "foo")
            test.fulfill()
        }
        waitForExpectations(timeout: 2) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }

    func testRequestWithParams() {
        let test = expectation(description: "Handler called")
        session.nextResponse = jsonResponse(["id": 42, "result": "foo"])
        var req = TestRequest()
        req.params = ["hello"]
        client.send(request: req) { response, error in
            XCTAssertNil(error)
            XCTAssertEqual(response as? String, "foo")
            test.fulfill()
        }
        waitForExpectations(timeout: 2) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }

    func testBadServerResponse() {
        let test = expectation(description: "Handler called")
        session.nextResponse = errorResponse(code: 503, message: "So sorry")
        client.send(request: TestRequest()) { response, error in
            XCTAssertNotNil(error)
            XCTAssertNil(response)
            if let error = error as? Client.Error, case let Client.Error.invalidResponse(message, response, data) = error {
                XCTAssertEqual(message, "Server responded with HTTP 503")
                XCTAssertEqual(response?.statusCode, 503)
                XCTAssertEqual(String(data: data!, encoding: .utf8), "So sorry")
            } else {
                XCTFail()
            }
            test.fulfill()
        }
        waitForExpectations(timeout: 2) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }

    func testBadRpcResponse() {
        let test = expectation(description: "Handler called")
        session.nextResponse = jsonResponse(["id": 0, "banana": false])
        client.send(request: TestRequest()) { response, error in
            XCTAssertNotNil(error)
            XCTAssertNil(response)
            if let error = error as? Client.Error, case let Client.Error.invalidResponse(message, _, _) = error {
                XCTAssertEqual(message, "Request id mismatch")
            } else {
                XCTFail()
            }
            test.fulfill()
        }
        waitForExpectations(timeout: 2) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }

    func testRpcError() {
        let test = expectation(description: "Handler called")
        session.nextResponse = jsonResponse(["id": 42, "error": ["code": 123, "message": "Had some issues", "data": ["extra": 123]]])
        client.send(request: TestRequest()) { response, error in
            XCTAssertNotNil(error)
            XCTAssertNil(response)
            if let error = error as? Client.Error, case let Client.Error.responseError(code, message, data) = error {
                XCTAssertEqual(code, 123)
                XCTAssertEqual(message, "Had some issues")
                XCTAssertEqual(data as? [String: Int], ["extra": 123])
            } else {
                XCTFail()
            }
            test.fulfill()
        }
        waitForExpectations(timeout: 2) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }

    func testSeqIdGenerator() {
        var gen = SeqIdGenerator()
        assert(gen.next() == 1)
        assert(gen.next() == 2)
        assert(gen.next() == 3)
    }
}
