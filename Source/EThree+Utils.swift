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
import VirgilCrypto
import VirgilSDKRatchet

extension EThree {
    internal func privateKeyChanged(card: Card? = nil) throws {
        if let card = card {
            try self.lookupManager.cardStorage.storeCard(card)
        }

        let selfKeyPair = try self.localKeyStorage.retrieveKeyPair()

        let localGroupStorage = try FileGroupStorage(identity: self.identity,
                                                     crypto: self.crypto,
                                                     identityKeyPair: selfKeyPair)
        let cloudTicketStorage = try CloudTicketStorage(accessTokenProvider: self.accessTokenProvider,
                                                        localKeyStorage: self.localKeyStorage)
        self.groupManager = GroupManager(localGroupStorage: localGroupStorage,
                                         cloudTicketStorage: cloudTicketStorage,
                                         localKeyStorage: self.localKeyStorage,
                                         lookupManager: self.lookupManager,
                                         crypto: self.crypto)

        if self.enableRatchet {
            guard let selfCard = card ?? self.findCachedUser(with: self.identity) else {
                throw NSError()
            }

            try self.setupSecureChat(keyPair: selfKeyPair, card: selfCard)
        }
    }

    internal func privateKeyDeleted() throws {
        try self.lookupManager.cardStorage.reset()
        try self.groupManager?.localGroupStorage.reset()

        self.groupManager = nil
        self.secureChat = nil
        self.timer = nil
    }

    internal func computeSessionId(from identifier: Data) throws -> Data {
        guard identifier.count > 10 else {
            throw GroupError.shortGroupId
        }

        return self.crypto.computeHash(for: identifier, using: .sha512).subdata(in: 0..<32)
    }

    internal static func getConnection() -> HttpConnection {
        let version = VersionUtils.getVersion(bundleIdentitifer: "com.virgilsecurity.VirgilE3Kit")
        let adapters = [VirgilAgentAdapter(product: "e3kit", version: version)]

        return HttpConnection(adapters: adapters)
    }

    internal func publishCardThenSaveLocal(keyPair: VirgilKeyPair? = nil, previousCardId: String? = nil) throws {
        let keyPair = try keyPair ?? self.crypto.generateKeyPair()

        let card = try self.cardManager.publishCard(privateKey: keyPair.privateKey,
                                                    publicKey: keyPair.publicKey,
                                                    identity: self.identity,
                                                    previousCardId: previousCardId)
            .startSync()
            .get()

        let data = try self.crypto.exportPrivateKey(keyPair.privateKey)

        try self.localKeyStorage.store(data: data)

        try self.privateKeyChanged(card: card)
    }

    internal func getGroupManager() throws -> GroupManager {
        guard let manager = self.groupManager else {
            throw EThreeError.missingPrivateKey
        }

        return manager
    }
}

extension EThree {
    internal func setupSecureChat(keyPair: VirgilKeyPair, card: Card) throws {
        let context = SecureChatContext(identityCard: card,
                                        identityPrivateKey: keyPair.privateKey,
                                        accessTokenProvider: self.accessTokenProvider)

        let chat = try SecureChat(context: context)

        do {
            try chat.reset().startSync().get()
        } // When there's no keys on cloud. Should be fixed on server side.
        catch let error as NSError where error.code == 50_017 {}

        Log.debug("Key rotation started")
        let logs = try chat.rotateKeys().startSync().get()
        Log.debug("Key rotation succeed: \(logs.description)")

        self.scheduleKeyRotation(with: chat)

        self.secureChat = chat
    }

    private func scheduleKeyRotation(with chat: SecureChat) {
        self.timer = RepeatingTimer(interval: self.keyRotationInterval) {
            Log.debug("Key rotation started")
            do {
                let logs = try chat.rotateKeys().startSync().get()
                Log.debug("Key rotation succeed: \(logs.description)")
            } catch {
                Log.error("Key rotation failed: \(error.localizedDescription)")
            }
        }

        self.timer?.resume()
    }

    internal func getSecureChat() throws -> SecureChat {
        guard let secureChat = self.secureChat else {
            throw EThreeError.missingPrivateKey
        }

        return secureChat
    }
}