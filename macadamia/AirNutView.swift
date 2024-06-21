//
//  AirNut.swift
//  macadamia
//
//  Created by zm on 20.06.24.
//

import SwiftUI
import CoreBluetooth

struct AirNutView: View {
    @ObservedObject var vm:AirNutViewModel
    
    var body: some View {
        List(vm.peerNames, id: \.self) { peer in
            Text(peer)
        }
    }
}

class AirNutViewModel: NSObject, ObservableObject, CBPeripheralManagerDelegate, CBCentralManagerDelegate {
    
    @Published var peerNames = [String]()
    
    @Published var tokenString:String
    
    var centralManager:CBCentralManager!
    var peripheralManager:CBPeripheralManager!
    
    var discoveredPeripherals = [UUID:CBPeripheral]()
    
    private var _navPath: Binding<NavigationPath>!
    
    let serviceUUID = CBUUID(string: "C7E5D82C-71DD-48E3-8FDC-05D8C8609346")
    let tokenCharateristicUUID = CBUUID(string: "9AAC04F8-29AA-4D78-B6CF-F0270704B3C9")
    
    var navPath: NavigationPath {
        get { _navPath.wrappedValue }
        set { _navPath.wrappedValue = newValue }
    }
    
    init(navPath:Binding<NavigationPath>, tokenString: String) {
        print("AirNutViewModel initialized.")
        self.tokenString = tokenString
        super.init()
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self._navPath = navPath
    }
    
    //MARK: - RECEIVING AND DISCOVERY
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
            print("central managaer on")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if discoveredPeripherals[peripheral.identifier] == nil {
            discoveredPeripherals[peripheral.identifier] = peripheral
            print("Discovered new peripheral: \(peripheral)")
            peerNames.append(peripheral.name ?? peripheral.identifier.uuidString)
        }
    }


    //MARK: -
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            let service = CBMutableService(type: serviceUUID, primary: true)
            let characteristic = CBMutableCharacteristic(type: tokenCharateristicUUID,
                                                         properties: [.read, .write],
                                                         value: nil,
                                                         permissions: [.readable, .writeable])
            service.characteristics = [characteristic]
            peripheralManager.add(service)
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [serviceUUID]])
            print("peripheral turned on ")
        } else if peripheral.state == .poweredOff {
            print("peripheral turned off")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value, let string = String(data: value, encoding: .utf8) {
                // Handle received string here
                print("Received string: \(string)")
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
//        if request.characteristic.uuid == publicKeyCharacteristicUUID {
//            request.value = "Your string here".data(using: .utf8)
//            peripheral.respond(to: request, withResult: .success)
//        }
    }
    
    
    
    //MARK: -
    
    func startBT() {
        print("Starting BT")
        navPath.removeLast()
        if CBCentralManager.supports(.extendedScanAndConnect) {
            print("SUPPORT!")
        } else {
            print("no support :(")
        }
    }
}

//#Preview {
//    AirNutView(vm: AirNutViewModel(navPath: ))
//}
