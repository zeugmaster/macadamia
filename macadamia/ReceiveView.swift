//
//  ReceiveView.swift
//  macadamia
//
//  Created by zeugmaster on 05.01.24.
//

import SwiftUI

struct ReceiveView: View {
    @StateObject var vm = ReceiveViewModel()
        
    var body: some View {
        VStack {
            List {
                if vm.token != nil {
                    Section {
                        // TOKEN STRING
                        Text(vm.token!)
                            .lineLimit(5, reservesSpace: true)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .disableAutocorrection(true)
                        // TOTAL AMOUNT
                        HStack {
                            Text("Total Amount: ")
                            Spacer()
                            Text(String(vm.totalAmount ?? 0) + " sats")
                        }
                        .foregroundStyle(.secondary)
                        // TOKEN MEMO
                        if vm.tokenMemo != nil {
                            if !vm.tokenMemo!.isEmpty {
                                Text("Memo: \(vm.tokenMemo!)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                         Text("cashu Token")
                    }
                    if !vm.tokenParts.isEmpty {
                        ForEach(vm.tokenParts, id: \.self) {part in
                            Section {
                                Text("Mint: " + part.token.mint.dropFirst(8))
                                    .foregroundStyle(.secondary)
                                switch part.state {
                                case .mintUnavailable:
                                    Text("Mint unavailable")
                                case .notSpendable:
                                    Text("Token not spendable")
                                case .spendable:
                                    EmptyView()
                                case .unknown:
                                    Text("Checking...")
                                }
                                if vm.tokenParts.count > 1 {
                                    HStack {
                                        Text("Amount: ")
                                        Spacer()
                                        Text(String(part.amount) + " sats")
                                    }
                                }
                                if (part.knownMint == false && part.state != .mintUnavailable) {
                                    Button {
                                        vm.addUnknownMint(for: part)
                                    } label: {
                                        HStack {
                                            if part.addingMint {
                                                Text("Adding...")
                                            } else {
                                                Text("Unknown mint. Add it?")
                                                Spacer()
                                                Image(systemName: "plus")
                                            }
                                        }
                                    }
                                    .disabled(part.addingMint || part.state == .mintUnavailable || part.state == .unknown)
                                }
                            }
                        }
                    }
                    
                    Section {
                        Button {
                            vm.reset()
                        } label: {
                            HStack {
                                Text("Reset")
                                Spacer()
                                Image(systemName: "trash")
                            }
                        }
                        .disabled(vm.addingMint)
                    }
                } else {
                    Button {
                        vm.paste()
                    } label: {
                        HStack {
                            Text("Paste from clipboard")
                            Spacer()
                            Image(systemName: "list.clipboard")
                        }
                    }
                }
            }
            .alert(vm.currentAlert?.title ?? "Error", isPresented: $vm.showAlert) {
                Button(role: .cancel) {
                    
                } label: {
                    Text(vm.currentAlert?.primaryButtonText ?? "OK")
                }
                if vm.currentAlert?.onAffirm != nil &&
                    vm.currentAlert?.affirmText != nil {
                    Button(role: .destructive) {
                        vm.currentAlert!.onAffirm!()
                    } label: {
                        Text(vm.currentAlert!.affirmText!)
                    }
                }
            } message: {
                Text(vm.currentAlert?.alertDescription ?? "")
            }
            .navigationTitle("Receive")
            .toolbar(.hidden, for: .tabBar)
            .onAppear(perform: {
//                vm.parseToken(token: "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOlwvXC9taW50Lm1hY2FkYW1pYS5jYXNoIiwicHJvb2ZzIjpbeyJDIjoiMDI1MjZmYjI5ZDJiMzBjMWMwYWEwMDhmN2RiYmZhNzQ4NThmMDliMDI0NjkxNDY2MjkyZjBjZDJkNmZmNzYyZTZkIiwic2VjcmV0IjoiNDExOTYwOTUxZDk5OTJlZThjNjkwYWRmMDE3Y2MyNDY3ODllMGQwODc2MzVhOGFmMzE2ZjhkNTcxMGNjOTVkNSIsImlkIjoiMDBhOGNkOWM2NWI0M2UzZiIsImFtb3VudCI6MTZ9LHsiYW1vdW50Ijo0LCJzZWNyZXQiOiIwZTJiOTEyZjZjNTFlZTRmNDYyNThmMjU3ZDhhMTk4NzNmODdlMmRkOGE5NzQzNzRjMjUzMWM4ZjljZGFhOGI2IiwiQyI6IjAzMTc3MWYzNmVjMmQ4OTZkN2RhNjc4ZWRhOWU3OWE3MWRlMmNmZjQ5ZGRkYmM4NjgxYmZkNGQ2NGFjNzY2NzllYSIsImlkIjoiMDBhOGNkOWM2NWI0M2UzZiJ9LHsiQyI6IjAzM2JhODQ1NDc0Yzc1ZmYyNjkxNGQ4Yjk4YzU4N2RjNDM5NDQ0YmY3YzIzNDdmNmE1MTgxMDdhYWMyNzEyZmEyNiIsInNlY3JldCI6IjY5OTJiYjdiZGM2MGQyYmI3YzFiNzNiZjgxYzFhM2U1NWNjMTQ5MzhmNDljZmNiNDQ4MDE0NDBiMTgzY2I0ZDgiLCJpZCI6IjAwYThjZDljNjViNDNlM2YiLCJhbW91bnQiOjF9XX1dLCJtZW1vIjoiSHVsbG8ifQ==")
                vm.parseToken(token: "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vNjNmZjM0YzliNi5kLnZvbHRhZ2VhcHAuaW8vY2FzaHUvYXBpL3YxL1NHbWoycndta1VZZGV1Z3doVTNmVmMiLCJwcm9vZnMiOlt7ImlkIjoiM2RURnZPUzFnT1laIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJHY2dmNkwyTGFNUi9zSXNraVR2Q0o3YkhMbHZjdUYzT3R0Zm1pR3pheGx3PSIsIkMiOiIwMjE2NmU1OTljNzM5NmViMjEyZGQ0OGQ3OTBmZDQyZjAwNTliNTM3ZjVmNmIwNzg3OTU3YzRmMDczYzE2ZmFmOGQifSx7ImlkIjoiM2RURnZPUzFnT1laIiwiYW1vdW50IjoyLCJzZWNyZXQiOiJhMkNQdnVST1dqMDEyNmhES0hHS01vQW9EWldhenNhWG9zZmFPTk9lTStNPSIsIkMiOiIwMzczODZjZjU4MDZmNzE5N2I2Yjc4NTdjMmZlY2E2YzFiYTk1ZTg2NWJiZTU3YjY0MDVjZDNlMGFiZWEwNzE2ZjgifSx7ImlkIjoiM2RURnZPUzFnT1laIiwiYW1vdW50Ijo4LCJzZWNyZXQiOiI3SmFCVW1XYnErd3BhM1dRNE1NRjRjU0VIQmhlazU1TmErOGhXK1ZmaGVFPSIsIkMiOiIwMzUxYjk0NWE4NTQ4MGE4OTZmZjZhMmRmNDljZjlkYjg0ZjVjM2U5NmJmMzZlMWI5ZTg3MTAwZTUzMjEzYTgzMzkifSx7ImlkIjoiM2RURnZPUzFnT1laIiwiYW1vdW50IjozMiwic2VjcmV0IjoiSVhPelAwNmJhK2RnV2NCVDJ6OE0wM1RTOWxBa0tCOW43bFNpS2ZST1Ewaz0iLCJDIjoiMDM4ZmUzYTQwYjEzMThhNTMxM2VlYTRmMDFmNDg3ZDU0MjcwNDAzMjM4YTM2NDFmZWYxODg3YmZjNDkxZmM5ZDk0In0seyJpZCI6IjNkVEZ2T1MxZ09ZWiIsImFtb3VudCI6MSwic2VjcmV0IjoiZEJXcVZ6RFExaGVXelVRa2xqdXpmQVlBaE1XeitwQmh2elVsTlByV3B2UT0iLCJDIjoiMDM4NGJmNzkxNjNhNWIyOWY2MjkyNzk1NDBmNzIyODZkMTk2ZWNjMmU0ZDFjOTNjMmMzYzBjYTg5NzU0YzA4OTQ0In0seyJpZCI6IjNkVEZ2T1MxZ09ZWiIsImFtb3VudCI6Miwic2VjcmV0IjoiS2d2YzZFWkVTbnlkK0diUmJsbmFlVTQrTWNQeFl5d0dFSDNMODlvRU8rWT0iLCJDIjoiMDJmZmJhZjExY2FiNmY5MmI1YWYyN2U1NjAwNzc0N2NhNmE0ZTJlMDEzMTMwNzkzMjQ3ODRmZjFlZGMyNzg4N2UzIn0seyJpZCI6IjNkVEZ2T1MxZ09ZWiIsImFtb3VudCI6OCwic2VjcmV0IjoiQlNPczBtc3lRYXNRMGlyTWZ5OWFJOURuT2pNZTg4eS85Vzc5SW1FMkdtQT0iLCJDIjoiMDNiY2ZlMzg5NGY0MDkyZDViZGE1YTg1ZTYxZDlhYzIyYjE5MWEyOGFiMTdmYzI5MTEzNTZhNDIzNDU4YzgyOGNhIn0seyJpZCI6IjNkVEZ2T1MxZ09ZWiIsImFtb3VudCI6MzIsInNlY3JldCI6ImI0R2JLTXFBdlB6eDNuSDIrNFFWdHVMa1BaeFRiSnI1eE42VmV4Z0hyUnc9IiwiQyI6IjAzYTc1ZGE5YTM3YmI3ZDM4MmFmNmI4OTUwNGQxZmFlZTM4ZWRhZGQzMTE5Yjk5MzFiYjRhZGU4YTAxNDU3NzMyOCJ9LHsiaWQiOiIzZFRGdk9TMWdPWVoiLCJhbW91bnQiOjY0LCJzZWNyZXQiOiJLbWlSSlJZd2hSME1hOTBBVDZUNWJDczhjdnRNVUQ1dG1NazYrUEhZdXYwPSIsIkMiOiIwMjlhYWQyMmE5MDRjMGEzMWEzNDE5MDY4YjRkZTQ5OTc5ZWE3MWE1ZTY0ZmNjMzU0YjVjYWVlY2IyZmNhMWRjODgifSx7ImlkIjoiM2RURnZPUzFnT1laIiwiYW1vdW50IjoxMjgsInNlY3JldCI6InBYSm9rcE1aYkZaQzdZcXFXb2l0UEM5OUFzdkYzOXhza1lpR1NuNVNVOXM9IiwiQyI6IjAzODQwODg3ZWExMzY5NWU2MGZkZDhmYWQ5NTM4OWEyZGJiMmZjN2NmZGJmMDZiYmUyNDJkN2U5YmE1OWQxNzI5MCJ9LHsiaWQiOiIzZFRGdk9TMWdPWVoiLCJhbW91bnQiOjI1Niwic2VjcmV0Ijoid2VHNExGaDlybEpTNDlvbEtUWHgwZ2xnbEhGYXhKVldDRHgwQXpXb0w4TT0iLCJDIjoiMDNkY2NlM2UwM2UyZDJjNTg0NDUyYWVhY2Y0YzljM2MxMDRmYTlhNTAzNzZmNzI3MTRhYzRhNmM0M2M4OTQ1MzQ0In0seyJpZCI6IjNkVEZ2T1MxZ09ZWiIsImFtb3VudCI6MSwic2VjcmV0IjoiUWF2T01VSG5KaWszVEduZVUyU0dtUVNIR3BvRXJZeWh6Zkwvd3VaZXFOTT0iLCJDIjoiMDJkZTlkNDQ3NDgxOWRjZTdlMTQ3NWEwN2JhMzFmZDdmZmRiMzg1MjU4MDQ3YTA1YjY3ZjJiYzM1M2RjMTMwNTBiIn0seyJpZCI6IjNkVEZ2T1MxZ09ZWiIsImFtb3VudCI6NCwic2VjcmV0IjoicXM4WmhQMFZDUXdodTJUWFZDY3hRdzdoeUpnYXlSSk53V2U1S2ZXVjFIOD0iLCJDIjoiMDJlMTg0MDA2NTlhYThhMzgwOThiMWE1ZjQzYzZhMmJlNDI4MGI4MmVkY2Q2M2Q2MDhkNWVlMzFiZTQyYzQ4Mjk3In0seyJpZCI6IjNkVEZ2T1MxZ09ZWiIsImFtb3VudCI6MTYsInNlY3JldCI6InlmM2NUUnJrVkFqR01KSCtRRUNMdDVXTkhVM2RYbjZwb1FrdzhyUWQyYzg9IiwiQyI6IjAyMjQ5NjYxMjVhN2U4MTMyOTI5Y2YxNDdmYjMzYTg5MDMyMzc1NjlmNjE2MDgwOTZjODIxZTYxZTExMzFjNzJhZCJ9XX0seyJtaW50IjoiaHR0cHM6Ly9taW50LnpldWdtYXN0ZXIuY29tOjMzMzgiLCJwcm9vZnMiOlt7ImlkIjoiZjhsdVR6OWFFZWI3IiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJHWVduQ1dkSlp1clpMeEpJWHRUNE5UZnpKSm9LRWh4N1pmVmxydGlTQlA4PSIsIkMiOiIwMjkzMzVkNTZiZjhjNzMzNWQ1ODI5MTU3YjE3NzJkOTNjYzJmZGNlZTQxMGUxMzI2NmUzNjMwMzk2NTc1YTM3NWMifSx7ImlkIjoiZjhsdVR6OWFFZWI3IiwiYW1vdW50Ijo4LCJzZWNyZXQiOiJWcWJxc1FTaVNvUktJbDJGYWNtTGlRUDBFL3poU3NhaHlTVUVNbTRWVWVFPSIsIkMiOiIwM2VjZmY2MzA0OGJmZGQyMDNkZDkxNzRiNGU4ZjY5MjNkNDIzOTJmOTU5YTQ0ZDM4NDE2OGFjYzM3NTYwYmFjZmQifV19LHsibWludCI6Imh0dHBzOi8vODMzMy5zcGFjZTozMzM4IiwicHJvb2ZzIjpbeyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6NCwic2VjcmV0IjoiM3U3NVI1clpFdjkxblZKVnoyNFJjN3dKME85OUN5amEvMFh4dWdtQ3dCWT0iLCJDIjoiMDI0OWE3YmJjZGNmZmFiMGVhYWJhNzdjZDk0ZjNhYjY0NDg4ZDcxYjU1YzA5NmM1MjI2YTI1YzEzNWM4YmQ2NzhmIn0seyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6MSwic2VjcmV0IjoiMElGazRHTnkra2tBeHNZdTRnNXJLQ21ORktPSTltc2Rlb2tVelc3dnRTRT0iLCJDIjoiMDM0N2FkNDZlMjcyYTc1ZTBjZGU4Y2EyNmU4ZDg5NzQxMWRlZjI5NjMwZjgxNjIwMjI0MmFjNGEyNWRhMDc1YjRhIn0seyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6Miwic2VjcmV0IjoidTBlNlo5Uy9CYWdVRjZrblBzdmpQWnZiSVlvejUxZWlMRGl1aDFmM0FvUT0iLCJDIjoiMDM5YzMwOGMxNThjOTg0NDQzMDRjNTE5NjJkZjljMDM4ODQ2ODNlNGU3ZDRlZjBjN2I5MGQyNjM2MTE4OWM3YzViIn0seyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6OCwic2VjcmV0IjoicUppc21JazVCSVlUaUxMQ1BKRHJ5RUdHMEl3Z1VOcmJjZTNaOGtraGZQUT0iLCJDIjoiMDJkNDhiNGJkZTEzYzY1ZDU3MDIyODkwNDZiNDhiMGY5Mzk5MjM5ZmQ0MjM3ODAwZTk4NDEwNGRhZmY2ZjM3MmQ0In0seyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6MTYsInNlY3JldCI6IlI2OC9IYVp6WlozUGpRREh2bEFVMXZ3YzU2TnV5elBFZnBYTzJ4bDlnT2M9IiwiQyI6IjAzNDM1NDI5ZjEwMjZiNjMyMTQwMmFlMjdkNzIyODVhMzM4MDRiMmUzYmNmZThlMzQzMTRhNDFkNWIyZjc2MTYzYiJ9LHsiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjMyLCJzZWNyZXQiOiJweFJSdGU5NVlNUUFYZ0JOckZyZGtuOTlMc0owNkFhV2dPNjMwNzFobEw0PSIsIkMiOiIwMzY3YzllZjgxZjI1MGRlMmQ3OTc5MGQxZWNmZmQyNDBhMWQwM2QwYTQ5MTUwNGJlNjQwNmMyNWE2NmM2MTI5YzcifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50IjoyLCJzZWNyZXQiOiJ2WHd6UEsxUEpxTnVPTzNGR2RJYURycWhyVTVzVE1TeHdEL0IzRXRCV2I0PSIsIkMiOiIwMjkzZWFmMDk4ZmMyMWRlNzRmZjBiNDM2NGJiODUyMjQyZDQzZDAxMTc1NzE4MWQ3MTg0MjVmYzdhNjEwYjFjMDAifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJaR1UxdmQzWkY0dnBUK0tWMVdsdElOU0FzbmFCRlkyN3YzbWowc0ZjMXBFPSIsIkMiOiIwM2JlNjc3NmY5MDBlNjA2ZWVlNDYzYmFhOTFiMDAwZjUzYThjNzY3Y2UzMmEyN2M4M2JiMTg2NGEyNTA5MWY0YWEifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50Ijo4LCJzZWNyZXQiOiI5TjBJaDNpbzA3czY2dGMwWFkwRUxFR01vbnkwYVpyMHdiY1VCUExYZDdBPSIsIkMiOiIwMjk1NTEyODVjMDFlYTFiZDkyOTBjNjU4MDhlMjRhZDU5YjdhY2E2ZjI5YzQ0ZjY1YzIzZGI2ZDI5YWFiZDZmZmMifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJFdlNMUzFiSVJEZDE5MkdaOUFzZzV4bjV0VFdUSEhHWmdTVHV4bHRYRG1jPSIsIkMiOiIwMjA0MWY2ODkwMjJmNTdmNDExNjljM2Y0MjJmOTExYTk3YmZkYjIxN2IwMzExN2ViM2VlY2RhNDBkZWQwNjk0NGUifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiWlVaWUtRQ3c5K0hsaG0zbjduSnRBNmNxcjEwbVUzeDZrYVV4SHhpYVJGbz0iLCJDIjoiMDJiNTNiMjgxYTc0ODk2MzlhYWRlOTdjYjU2OWUwM2Y0MTM3ZmU3ZjEzNGZlMThiOGViZjM4ZTg3NjMyZjk4MGY3In0seyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6MzIsInNlY3JldCI6IlRRT1NZdTJieUpoSVdtNm5QZHAreXB0N1VveUNaV3drL0VhQWdUUTNBVkk9IiwiQyI6IjAyZjFmMDBkNzVlZmNiY2FmMjFhMDNlMjU3MDljNmE3NTEwMGUxYWRlNmYyZDRmODI4ZWExMWQwZDRiYzkyODYxYiJ9LHsiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjY0LCJzZWNyZXQiOiIwTU8xcUd0bUthMUc4c0l0a1c4dkZJNjlacTR4YkNrWWozRmlMZ0E4SVFVPSIsIkMiOiIwMzJjOWU4MDEyZTQ5ODM5ZjlhNjMyNGE0Yjc1MDVmYjhlYTE0MjVkZWRlZTIxMTBkYmNmMGZkNTBkODk5NTBlN2EifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJ0Rm01NTl6WFFGUkZ2MWhIVHBEYXAwcHM1cjJNU0l2VzljbVRJc24wOTFjPSIsIkMiOiIwMmNmYzIxNzNlMjA1NjhkMGU5N2E4MGYwZmU1NTE4NzJiNmZhYmFkOThlOThkZjRlN2E2ZThhOWI3MjNlNjEyMTkifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJJQS82WVRUTHRTZ0ZVRHFOekk5alJuRmVxQnJTMXpPTUYxblZhYzdnalJNPSIsIkMiOiIwMzdmM2E1Nzc0NmU1ZGM2ZGM5MGUzMzUyY2UwMGE4Y2U5MWVjMDNiMWNhODZmM2EyN2ZjNmFjZjBiOTA0Yzc0MDUifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJGOC9CaFhrVVBpU3Mrai9kQWNlVVp6SFBYOFBsYnBKSU1qRG4yS2pNdmQwPSIsIkMiOiIwM2VlNzAwN2E3NTNhMzU2YWQyYjQ4NmM2NDA2ZjkxZTRhODVmMWY4Y2VjMjA2MDQ5Yzg2YzE2ZTc2ZDBhY2VmMDAifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJ4bm8yUmp1ZWxCcit3M3c0anNMSzBHWlAzbldTbVBkY2IxWmpML3hnenpNPSIsIkMiOiIwMmZlMGZjOGJlNTliZWM0NDg5NWVmYWYzYzdlYzRhYTVjYzViZDU0M2Y0YTBmMzJhNmI3ZDFiNWQ4OGY1YjA0NzUifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJ3b1FObWZnWnlUc1FDbGdXK2FoSHFoaFZVaTB5VDhBcFNQN21TNDd4S3EwPSIsIkMiOiIwMmYxNGUxNWRhOTBiYTQ0MjU2MGE1ZGRhOTAwZGEyN2NmMDliYzlhNTA4MDQ1ZjU0ZTNmYzJhMjA0Zjk0MWM0YzUifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50IjoyLCJzZWNyZXQiOiJDQ2l5V1ZKL3BZK0ViQm9TUHFRWjFJa0ZoS1hlMjhIUlR4OEJ2VWMzekdvPSIsIkMiOiIwMzY1ZWQ5ZTRhYzQzNzBmMmQ1ZmE4OTZmZGQ1NDhlMTBlZGU2MDc4N2E0NWZlYjQxZDQxMDJlNWE4OTA1MjVkNDIifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50Ijo4LCJzZWNyZXQiOiJtckkzRjNrY2NLS2I5R0RqWitJUzNJOWp0NlNUZ2s3VGhpZWFyZklXT0RZPSIsIkMiOiIwMzA5MzcwNjQxODcyZWQyYTViMzY0MzgxM2Q5Y2Y1MzViZmYxYzMyNjg4NjNiNzM3OGE3ZGZjMzNiMzRmYjU3NDgifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiMWt6S3JLSWZzRmVIR2JvSEZ0RnMvd1RvRkFCZWptQ2lNaHAvdVdwZHBqaz0iLCJDIjoiMDNlOWRjZDljYmE5MTg4ZDIyYTFkNjZhZGNlNzMxMzYwMzA4MDc0OWRmNTUzY2E1NDdhNDYwODM5ZjgyZTY0Y2E2In0seyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6MzIsInNlY3JldCI6ImRyaGRFSmpEK1kzMHZOWW5lMjZvQXdjTjFYS0tYYTlIYTVFNWpWNnIyQ0k9IiwiQyI6IjAyNjg0OWRkNjEzOTNiNzcxNGU1ZGQxZDY3ZGY1ZDI0NDFlNjBkNGQ4MmQwYzVhODNjZTA3OWQ2NDMxYjIwNWMyNCJ9LHsiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjY0LCJzZWNyZXQiOiIrSHFMdGtZWU5tZlJJQ2pVV2laWTA4RDRZTmUzTDJSOWVBcFhqeDZNQTBvPSIsIkMiOiIwMjVjYjljOGY0YzMxY2MwMjc3NTMxNTFkODQ3YmQ3YjRiMzc4NjUxNWM1MTE2MDk3ZDVkZDhhZDUxOTBmNGQ1YjkifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50IjoxMjgsInNlY3JldCI6InV1TzZCbHVRTkU5UHZnWWJIekNTWXZmVkFWL1Jsd0Zmenl2Y25kalV3dW89IiwiQyI6IjAzM2EzYWUyOGIwNWM1YzYxYzk0NGJlMzc5Mjk1NDk3NDA4MTQ4ODBiMTk3OTg4MTJjZjE3ZmJlZDRkNThiNWJkNCJ9LHsiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjEsInNlY3JldCI6IlJScVdtZkYzeHNuYXFNRys0YWUxdUowVFNEWDQrNkUzNktoWUhQYVVnTTQ9IiwiQyI6IjAyZDI3MTdiMDlkOTkzYTc4MDYzNmU0N2IzNTVjOTZmMDQ0ZGVkNmUyNmUwZDY4NDk3OTFmODE4MzJjNDQ1OWJmNCJ9LHsiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjIsInNlY3JldCI6Inl0eHZoWDFCSXdvL0dnSjU2ZnN1ak1NZldFMEg3OXFBb2I0T0dSVUxrc2M9IiwiQyI6IjAyMjVmNWEzMWQxMGUxMzY2NjYzNzYyNDViYWRkNTg2MTZmZmY1ZDBkZWQ2MjYxMmQ4ZGNiNzhkMzQ3OTliYmQwMSJ9LHsiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjgsInNlY3JldCI6IlRma1dNMEMwMVR0UzJaclE1cXppZWFJQ3ZvdVd5L3NJb1c1Z0w5MzdWRTA9IiwiQyI6IjAyM2UzMDNjYzVlN2YwZDY1MjRkMDhkODdmNDY5NTdhNTVhNmY0YTM0NGM2NDM3YjRmYTI4N2Q0Y2Y4ZGUzZWZmNCJ9LHsiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjE2LCJzZWNyZXQiOiJRQ1NxWFp1dTZVVUdZVW1XbXB1LzJZSEM5Ri9RdENSVHJvWUZ2a1Z0MWlRPSIsIkMiOiIwM2Y2OTNkYWVlYWIwODQxZGRiNjE1ZWY4ZTU1NzdjYzUxNDdjNDIwYzVhZWMwODU5MjhjZDc0MWM1YzJmZjI2MTMifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiYW1vdW50IjozMiwic2VjcmV0IjoiZ1U0Qmk4dmZsY25DUnJiZnlnTlAyY2Jkc2lSSEczUlNEY1lSRXhUV0RmYz0iLCJDIjoiMDJjNTEwMzFiYmU3M2QwZDgyZjk2ODljMmZlYTliZWJhMzY4MWZkYjExZmMwNTM3OGU3MTFlYzFmZDI3OTc2NWNlIn0seyJpZCI6IkkyeU4raVJZZmt6VCIsImFtb3VudCI6NjQsInNlY3JldCI6ImJQUmZQV1NCUXhkU0J5OU1mRnNLTlhNRW1PZ0ZWTmJvNVBzS3NvRlFNT009IiwiQyI6IjAyMmVmYWEyYWQ2M2VmNTI2MTc3OWIzNDFmY2RiZTk2NDk5OTgwZjM0ZTg4NjZjYjM2NDExNzg3NTI5ZGUwYmI4OSJ9XX0seyJtaW50IjoiaHR0cHM6Ly9sZWdlbmQubG5iaXRzLmNvbS9jYXNodS9hcGkvdjEvQXB0RE5BQk5CWHY4Z3B1eXdoeDZOViIsInByb29mcyI6W3siaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjEsInNlY3JldCI6InR5c2lPSTVUNVFVNWxFNGEyUnNSOUI1aTJteUpBNDMxRWhGeUcvT281UUE9IiwiQyI6IjAzZDllNmI1NzNjNTA5NjA4YjhjMjY1ZjAzNTI0NWIwODM3ZTY4MmRjOGY1MGMzMzgyYjZlZDE4ODU4MjQ0MTNiNCJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjgsInNlY3JldCI6Ik4vczNIdVVsRHU2ZURBcHlMUGxWVmZFQnNsT2FqQi9FVTdLK2VCUnZ2aUE9IiwiQyI6IjAzOWMxZTEzZmFjNGZmN2MwODA3ZDU1M2ViN2VlMjI5YzQ1NTI2YmQ0ZWY3MDI5NTJlNmMzMzM0YTIzNDNmYjg3MyJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjEsInNlY3JldCI6Im1mRFZJSU1MZEk4RE9tMFNFQ2hxamFXVVNLaUMzZ1VJdXRSZDNna0xyYzg9IiwiQyI6IjAyOTM3ZGNiMjNiYjM0N2I2MTEyMjJmZDVkZTcyMzU3M2RhZWE3OGQ0MTYwMDYwMDIxM2QwZGFiN2E5OTQ4YWVmZSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjIsInNlY3JldCI6InE5dGhEaW50YUFoSW01enlvWWpzamt3bHBZclorYkxnTVNndzRIU25BNjA9IiwiQyI6IjAyZjExZWNlZjEyM2JhNTcxZGNhMWNmZmYzNTFiNjZhMzJmOGRmYmFmODRiZGVjYWZjYTVmNmIyOTFkMTJjNzEwZiJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjgsInNlY3JldCI6IlNNdVhGL1FibDZGMFFvK2l0WitZSnNISUgwMDgxRk9OUFlBMjhCQlh2M0k9IiwiQyI6IjAyMWI3ZmRkMDBmNTIxZmZlYTJiZGM0ZDZmZmE5MDZhOTg4OTU0NzIzNTcxMDMyM2M3NjBkMDExMTBjOTBiMjQwMyJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjE2LCJzZWNyZXQiOiJGS3AxMitNU2VHQUN2MnBOamxwSzBmSDJ6azhlK0Evb1NEVjgyTWtOb2xRPSIsIkMiOiIwMjQ1N2I2YjIzODI2ZDk4NjBiM2QyMGFiZTEwZmVlYjNiOTJjNWVmOTE5YjFlYWEzZTU5MGY2YzE1NDI1MjcyNTQifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJ0ZGQ1dGNodTdDZEYycTFNMVlzS3UvUkJwVHhUNWd4RDE3MVdsY00zVkdFPSIsIkMiOiIwMmZmNjcxMTliMWY3ODdkOTBjZjNlMWEyYTNhMGIyOTQ5NWVjM2JiZGE3MGYzZWJiMjI2Mjk3NDljNzJjYWE2ZmIifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoyLCJzZWNyZXQiOiI2K0tNY25JdXBTcE1OeHI5SWVjTHZHdHVGT2xrSy9hcGhWR0NxeGZzM1YwPSIsIkMiOiIwMmU2OTQxZGNlYThhMzE2ODhjYTdkMTNiODBkODMzMDFjNGQ4YzMyMDAzN2YyYzExMzkzZTYyODJmMmE1MjE3ZDAifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo4LCJzZWNyZXQiOiJFL3lJdTBDSEZWOWRiRmkxUU1QMTJRN2o3UjdBWjRMY0lKbEV0OWZoYTNFPSIsIkMiOiIwMzdlZDNlZWEyY2U4Y2RmOTYwOGU3MjdiYjZlM2I1NzAzMThmMTc1MTExYzM2MTg0ODU4NGI3MmYzZWM3YWVkZWMifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiVzYzeEV4N05KU0FzVEQrckhQRXd6ZXFPWU9CalVCdkZZVUo0S1hjSVhJZz0iLCJDIjoiMDNiYWZkYTMwMGYxYjg2ZTQyNTJkZDhkNDRlMTZhNmE3OGQ3YjFlNmNiMzE3MjE1OWU5Zjk5ZWNmODU0ZjQxYjkxIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6MSwic2VjcmV0IjoiUER1a0RBZGxXT0tqcFM4TTExTlU2K3BXdTRydDRnZnNYY015dXdxeW5sUT0iLCJDIjoiMDMxZDdiZTM0ZjJlMmFiNGJmZGI3NGE4MTQ4ZGNhMGQxNjM2NTk3OTQ4MzkyMDdhYzVjMzc4NDY2ZTk2NWVmN2U0In0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6Miwic2VjcmV0IjoiQU9zVVNvTzJvdzZiMXRDY0NmMUphdXN4SW1IVnNxVXZOVEp2UlRmbG1WVT0iLCJDIjoiMDJkNTNmZWE0OGJjOTIyNWViZDc4MDUxMzRmYjkzNmM4ZWNiYmRiNTdlOTEwMmM3NWE2YjYzZmI4MzExYTBkZGJjIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6NCwic2VjcmV0IjoiY0NuYjdpK2xOelBZWHF4K0J1Rml5UnQybWEyQWQ4dXhrZFRib2lOaXhvRT0iLCJDIjoiMDJlNThjYTAyN2I3NjEzNjU0MmI0NDk4OGY4MjNkNmRmNWMyMjFjYjZhMzQyOGQ3MDE2MWIwNWQ4MmU2MmMxYmNjIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6OCwic2VjcmV0IjoiOWV0Z1dBbDM0dmltNUE2cEJsZkhmOHNpbGRwMWFPTlM5OFptZmlyNEFqRT0iLCJDIjoiMDIyMTEyODZhNmRiNmFlODk4Y2UxZmQ0NDgyYzhjZjZlYTM3NjJjMWQwMzI2MDRhMDYwYTc5YjRkNDczNmI4N2YwIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6MTYsInNlY3JldCI6ImtQbG44cmRpVy81QmVWbGMrKzVOWmRCdkpjVWpSL0tzRGpObDVVMm8vR0E9IiwiQyI6IjAyMTI1MzdiYTFhOGE4MTY5MThjZjk2NDIxODBmOTE0YjdhM2UxY2IzYjY1YjM4YzNkMTU2ZjMyYmY4ZDllMDJkMSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjEsInNlY3JldCI6IjlSQWYvYjZVdUg0MDRUZTdoSnROV1ZtZ0pZbENDVzFuSjVqdlBSNFA2d2M9IiwiQyI6IjAzYjUzOWQ1ZGYwMjAzMmY0YzUzYThlMmE0MWI1NTU2ODNhZWM2YzQ2NjgxMWZjZjg4NGI2N2QyMTFjMjBhNDRiZCJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjQsInNlY3JldCI6ImRSMkZsc0pzZjRTZUxIMjVwU1BXTkt0S2grU1hPU2hIQXhBTHdsQXBlQkU9IiwiQyI6IjAzMjZjOGZjNDRlZTY0Y2U3ODhjMDdjYzQ5ZDE1MTAzYmZmMDBhYzU1OTUzM2Y1ZDAyMDMzY2VhYzQxMDg1MTEzYyJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjEsInNlY3JldCI6ImppK3VDWktvR3JQdzh0SEN1Y1pmK1EzYmxxQmpjdnY1MVVEQ1JmTndBUmM9IiwiQyI6IjAzZmVmYjliMDYxYzY5MjQ4NjU3ODllN2Y2NzFkZTIyYjk0MzhmZDdhN2EzZmExMTYxZDFmMTQ1ODc0ZTBkMDM1OSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjIsInNlY3JldCI6InVXVTMxUWNBcUVac2llcWY2MzVwUGlBc2NSeVU5WHc4K2twTjQ1dms3QTQ9IiwiQyI6IjAzYjVhNDI3YmQ4NWExMTY2MjdiM2YxMDA3MWE5Yjg1ODdjMTA3M2U2OTU3ZTBlNmNmMzMzOTk3MDIxYTM3ZDgwOSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjgsInNlY3JldCI6ImpqWDVDWEJNTGp0bWxQdjZiWWMybGhpbllwcjhZVEFyRjZMVGk0VlFybDQ9IiwiQyI6IjAzZTM0MmVjNjY5NGRhZGJmOTQ3YTMzZDI0MWY0MWZlMDIzZjQ3MjQxNzdjNjYxYjVmMmFhODRhZGM2MTYyMDVmMSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjE2LCJzZWNyZXQiOiJ1MUgyRU1DdkNJWGJOcjNvaU5yOFB3UXZZK3dWTU5zdjl6eU1vc01hQlY0PSIsIkMiOiIwMmQ1NDNiMTBiMGZkM2MzZGFlNjllZWY4OGE5NzkzNjNkYjFjNGUzY2JjMjBjNTNkNTI3YTY0ZjI4YzI5ZjM3ZTAifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoyLCJzZWNyZXQiOiJaenAvbFlXTWdTMkswUG5kMVY3YlRTRU5nUVVnL3kzSXQ3eG9EbEY1Q2I4PSIsIkMiOiIwMzhhOWVhZWYxMzA0OGY3NTE0NzlkMzQ0ZTIwYjU1MTAxYWYxMTQ3YWZhY2I4ODFiNGRhMWZmNjhiMjJhNzQxYWUifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJvK0xYOGFKT2dSSHZBMVBpbE95WUNLWjl3QmNMWFp2bitIcUhxQVhGV3BZPSIsIkMiOiIwMjQ0MDE2NzhjZjhmZDRiZDI4YWViOTUxNzdiMjE4ZjVmYTJjMTNkZjRkY2MxNGJkMmRhNTg1YTc1N2RkZTZmMjcifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiVjJ0OHZEaXRLV1Jxb3I3NlZZVmNRVE1USE9kL2paRnV3MC83djhMYnlXaz0iLCJDIjoiMDNmOTMyZWY3NjFkNTZlZmFmZjYzYjRjN2VjMWU0NjdhYWMxYzJhZDY5Y2EyNzE2N2E4MjY5MDRmM2E5NmVlNjMwIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6Miwic2VjcmV0Ijoid3R4Y29TWmFnak9sTk4rZGNwWlJuaUNCbzNRcjBFSFNaZ1lmMWRoenFpbz0iLCJDIjoiMDNmNzVhNzY2ZjJiM2IxZmNmOTY1NzdjOGEwYjY1MGFiYTVlZWZiNDZjNzgzNjI2MmFmYWMzNWQxYjk3NGYwMWM3In0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6NCwic2VjcmV0IjoiaU1FNFNMYmdPNy9oRm1YQXkwNTdycHdSZmJlSEViLzFabmdhK1p0Zm1xND0iLCJDIjoiMDNmOGExMDhiZmIzOGYxZDM3Mjc5MzVmZTc4YjIzYWM3Y2M3YzI0ZjZhOWZhOTk1M2UzOWQwMmVlMjYxYWZhMjIxIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6MTYsInNlY3JldCI6InlQb2U3eWlSS2h5UEpvK3NEVkkwSTJmdWxvREk4cGhZblo3Um9janVSSkk9IiwiQyI6IjAzNjE4YmM4ZmUxZDhkYTU0NDQ4ODNmZGNkODU5MDkwYzUzNzExZDNlYTE2YTYxMmY3Nzg1ODU4ODY4MjBlOWY2MSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjIsInNlY3JldCI6Ik5RQTczR25XaDBrK0RiSm9PZEhqL3NtRXlQQXpzcDcydnk5Y3R0VTEvSTA9IiwiQyI6IjAyYzFiMjFhZWM3NzZjMTY5NWMwZDk2NmI4MzhjZWZjZGI3NDIwZDZmZjg5ZDZiMzE1OTFmNjAyMWU5MWM0MGJkNiJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjQsInNlY3JldCI6ImNWSXppcEQvRXN2OU1GOUF4R1BlWlA1UzdIZnpDTXpUMlFleVpqM3NNejg9IiwiQyI6IjAzNTU3NjU4MGNlMWY3NTM2MGEyODJlNWUxNTkwYzk3MTM0M2RjYTJiOWFlYjY2MTEzODliYTIxZGQxODFiMWRhMiJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjgsInNlY3JldCI6Im1idTdjZTYweHNZWnM2b04vOEFvN2Z5L2FrMGZLYnAzMjdxZTY4MmFmSjQ9IiwiQyI6IjAzOTg4ZTFmZjFjNzc5OTBiNWQwM2JmNDIzNTU2MDQyN2FlZWNkYTRmY2MwZTNjNzBjMDI2NzA1NjEwZmUxYTU5ZSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjIsInNlY3JldCI6IkFIdVBGakhtTDdiejZVbXRwVExvNS95UGs5SW81VjZRa0xRekhSY2F2bXM9IiwiQyI6IjAyYWU1NjJjOTFiMzhmM2M3OTYxMmJjOWZlNzJiMWJhNzA3YzU5YjI3YjE4YThiM2RjMTQyM2MxOTQxY2YyNTk0YSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjQsInNlY3JldCI6IkVjTG4vR2hkY2hsV0dFUkJlRzlISGR3WmJWd04vbkMwenE5NkhESHVyRmM9IiwiQyI6IjAyYzI3NzAxZmY1NDNkYTU2ZWRlZGNlZGQ4ZWYyNTAzMjI2ZTU2ZmY2ZGY1NWYzNDk3OGM3OWI4MTk3YzZhZTdkNCJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjgsInNlY3JldCI6IkRVZHlvN1hXS21kZjNBZFEzM1loR0liRkx6NlgwWUZYbUxDYXZjbnk5czA9IiwiQyI6IjAyMTc0NjEyY2YxYWQ5MTFkM2M4MWE0MDc2MzljZjE2MWU1NTQ2NDQ1NTQxOTZlNTQ4ZmY0NzM3MWVmNTEzNDVjZSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjEsInNlY3JldCI6IjJVckt1a3k2dFoyd2swSEhTRWpRbHpBSEc0SDJsajZYTWd0eVZJV05UL3c9IiwiQyI6IjAzMmI1ZGFiYTM5ZWNhMjRiZjdlMzg5MTg0ZjkyYWJjODY2N2U2OGI1NmE4YzJlNWVjMTIzYTdiOTM4NmY0OGEyOCJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjIsInNlY3JldCI6IjZMVDNwdmhMS1BpRlNXTUtyQ0VZU0cyZURWUklyQ0dQeUlKWjNYaGo4ZVU9IiwiQyI6IjAyNGZlN2QwODRhN2RlMmQ1YWFiZmNmZDFmMzA1NjkzMDJhOTQ1NDZjNjIzOWM1MzM0N2RhZDNjZjU4MjYwMzE5OSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjgsInNlY3JldCI6IlV4YkhTQ0ZXWmxPcndscTVDTDlmL1ZLcWVTR0VkSnlFMzEzOHJ0c2lZaVU9IiwiQyI6IjAyYWVjMjBmNDI2NTUwMTAyZTZjZDMzMDQ3NDljNjJjMDVlMTRhMDM2MzI3NDZkMjE5Mzk3NGViZDY4MWM0NzExOSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjE2LCJzZWNyZXQiOiJZaWhibko4QW1RQ0RQWGRkUGR1aHgwN1VHenVQSms5TDZMQVQ2OEY0ZHVZPSIsIkMiOiIwMmZjYTgwZTY0MzdhNzM0NzQ0MWMxOTczM2M1ZGM5NDRjNzQ2MzUxYjViMmUyYWU5ODUxNDgxNTk3ZjQ4MjM1Y2IifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoyLCJzZWNyZXQiOiJQTTZsUTROSnFwenF4M0hkMnd6bVhxYjVSVDJDRFV3a202c1hCRGYzdmw4PSIsIkMiOiIwMzEzNTUyNzBhOTlmM2E3MzNjN2EzZDc4OTdjNjhkMGQ2ZTczZTQ3MTY3NGUyOTI4YjVkNjk4NGYxMGJlN2E2NGQifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo0LCJzZWNyZXQiOiJUREQxVGxDUEt4cGo2Q29iWVpmbjM4VkpUbWxqdTZHSUxmZTU1T2I5ZG9zPSIsIkMiOiIwMmRkYzQwOTRiNDlkZTAwOWEzMTRmOWMwNjAwN2I5NTBiMTM2NDkxMmRlMjkzN2ExMWU2MGI1YzNmNjJlZTAzNjQifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo4LCJzZWNyZXQiOiJpdjZOdUpYaENrMVhlZmxOZVZydTJyNTdJYTAva2Z4VjdPd01GTVUwL3NnPSIsIkMiOiIwMmRjZTZjMTk0NDlkNzVmMzA2OGExNWIxZDEwYzZjM2VmYjQ2ZWE4ZmYyYjVkZmJlMTQzNjE3ZWQyMWFmOWU4NzEifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJEZkNYdndvOXVHVW5mWGpTZXJKL0tWUWYrOXEwK3hOejBiOWdBVnRSbGc4PSIsIkMiOiIwMjIwOTFkMmNiZDVkNTdmODY0MjZjNTVmYjI5ZWM5NThjYzk3ZjBlMDkxYzUzOTRkZGI5NTNiNTc1OGE0YmY0NDIifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoyLCJzZWNyZXQiOiJnT21yK2ZMOHhxUWpIS0NRdWxHR3JjK0JibklUK1JhZWdKb1N2dkJva0VFPSIsIkMiOiIwM2NkMmIwOTMwNTEzN2MyNmIxZjk1N2NlMTdkMWI4NjRhYjJhNzdlNDgxMzA0ZGZhNjYwZWUwNDlkM2M0ZjNiMjYifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo4LCJzZWNyZXQiOiJraEExYnUrVktMaGpHZUJ0eUxDL2FWcUVWMkxQSi9MaHpNZnFrYVU2ajA0PSIsIkMiOiIwMjliMmE5MTI1ZTEzNDZhYzAwNTc1YzhiNWU0ZTgzMTYyNDgyNDVlY2ZhZmFmNTA4N2VkYmQ3ZWNmYTI0ZmRkNWEifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiYzFvbTFNNXJEZGNDR01Od1dJWlJOVkhCQnRDOU5GOEtMYlZxdy9vMkNMST0iLCJDIjoiMDMyYTNjMDc0MDQ0NzI5ZjcxNmQ4YWFjYTA1OThjOTUzMjNhYmEwODBmZjk0MmNhYjg5ZDRiYmY2MzIwMjg2YzdjIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6Miwic2VjcmV0IjoiMElROEVuWTdMblBlbU1Ca2xCUnkyb2lXR085OTc4aVlZMFAvaURQYi9wOD0iLCJDIjoiMDIxYmEzNTI0NGE2ZjQwNDg1MTI2ZmRkYjkwMmU1Yjg4Y2ZkMGE3NDMzZDdhYTU4YjUxOWFlMjM1YzFkMDJlNjg2In0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6NCwic2VjcmV0IjoibHJaYlB5eUJxYzdXYmthRU9qcWtMMTFzM0haNlBSSlhYNWNkR1laVnZtMD0iLCJDIjoiMDNhYWE0N2U1NGYyZGJmNjAwNGVlNDFlYTNmODYzZTc5YTQwNDE1MTYwNWIzNTZlN2I4NGE3YjBjZGVjZTBiMWIwIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6OCwic2VjcmV0IjoieUZIR0hMcm4wMmFKbm0xTVRZOFEvWkhxRUdiemJvZnFWay9veStjc1pRRT0iLCJDIjoiMDNlNTJmMTkzYjU5Njk2M2UyMTlmOGNhM2QyOGJmNjllMGMzNDQzMzgzYTI1NWM1NWM2NDQ0ODM2MDAzNGU5MjY3In0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6NCwic2VjcmV0IjoiRnQ1amV5K0NJd0k4eUdRYjFmTVNSQnE0anRTQVBNVURBZFVoZDNvSnNtTT0iLCJDIjoiMDJlYzMyYmZlNWRlMzFkNDFhZTZkODdhYjAxZmI0NmE0M2U1M2VmOGM4YmRhM2Q0YWRhZDQ1N2I4Mjk0ZmU0NjVjIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6OCwic2VjcmV0IjoiSzZQczVWRGF2eW10UENFclhZd21VZ2p3bktydXN1aUwvMmhPL29iVnJKRT0iLCJDIjoiMDM0OTIzYTUxZjgyODI2ZDk3MjU1MmM1NmJhYmUxZjhhMzAyOWJmYTE0OTExOGY5YzBmMGMzZWVkNjQ4OWFmYWMwIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6MSwic2VjcmV0IjoiN01way8vQ1hWUDg4azBHc3owOFpiN3RXeGFBSWdBeDFVaTg0eXhvVHZxND0iLCJDIjoiMDMzZmJiMzg4OTk5OWMwNzMxZjA4YzQ0NTVlMWJmYzdlMjcyYWQ4NmZkYjA1ZGMyMDczYjRiODk0MTE5YWM4NzE2In0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6Miwic2VjcmV0Ijoib29pMkZ6cWI4L3FaSklvMnBlS0l0UGpYTWRpV3pLQXNXVXRtTUoxQVBhTT0iLCJDIjoiMDIxYjk0NTUwNzZiMmIwODNiMTkzMDBlY2RmY2ZlZGY3ODMzYTAwMDhjOGRhY2NiNmUzZGViN2U5M2Q0ZTM1YTViIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6OCwic2VjcmV0IjoiNHIvTnV0OGNvSnMvVTdzMFU5enoyTWIzNnc5Rk9kSDMrVFR3SWRIRzd2MD0iLCJDIjoiMDM1MDM1MzliMGFlNjBkZmE4NzZhOWFlYTBlMTliYjg1Y2I0YjBlZjA0NzNmMTY2ZDUwNzEyZmNmZmI2Mjg2MTMxIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6MTYsInNlY3JldCI6Imk5UWFvUUtVbE5MM1RBR0Z0eWVZcDlzc3E2K1ZFZWFJekR4ak9ETVo4REU9IiwiQyI6IjAzODUxY2ZlZDk5ODQxZWYyZWJhZWYxZGYyYjQ5NjI4ZjAzOGMwMzRiMDY4NjFmZDFmNjJiMzY5OGU5OGFmYzNjOCJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjEsInNlY3JldCI6IkpvTGl6N0x3a2gyTWhhc3hDNkxXM2J3cTNNWEtPanhBMHJCdWhPZnV1bjQ9IiwiQyI6IjAyNDVkNzg3MDFhYTlmOTM4MTkyOWMwYTkwN2U5M2E0NGZiYzM3NWFmYjlkMWY4ZDEzNjk1OTMxNDFlMzBjYWY5MiJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjIsInNlY3JldCI6InlMeFBOQldwSms3bmZnYTJhZlRhVjZ1Mzlaamt6NkQrdFpkTkFiTUducEE9IiwiQyI6IjAzOWY3MGU5ZjRmZTFmNTQ4YjgzMWYyZDRlODFlNjU0YmJhNjc4MTE2N2I4ZDMxNjljYWYwNjE5MmFjZWE4NTkyYSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjgsInNlY3JldCI6IlRSQlpEZm8wcVBKQ2xObnQ4VUNmdWtHUmx2N2N1SlhKU3Rya0cyTEJPZkU9IiwiQyI6IjAzZDg2NDkzZmE1YzllMDA1MWEyZjBjN2U0YWJkOWRhYzJjNDY2ZDVmNjJmOTJiOTk3ZWRiNmI0MmVmYjdjOGJkOSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjE2LCJzZWNyZXQiOiJEWmVjUkVqME1iT3B2Z0RqbXdTNkVHSkt5R2tKeHI5eHN0aGo0aVhzRjcwPSIsIkMiOiIwMjlkZDQ4ZDY0ZGVkMWQ4NTFlMWIwMTYxNTFjMWVmZTkyYTc1ZTYwM2VjNmIxNGFmYjcxM2RiYmE2OGJjNzQ0MDkifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJ3M1ZFYUljbmltSTg2RXRUTzczUHdqc0xVamlQQy8zbnpjaUVDM0x3UGJFPSIsIkMiOiIwMjk5YTY0MDc4OGZkNDZjNWRiMDg2MDU1MGQ3MzNhYjAxMWQxMjMxOGI4ZTk5YzUzZjM0MWQ2ZmY4ZjNhODJhMWYifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo4LCJzZWNyZXQiOiJwWjZoMktCaVZDNHhsNkxkOExlWnlrYXZRQUJ0M0xETFZPem1qMmFtb0k0PSIsIkMiOiIwMzc2ZTE5ZWQxNzIyMmVhODNiNDhkYWFkOTMwMGM1MDg1YzkzYWYzNDQ1MGE2NGE0ZDFlZjNkNTE1OGEyMjViMGEifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJrZitpbVJIbk9vSnhYaW8rOW12aUZkanVRNmR3THZQWHRUQWtCam95SWQ4PSIsIkMiOiIwMzhhZDUyNjY0Mjk4MDQwNTRhZTAyNWYwNmUwZWMyZmFhZTYyMjFiODRkYTE5ZjIxOTM3YTU2MjQyMmNlMzAxN2IifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoyLCJzZWNyZXQiOiIxanFiOXRjSGZhcnRWTjlsVURVYTlaRjROcGl3ODdlRFhwMk4wVFZCWWFjPSIsIkMiOiIwM2U1ZGFkZThmNmQwZWY4MzlhYzM2Nzk5MTlmMDk2OGU4ODQ3ODZiNWU0MDhlZDUxMTkwNzcxMjA5YmIyZGY3YWIifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo4LCJzZWNyZXQiOiJKNUtWY044RVJ0dFV1ck9tOE5zbUFUdmdES3pmU2htUDJXeFQvY0ZzTVJBPSIsIkMiOiIwMzA1MDVhNGY4MjQ1ZDE5ZmM5ZTIyYTE5OGEzOWJmNmEzNmZlM2Q1NzYxMjY0NmFjMjBhNGViYTk3YmQ2M2U1MDQifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxNiwic2VjcmV0IjoiZkdWUVRyWGZuVWEvQm8xUlU3Q251OWxMY25uSFZua1crbFVnZE4wL0dFaz0iLCJDIjoiMDI3NGFlY2Y1MWNmYTUxMWU1MWRiYjJiOGFjNzAwMDA3NzEyYjhlNTEzZTU4Y2NiZTZiY2ZjYjE2MmE3ZmMzYjJlIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6MSwic2VjcmV0IjoiNS9DNlA0NmJMNk1sQjY1UUxmSWFKUWlsRFJYajVydys4Y2FMYXpnZk5XUT0iLCJDIjoiMDM2YTkzN2ZjZmE4ZTlhMjZmOGFlMTJhMGRhNTMzNDg1N2Q3YTIxNWFkMzgzMzJhZDc0ZGY1M2VlYjQ3ZGQ4ZWRkIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6Miwic2VjcmV0IjoiTEw3UDNRenBiZm85SVVXUDNoWkJyVUdjcVpWcEZFRUxKT214d1V6UTNhST0iLCJDIjoiMDI3NzY0YTA4M2NkZGI0OTkxNzM1ZDIzYjE0ZDQ0Nzc1NTljMzdiNDcwN2VlMjU0YTc0ZWUyZDM1YWJiOWEzMTkxIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6OCwic2VjcmV0IjoiN3VTV1hoTTBmRlVMWEJsTHNSbnduYnJuaDgwTU5BdUNHS0pRa1VuZmtrUT0iLCJDIjoiMDMyMjUzMjc2ZDkyZTc4MzE4MjJkMjVjODczMmYzNzFhYjFlMDIwOWI1NmVkZjlkYzZlYzk4NDY5MWMzYWIyMDFmIn0seyJpZCI6Ik95N0Z1RkRhc2h6byIsImFtb3VudCI6MTYsInNlY3JldCI6ImVUZWJxWitBbDlRWUVLbC9USExSRXoxVTN5OEJ3NE5naWNkZHg2bjlKc0k9IiwiQyI6IjAyOTU2MTQ2NTg1NzU0NTA4MGMwYzVhMTIwNzlhNDliYTQ1YTJiNTc4ZjdkNmQwNmVhNWU4MmFiZDM1N2U1Nzg1NyJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjEsInNlY3JldCI6InJVZ1AySndJUjcwNkhnOTdScGlPYnVoMTZLeCtwNWdvKzVlSGRxR3kwS009IiwiQyI6IjAyYWZmZWU2ZTA1NGQ4ZjJhNzczM2FiMzBhOTI0MGNkMWJlMTNlZjZkODhhZDM0MGUzNjU4ZDc0YTJhZjhiZGYyNSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjIsInNlY3JldCI6IjdQQTRsNGxIMldtTThuYXk3RHJ4QnNkKzd6SjUvMnhJLytVa1hQQkRWdUk9IiwiQyI6IjAyNWZhNzIwOWIwNmQ0N2Q1NDgxMWViZDM2ZjBkYzk4NTc3ZDc5MDAxNWI2OGYzYjVlYWM5OTAyNmYxODY4ZjMyNiJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjgsInNlY3JldCI6IlgvRGpWckplWTVPcGdyVXBmK2QwTFJnMzVXQjN0c0xDcU4wWGE5WDViTWs9IiwiQyI6IjAyNjY1MzU3YzkxMDRhY2EwZjE5ZTM2NGNjNzcxODEwOGUwNTc0YWMxMDdlYTIxMDk0OGYzNjI1MzA1MGU5ZTkxZCJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjQsInNlY3JldCI6InEyVUFoVGhaeFYvWkI3dStjZE5qZG1rd1dONGtJRWZxM0kzVjJ3NGpmL0E9IiwiQyI6IjAzYjY5ODVkN2E2YTZiY2Q0ZDBhYjUzNWUwNDFkYTdjMzZlYjY2ZDk4NDAyMmMyNjcwYjkyYjA4MjNlMzM1OGRmNSJ9LHsiaWQiOiJPeTdGdUZEYXNoem8iLCJhbW91bnQiOjE2LCJzZWNyZXQiOiIwd1d4RnhYY1VZa1lqSkx1cmZyMGhIQUFoWjFFWTNlVHV6UG1DSXk1OG9vPSIsIkMiOiIwMjA2MjBmOTE1NmQ4OGJjYTJlYjRiMzBiNmFjY2M0OTlkNmZkNjE5YTc3MjkxMmU4NDhlMmE0MGExNDJmMDllYzAifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50IjoxLCJzZWNyZXQiOiJIMmQzOHRRTTljZ0tNY0FUcUp0MXRNOFYxNmhjZm40SHRJVW41Zm9zaWVRPSIsIkMiOiIwMjI0OTYwZDRiZDhmNTEzMWNhN2VhMGNhZTc0Nzc5ZWU4ODQ1MGE0OTU2NDdkM2Q0MTIwZGVkYmFiMWEyNmI3ODEifSx7ImlkIjoiT3k3RnVGRGFzaHpvIiwiYW1vdW50Ijo4LCJzZWNyZXQiOiIra3IxOERQVCtmdXJFZk5CSXh6aVBRWCtaSE85UjBZRXdic3VNWjJqV1dBPSIsIkMiOiIwMmVlZTE2N2UwMTllZTMyMDE3M2E1ZDlkYTIwNzA2ZDA1M2M0YmRkMzY1ZDY4OTc5YmE2MWM1MWY5NTEyZWVlODAifV19XX0")
            })
            Button(action: {
                vm.redeem()
            }, label: {
                if vm.loading {
                    Text("Sending...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if vm.success {
                    Text("Done!")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.green)
                } else {
                    Text("Redeem")
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            })
            .foregroundColor(.white)
            .buttonStyle(.bordered)
            .padding()
            .bold()
            .toolbar(.hidden, for: .tabBar)
            .disabled(vm.token == nil || vm.loading || vm.success || vm.addingMint)
        }
    }
}

#Preview {
    ReceiveView()
}

@MainActor
class ReceiveViewModel: ObservableObject {
    
    @Published var token:String?
    @Published var tokenParts = [TokenPart]()
    @Published var tokenMemo:String?
    @Published var loading = false
    @Published var success = false
    @Published var totalAmount:Int?
//    @Published var unknownMint = false
    @Published var addingMint = false
    
    @Published var refreshCounter:Int = 0
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    var wallet = Wallet.shared
    
    func paste() {
        let pasteString = UIPasteboard.general.string ?? ""
        parseToken(token: pasteString)
    }
    
    func parseToken(token:String) {
        let deserialized:Token_Container
        
        do {
            deserialized = try wallet.deserializeToken(token: token)
        } catch {
            displayAlert(alert: AlertDetail(title: "Invalid token",
                                            description: "This token could not be read. Input: \(token.prefix(20))... Error: \(String(describing: error))"))
            return
        }
        
        self.token = token
        tokenMemo = deserialized.memo
        
        tokenParts = []
        totalAmount = 0
        for token in deserialized.token {
            let tokenAmount = amountForToken(token: token)
            let known = wallet.database.mints.contains(where: { $0.url.absoluteString.contains(token.mint) })
            let part = TokenPart(token: token, knownMint: known, amount: tokenAmount)
            tokenParts.append(part)
            totalAmount! += tokenAmount
        }
        for part in tokenParts {
            checkTokenState(for: part)
        }
    }
    
    func amountForToken(token:Token_JSON) -> Int {
        var total = 0
        for proof in token.proofs {
            total += proof.amount
        }
        return total
    }
    
    func checkTokenState(for tokenPart:TokenPart) {
        Task {
            do {
                let spendable = try await wallet.checkTokenStateSpendable(for:tokenPart.token)
                if spendable {
                    tokenPart.state = .spendable
                    print("token is spendable")
                } else {
                    tokenPart.state = .notSpendable
                    print("token is NOT spendable")
                }
            } catch {
                tokenPart.state = .mintUnavailable
                print("mint unavailable " + tokenPart.token.mint)
            }
            refreshCounter += 1
        }
    }
    
    func addUnknownMint(for tokenPart:TokenPart) {
        Task {
            guard let url = URL(string: tokenPart.token.mint) else {
                return
            }
            tokenPart.addingMint = true
            addingMint = true
            do {
                try await wallet.addMint(with:url)
                tokenPart.knownMint = true
                tokenPart.addingMint = false
                addingMint = false
            } catch {
                displayAlert(alert: AlertDetail(title: "Could not add mint", 
                                                description: String(describing: error)))
                tokenPart.addingMint = false
                addingMint = false
            }
        }
    }

    func redeem() {
        guard !tokenParts.contains(where: { $0.state == .notSpendable }) else {
            displayAlert(alert: AlertDetail(title: "Unable to redeem", description: "One or more parts of this token are not spendable. macadamia does not yet support redeeming only parts of a token."))
            return
        }
        loading = true
        Task {
            do {
                try await wallet.receiveToken(tokenString: token!)
                self.loading = false
                self.success = true
            } catch {
                displayAlert(alert: AlertDetail(title: "Redeem failed",
                                               description: String(describing: error)))
                self.loading = false
                self.success = false
            }
        }
    }
    
    func reset() {
        token = nil
        tokenMemo = nil
        tokenParts = []
        tokenMemo = nil
        success = false
        addingMint = false
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

enum TokenPartState {
    case spendable
    case notSpendable
    case mintUnavailable
    case unknown
}

class TokenPart:ObservableObject, Hashable {
    
    @Published var token:Token_JSON
    @Published var knownMint:Bool
    @Published var amount:Int
    @Published var addingMint:Bool
    @Published var state:TokenPartState
    
    static func == (lhs: TokenPart, rhs: TokenPart) -> Bool {
            lhs.token.proofs == rhs.token.proofs
        }
    
    func hash(into hasher: inout Hasher) {
        for proof in token.proofs {
            hasher.combine(proof.C)
        }
    }
    
    init(token: Token_JSON, 
         knownMint: Bool,
         amount: Int,
         addingMint: Bool = false,
         state:TokenPartState = .unknown) {
        self.token = token
        self.knownMint = knownMint
        self.amount = amount
        self.addingMint = addingMint
        self.state = state
    }
}
