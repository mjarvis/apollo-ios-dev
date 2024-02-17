import XCTest
import Nimble
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

final class HTTPSubscriptionTests: XCTestCase {

  private class Time: MockSelectionSet {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {[
      .field("__typename", String.self),
      .field("ticker", Int.self)
    ]}

    var ticker: Int { __data["ticker"] }
  }

  private func buildNetworkTransport(
    responseData: Data
  ) -> RequestChainNetworkTransport {
    let client = MockURLSessionClient(
      response: .mock(headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]),
      data: responseData
    )

    let provider = MockInterceptorProvider([
      NetworkFetchInterceptor(client: client),
      MultipartResponseParsingInterceptor(),
      JSONResponseParsingInterceptor()
    ])

    return RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )
  }

  let defaultTimeout = 0.5

  // MARK: -

  func test__parsing__givenHeartbeat_shouldIgnore() throws {
    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {}
      --graphql
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Heartbeat ignored")
    expectation.isInverted = true

    _ = network.send(operation: MockSubscription<Time>()) { result in
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenPayloadNull_shouldIgnore() throws {
    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {
        "payload": null
      }
      --graphql
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Payload (null) ignored")
    expectation.isInverted = true

    _ = network.send(operation: MockSubscription<Time>()) { result in
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenSingleChunk_shouldReturnSuccess() throws {
    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {
        "payload": {
          "data": {
            "__typename": "Time",
            "ticker": 1
          }
        }
      }
      --graphql
      """.crlfFormattedData()
    )

    let expectedData = try Time(data: [
      "__typename": "Time",
      "ticker": 1
    ], variables: nil)

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        expect(data.data).to(equal(expectedData))
      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenMultipleChunks_shouldReturnMultipleSuccesses() throws {
    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {
        "payload": {
          "data": {
            "__typename": "Time",
            "ticker": 2
          }
        }
      }
      --graphql
      content-type: application/json

      {
        "payload": {
          "data": {
            "__typename": "Time",
            "ticker": 3
          }
        }
      }
      --graphql
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Multipart data received")
    expectation.expectedFulfillmentCount = 2

    _ = network.send(operation: MockSubscription<Time>()) { result in
      switch (result) {
      case let .success(data):
        guard let time = data.data else {
          fail("Unexpected missing data!")
          return
        }

        expect(time.__typename).to(equal("Time"))
        switch time.ticker {
        case 2...3: expectation.fulfill()
        default: fail("Unexpected data value!")
        }

      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenChunkWithGraphQLError_shouldReturnSuccessWithGraphQLError() throws {
    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {
        "payload": {
          "data": {
            "__typename": "Time",
            "ticker": 4
          },
          "errors": [
            {
              "message": "test error"
            }
          ]
        }
      }
      --graphql
      """.crlfFormattedData()
    )

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      switch (result) {
      case let .success(data):
        guard let time = data.data else {
          fail("Unexpected missing data!")
          return
        }

        expect(time.__typename).to(equal("Time"))
        expect(time.ticker).to(equal(4))
        expect(data.errors).to(equal([GraphQLError("test error")]))

        expectation.fulfill()

      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }

  func test__parsing__givenEndOfStream_shouldReturnSuccess() throws {
    let network = buildNetworkTransport(responseData: """
      --graphql
      content-type: application/json

      {
        "payload": {
          "data": {
            "__typename": "Time",
            "ticker": 5
          }
        }
      }
      --graphql--
      """.crlfFormattedData()
    )

    let expectedData = try Time(data: [
      "__typename": "Time",
      "ticker": 5
    ], variables: nil)

    let expectation = expectation(description: "Multipart data received")

    _ = network.send(operation: MockSubscription<Time>()) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        expect(data.data).to(equal(expectedData))
      case let .failure(error):
        fail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: defaultTimeout)
  }
}
