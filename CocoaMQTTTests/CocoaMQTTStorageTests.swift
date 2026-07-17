//
//  CocoaMQTTStorageTests.swift
//  CocoaMQTT-Tests
//
//  Created by JianBo on 2019/10/6.
//  Copyright © 2019 emqtt.io. All rights reserved.
//

import XCTest
@testable import CocoaMQTT

class CocoaMQTTStorageTests: XCTestCase {

    var clientId = "c1"

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testStorage() {
        let frames = [FramePublish(topic: "t/1", payload: [0x01], qos: .qos1, msgid: 1),
                      FramePublish(topic: "t/2", payload: [0x01], qos: .qos1, msgid: 2),
                      FramePublish(topic: "t/3", payload: [0x01], qos: .qos1, msgid: 3) ]

        var storage: CocoaMQTTStorage? = CocoaMQTTStorage(by: clientId)

        for f in frames {
            XCTAssertEqual(true, storage?.write(f))
        }

        storage?.remove(frames[1])
        storage = nil

        storage = CocoaMQTTStorage(by: clientId)
        let should = [frames[0], frames[2]]
        let saved = storage?.readAll()
        XCTAssertEqual(should.count, saved?.count)
        for i in 0 ..< should.count {
            assertEqual(should[i], saved?[i])
        }

        let taken = storage?.takeAll()
        XCTAssertEqual(should.count, taken?.count)
        for i in 0 ..< should.count {
            assertEqual(should[i], taken?[i])
        }

        XCTAssertEqual(storage?.readAll().count, 0)
    }

    func testReadAllSortByNumericMsgid() {
        let clientId = "storage-sort-\(UUID().uuidString)"
        defer {
            clearStorage(clientId)
        }

        guard let storage = CocoaMQTTStorage(by: clientId) else {
            XCTFail("Initial storage failed")
            return
        }

        let frames = [FramePublish(topic: "t/1", payload: [0x01], qos: .qos1, msgid: 1),
                      FramePublish(topic: "t/2", payload: [0x02], qos: .qos1, msgid: 2),
                      FramePublish(topic: "t/10", payload: [0x0A], qos: .qos1, msgid: 10)]

        for frame in frames {
            XCTAssertTrue(storage.write(frame))
        }

        let recovered = storage.readAll()
        XCTAssertEqual(recovered.count, frames.count)

        let recoveredMsgids = recovered.compactMap { ($0 as? FramePublish)?.msgid }
        XCTAssertEqual(recoveredMsgids, [1, 2, 10])
    }

    func testReadAllPreservesWriteOrderAcrossPacketIdentifierWrap() throws {
        let clientId = "storage-wrap-order-\(UUID().uuidString)"
        defer { clearStorage(clientId) }
        let storage = try XCTUnwrap(CocoaMQTTStorage(by: clientId, protocolVersion: .v5))

        for identifier in [UInt16.max, 1, 2] {
            var frame = FramePublish(
                topic: "t/\(identifier)",
                payload: [UInt8(truncatingIfNeeded: identifier)],
                qos: .qos1,
                msgid: identifier
            )
            frame.publishProperties = MqttPublishProperties()
            XCTAssertTrue(storage.write(frame))
        }

        XCTAssertEqual(
            storage.readAll().compactMap { ($0 as? FramePublish)?.msgid },
            [UInt16.max, 1, 2]
        )
    }

    func testReceivedQoS2IdentifiersPersistUntilPubrel() throws {
        let clientId = "storage-received-qos2-\(UUID().uuidString)"
        defer { clearStorage(clientId) }
        var storage: CocoaMQTTStorage? = try XCTUnwrap(
            CocoaMQTTStorage(by: clientId, protocolVersion: .v5)
        )

        XCTAssertTrue(storage?.markReceivedQoS2(42) == true)
        XCTAssertFalse(storage?.markReceivedQoS2(42) == true)
        storage = nil

        storage = try XCTUnwrap(CocoaMQTTStorage(by: clientId, protocolVersion: .v5))
        XCTAssertEqual(storage?.receivedQoS2Identifiers(), [42])
        XCTAssertTrue(storage?.completeReceivedQoS2(42) == true)
        XCTAssertFalse(storage?.completeReceivedQoS2(42) == true)
        XCTAssertTrue(storage?.receivedQoS2Identifiers().isEmpty == true)
    }

    func testVersionedStorageKeepsMQTT311AndMQTT5FramesIndependent() throws {
        let clientId = "storage-version-isolation-\(UUID().uuidString)"
        defer { clearStorage(clientId) }

        let mqtt311 = try XCTUnwrap(CocoaMQTTStorage(by: clientId, protocolVersion: .v311))
        let mqtt5 = try XCTUnwrap(CocoaMQTTStorage(by: clientId, protocolVersion: .v5))
        let mqtt311Frame = FramePublish(topic: "v3/topic", payload: [3], qos: .qos1, msgid: 1)
        var mqtt5Frame = FramePublish(topic: "v5/topic", payload: [5], qos: .qos1, msgid: 1)
        mqtt5Frame.publishProperties = MqttPublishProperties()

        XCTAssertTrue(mqtt311.write(mqtt311Frame))
        XCTAssertTrue(mqtt5.write(mqtt5Frame))

        let recovered311 = try XCTUnwrap(mqtt311.readAll().first as? FramePublish)
        let recovered5 = try XCTUnwrap(mqtt5.readAll().first as? FramePublish)
        XCTAssertEqual(recovered311.topic, "v3/topic")
        XCTAssertEqual(recovered311.payload(), [3])
        XCTAssertEqual(recovered5.topic, "v5/topic")
        XCTAssertEqual(recovered5.payload5(), [5])

        mqtt311.removeAll()
        XCTAssertTrue(mqtt311.readAll().isEmpty)
        XCTAssertEqual((mqtt5.readAll().first as? FramePublish)?.topic, "v5/topic")
    }

    func testVersionedStorageMigratesMatchingLegacyFrames() throws {
        let clientId = "storage-version-migration-\(UUID().uuidString)"
        let previousVersion = CocoaMQTTStorage()?.queryMQTTVersion()
        defer {
            clearStorage(clientId)
            if let previousVersion = previousVersion {
                CocoaMQTTStorage()?.setMQTTVersion(previousVersion)
            }
        }
        setMqtt3Version()

        let legacy = try XCTUnwrap(CocoaMQTTStorage(by: clientId))
        let frame = FramePublish(topic: "legacy/topic", payload: [1], qos: .qos1, msgid: 9)
        XCTAssertTrue(legacy.write(frame))

        let versioned = try XCTUnwrap(CocoaMQTTStorage(by: clientId, protocolVersion: .v311))
        XCTAssertEqual((versioned.readAll().first as? FramePublish)?.topic, "legacy/topic")
        XCTAssertTrue(legacy.readAll().isEmpty)
    }

    func testVersionedStorageMigratesLegacyFramesWhenGlobalVersionBelongsToAnotherInstance() throws {
        let clientId = "storage-version-mixed-instance-migration-\(UUID().uuidString)"
        let previousVersion = CocoaMQTTStorage()?.queryMQTTVersion()
        defer {
            clearStorage(clientId)
            if let previousVersion = previousVersion {
                CocoaMQTTStorage()?.setMQTTVersion(previousVersion)
            }
        }

        setMqtt5Version()
        let legacy = try XCTUnwrap(CocoaMQTTStorage(by: clientId))
        let frame = FramePublish(topic: "legacy/v3", payload: [3], qos: .qos1, msgid: 9)
        XCTAssertTrue(legacy.write(frame))

        let versioned = try XCTUnwrap(CocoaMQTTStorage(by: clientId, protocolVersion: .v311))
        let recovered = try XCTUnwrap(versioned.readAll().first as? FramePublish)
        XCTAssertEqual(recovered.topic, "legacy/v3")
        XCTAssertEqual(recovered.payload(), [3])
        XCTAssertTrue(legacy.readAll().isEmpty)
    }

    func testMQTT5StorageMigratesLegacyFramesWhenGlobalVersionBelongsToMQTT311() throws {
        let clientId = "storage-version-mixed-instance-v5-migration-\(UUID().uuidString)"
        let previousVersion = CocoaMQTTStorage()?.queryMQTTVersion()
        defer {
            clearStorage(clientId)
            if let previousVersion = previousVersion {
                CocoaMQTTStorage()?.setMQTTVersion(previousVersion)
            }
        }

        setMqtt3Version()
        var frame = FramePublish(topic: "legacy/v5", payload: [5], qos: .qos1, msgid: 10)
        frame.publishProperties = MqttPublishProperties()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "cocomqtt-\(clientId)"))
        defaults.set(frame.bytes(version: CocoaMQTTProtocolVersion.v5.rawValue), forKey: "10")

        let versioned = try XCTUnwrap(CocoaMQTTStorage(by: clientId, protocolVersion: .v5))
        let recovered = try XCTUnwrap(versioned.readAll().first as? FramePublish)
        XCTAssertEqual(recovered.topic, "legacy/v5")
        XCTAssertEqual(recovered.payload5(), [5])
        XCTAssertNil(defaults.object(forKey: "10"))
    }

    func testLegacyMigrationClaimsEachClientSuiteOnlyOnce() throws {
        let clientId = "storage-version-migration-claim-\(UUID().uuidString)"
        defer { clearStorage(clientId) }
        let legacy = try XCTUnwrap(CocoaMQTTStorage(by: clientId))
        let frame = FramePublish(topic: "legacy/claimed", payload: [1], qos: .qos1, msgid: 7)
        XCTAssertTrue(legacy.write(frame))

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "storage-version-migration-claim", attributes: .concurrent)
        for version in [CocoaMQTTProtocolVersion.v311, .v5] {
            group.enter()
            queue.async {
                _ = CocoaMQTTStorage(by: clientId, protocolVersion: version)
                group.leave()
            }
        }
        group.wait()

        let mqtt311 = try XCTUnwrap(CocoaMQTTStorage(by: clientId, protocolVersion: .v311))
        let mqtt5 = try XCTUnwrap(CocoaMQTTStorage(by: clientId, protocolVersion: .v5))
        XCTAssertEqual(mqtt311.readAll().count + mqtt5.readAll().count, 1)
        XCTAssertTrue(legacy.readAll().isEmpty)
    }

    private func clearStorage(_ clientId: String) {
        let suiteName = "cocomqtt-\(clientId)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }

    private func assertEqual(_ f1: Frame?, _ f2: Frame?) {
        if let pub1 = f1 as? FramePublish,
           let pub2 = f2 as? FramePublish {
            XCTAssertEqual(pub1.topic, pub2.topic)
            XCTAssertEqual(pub1.payload(), pub2.payload())
            XCTAssertEqual(pub1.msgid, pub2.msgid)
            XCTAssertEqual(pub1.qos, pub2.qos)
        } else if let rel1 = f1 as? FramePubRel,
                let rel2 = f2 as? FramePubRel {
            XCTAssertEqual(rel1.msgid, rel2.msgid)
        } else {
            XCTAssert(false)
        }
    }
}
