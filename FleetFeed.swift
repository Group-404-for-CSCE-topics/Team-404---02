//
//  FleetFeed.swift
//  MercyDrones — where the Fleet tab's drones come from
//
//  The fleet starts empty. Once drones report in (a cloud relay, a ground
//  station, MAVLink telemetry…), write a type that conforms to `FleetFeed` and
//  pass it as `PrototypeStore(feed:)` in `MercyDronesApp`. Each update replaces
//  the fleet. Callsigns renamed on this device are kept, and drones that
//  report a `position` also show on the map.
//

import Foundation

protocol FleetFeed: Sendable {
    /// The whole fleet as last reported, sent again whenever anything changes.
    /// The stream ends when the link closes.
    func updates() -> AsyncStream<[Drone]>
}

/// The default: no drones until a real feed is connected.
struct NoFleetFeed: FleetFeed {
    func updates() -> AsyncStream<[Drone]> {
        AsyncStream { $0.finish() }
    }
}
