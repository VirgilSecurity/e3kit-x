//
// Copyright (C) 2015-2019 Virgil Security Inc.
//
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     (1) Redistributions of source code must retain the above copyright
//     notice, this list of conditions and the following disclaimer.
//
//     (2) Redistributions in binary form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer in
//     the documentation and/or other materials provided with the
//     distribution.
//
//     (3) Neither the name of the copyright holder nor the names of its
//     contributors may be used to endorse or promote products derived from
//     this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR ''AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
// INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
// STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
// IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Lead Maintainer: Virgil Security Inc. <support@virgilsecurity.com>
//

import VirgilSDK
import VirgilSDKRatchet
import VirgilCryptoRatchet

public extension EThree {
    func createRatchetChat(with card: Card) -> GenericOperation<RatchetChat> {
        return CallbackOperation { _, completion in
            do {
                let secureChat = try self.getSecureChat()

                guard card.identity != self.identity else {
                    throw EThreeRatchetError.selfChatIsForbidden
                }

                let session = try secureChat.startNewSessionAsSender(receiverCard: card).startSync().get()

                let ticket = try session.encrypt(string: UUID().uuidString)

                try self.cloudRatchetStorage.store(ticket, sharedWith: card)

                let ratchetChat = RatchetChat(session: session,
                                              sessionStorage: secureChat.sessionStorage)

                completion(ratchetChat, nil)
            } catch SecureChatError.sessionAlreadyExists {
                completion(nil, EThreeRatchetError.chatAlreadyExists)
            } catch {
                completion(nil, error)
            }
        }
    }

    func joinRatchetChat(with card: Card) -> GenericOperation<RatchetChat> {
        return CallbackOperation { _, completion in
            do {
                let secureChat = try self.getSecureChat()

                let ticket = try self.cloudRatchetStorage.retrieve(from: card)

                let session = try secureChat.startNewSessionAsReceiver(senderCard: card, ratchetMessage: ticket)

                let ratchetChat = RatchetChat(session: session, sessionStorage: secureChat.sessionStorage)

                completion(ratchetChat, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    func getRatchetChat(with card: Card) throws -> RatchetChat? {
        let secureChat = try self.getSecureChat()
        guard let session = secureChat.existingSession(withParticipantIdentity: card.identity) else {
            return nil
        }
        return RatchetChat(session: session, sessionStorage: secureChat.sessionStorage)
    }

    func deleteRatchetChat(with card: Card) throws {
        let secureChat = try self.getSecureChat()

        do {
            try secureChat.deleteSession(withParticipantIdentity: card.identity)
        } catch CocoaError.fileNoSuchFile {
            throw EThreeRatchetError.missingChat
        }
    }
}