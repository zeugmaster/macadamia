//
//  RelayManagerView.swift
//  macadamia
//
//  Created by Dario Lass on 01.01.24.
//

import SwiftUI
import NostrSDK


struct RelayManagerView: View {
    @ObservedObject var viewModel = RelayManagerViewModel()
    
    var body: some View {
        List {
            Section {
                ForEach(viewModel.relayList, id: \.url) { relay in
                    Text(relay.url.absoluteString)
                }
                .onDelete(perform: viewModel.removeRelay(at:))
                TextField("enter new relay URL", text: $viewModel.newRelayURLString)
            } footer: {
                Text("Swipe to delete. Changes will be in effect as soon as you restart the app. Relay URLs must have the correct prefix and format.")
            }
        }
    }
}

#Preview {
    RelayManagerView()
}


class RelayManagerViewModel: ObservableObject {
    @Published var relayList = [Relay]()
    @Published var error:Error?
    @Published var newRelayURLString = ""
    
    init() {
        do {
            relayList = try [Relay(url: URL(string: "wss://test.test")!),
                             Relay(url: URL(string: "wss://yabba.dabba")!),
                             Relay(url: URL(string: "wss://doooo.oo")!)]
        } catch {
            print("unable")
        }
    }
    
    func addRelayWithUrlString(urlString:String) {
        // needs to check for uniqueness and URL format
    }
    
    func removeRelay(at offsets:IndexSet) {
        relayList.remove(atOffsets: offsets)
    }
}


// for future implementation of safer swipe-to-delete
/*
 struct CustomSwipeListView: View {
     @State private var items = ["Item 1", "Item 2", "Item 3"]

     var body: some View {
         List {
             ForEach(items, id: \.self) { item in
                 Text(item)
                     .swipeActions {
                         Button(role: .destructive) {
                             // Handle the delete action
                             if let index = items.firstIndex(of: item) {
                                 items.remove(at: index)
                             }
                         } label: {
                             Label("Delete", systemImage: "trash")
                         }
                     }
                     // Optionally, configure the swipe actions to not perform on a full swipe
                     .swipeActions(edge: .trailing, allowsFullSwipe: false)
             }
         }
     }
 }

 */
