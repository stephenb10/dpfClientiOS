//
//  SSDP.swift
//  DigiFrame
//
//  Created by Stephen Byatt on 1/1/21.
//

import SwiftUI
import Socket

class SSDP {
    
    struct NetInfo {
        var ip: String
        var subnet: String
        var broadcast: String = ""
        
        init(ipAddr: String, subnetMask: String) {
            ip = ipAddr
            subnet = subnetMask
            broadcast = getBroadcastAddress(ipAddress: ip, subnetMask: subnet)
        }
        
        func getBroadcastAddress(ipAddress: String, subnetMask: String) -> String {
            let ipAdressArray = ipAddress.split(separator: ".")
            let subnetMaskArray = subnetMask.split(separator: ".")
            guard ipAdressArray.count == 4 && subnetMaskArray.count == 4 else {
                return "255.255.255.255"
            }
            var broadcastAddressArray = [String]()
            for i in 0..<4 {
                let ipAddressByte = UInt8(ipAdressArray[i]) ?? 0
                let subnetMaskbyte = UInt8(subnetMaskArray[i]) ?? 0
                let broadcastAddressByte = ipAddressByte | ~subnetMaskbyte
                broadcastAddressArray.append(String(broadcastAddressByte))
            }
            return broadcastAddressArray.joined(separator: ".")
        }
        
    }
    
    // Return IP address of WiFi interface (en0) as a String, or `nil`
    func getWiFiAddress() -> NetInfo? {
        var address : String?
        var subnetMask : String?
        
        // Get list of all interfaces on the local machine:
        var ifaddr : UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        // For each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            
            // Check for IPv4 or IPv6 interface:
            let addrFamily = interface.ifa_addr.pointee.sa_family
            //addrFamily == UInt8(AF_INET6) ipv6
            if addrFamily == UInt8(AF_INET)  {
                
                // Check interface name:
                let name = String(cString: interface.ifa_name)
                if  name == "en0" {
                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    
                    
                    var net = interface.ifa_netmask.pointee
                    var mask = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(&net, socklen_t(net.sa_len), &mask, socklen_t(mask.count), nil, socklen_t(0), NI_NUMERICHOST)
                    subnetMask = String(cString: mask)
                }
            }
        }
        freeifaddrs(ifaddr)
        
        if address != nil {
            let netinfo = NetInfo(ipAddr: address!, subnetMask: subnetMask!)
            print(netinfo)
            return netinfo
        }
        else {
            return nil
        }
    }
    
    // Returns the IP address of the Digital Photo Frame
    func discover() -> String?{
            var ipAddr : String? = nil
            
            // Get the broadcast address to send the request on
            if let broadcast = getWiFiAddress()?.broadcast {
                let port: Int32 = 37020
                let fullAddr = Socket.createAddress(for: broadcast, on: port)
                
                do {
                    
                    let socket = try Socket.create(family: .inet, type: .datagram, proto: .udp)
                    try socket.udpBroadcast(enable: true)
                    try socket.setReadTimeout(value: 5000) // Set timeout to 5 seconds
                    try socket.write(from: "BSP: Requesting IP address of Digital Photo Frame", to: fullAddr!)
                    
                    var data = Data()
                    let tuple = try socket.readDatagram(into: &data)
                    if tuple.bytesRead > 0 {
                        let response = String(data: data, encoding: .utf8)
                        print(response!)
                        ipAddr = response
                    }
                } catch {
                    print("SSDP Error:", error)
                }
                
            }
            return ipAddr
        
    }
}
