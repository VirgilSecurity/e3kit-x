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

// MARK: - Extension with authorization operations
extension EThree {
    /// Initializes E3Kit with a callback to get Virgil access token
    ///
    /// - Parameters:
    ///   - tokenCallback: callback to get Virgil access token
    ///   - storageParams: `KeychainStorageParams` with specific parameters
    public static func initialize(tokenCallback: @escaping RenewJwtCallback,
                                  changedKeyDelegate: ChangedKeyDelegate? = nil,
                                  storageParams: KeychainStorageParams? = nil) -> GenericOperation<EThree> {
        return CallbackOperation { _, completion in
            do {
                let accessTokenProvider = CachingJwtProvider { tokenCallback($1) }

                let tokenContext = TokenContext(service: "cards", operation: "")

                let getTokenOperation = CallbackOperation<AccessToken> { _, completion in
                    accessTokenProvider.getToken(with: tokenContext, completion: completion)
                }

                let token = try getTokenOperation.startSync().get()

                let ethree = try EThree(identity: token.identity(),
                                        accessTokenProvider: accessTokenProvider,
                                        changedKeyDelegate: changedKeyDelegate,
                                        storageParams: storageParams)

                completion(ethree, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    /// Generates new Private Key, publishes Card on Virgil Cards Service and saves Private Key in local storage
    ///
    /// - Returns: CallbackOperation<Void>
    public func register() -> GenericOperation<Void> {
        return CallbackOperation { _, completion in
            self.queue.async {
                do {
                    guard try !self.localKeyStorage.exists() else {
                        throw EThreeError.privateKeyExists
                    }

                    let cards = try self.cardManager.searchCards(identities: [self.identity]).startSync().get()

                    guard cards.isEmpty else {
                        throw EThreeError.userIsAlreadyRegistered
                    }

                    try self.publishCardThenSaveLocal()

                    completion((), nil)
                } catch {
                    completion(nil, error)
                }
            }
        }
    }

    /// Generates new Private Key, publishes new Card to replace the current one on Virgil Cards Service
    /// and saves new Private Key in local storage
    ///
    /// - Returns: CallbackOperation<Void>
    public func rotatePrivateKey() -> GenericOperation<Void> {
        return CallbackOperation { _, completion in
            self.queue.async {
                do {
                    guard try !self.localKeyStorage.exists() else {
                        throw EThreeError.privateKeyExists
                    }

                    let cards = try self.cardManager.searchCards(identities: [self.identity]).startSync().get()

                    guard let card = cards.first else {
                        throw EThreeError.userIsNotRegistered
                    }

                    try self.publishCardThenSaveLocal(previousCardId: card.identifier)

                    completion((), nil)
                } catch {
                    completion(nil, error)
                }
            }
        }
    }

    /// Revokes Card from Virgil Cards Service, deletes Private Key from local storage
    ///
    /// - Returns: CallbackOperation<Void>
    public func unregister() -> GenericOperation<Void> {
        return CallbackOperation { _, completion in
            self.queue.async {
                do {
                    let cards = try self.cardManager.searchCards(identities: [self.identity]).startSync().get()

                    guard let card = cards.first else {
                        throw EThreeError.userIsNotRegistered
                    }

                    try self.cardManager.revokeCard(withId: card.identifier).startSync().get()

                    try self.localKeyStorage.delete()

                    try self.privateKeyDeleted()

                    completion((), nil)
                } catch {
                    completion(nil, error)
                }
            }
        }
    }

    /// Checks existance of private key in keychain storage
    ///
    /// - Returns: true if private key exists in keychain storage
    /// - Throws: KeychainStorageError
    public func hasLocalPrivateKey() throws -> Bool {
        return try self.localKeyStorage.exists()
    }

    /// Deletes Private Key from local storage
    ///
    /// - Throws: KeychainStorageError
    @objc public func cleanUp() throws {
        try self.localKeyStorage.delete()

        try self.privateKeyDeleted()
    }
}
