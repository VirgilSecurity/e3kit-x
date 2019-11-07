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

extension EThree {
    /// Creates channel with unregistered user
    ///
    /// - Important: Temporary key for unregistered user is stored unencrypted on Cloud.
    ///
    /// - Parameter identity: identity of unregistered user
    open func createUnsafeChannel(with identity: String) -> GenericOperation<UnsafeChannel> {
        return CallbackOperation { _, completion in
            do {
                guard identity != self.identity else {
                    throw UnsafeChannelError.selfChannelIsForbidden
                }

                let result = try self.findUsers(with: [identity], checkResult: false).startSync().get()

                guard result.isEmpty else {
                    throw UnsafeChannelError.userIsRegistered
                }

                let unsafeChannel = try self.getUnsafeManager().create(with: identity)

                completion(unsafeChannel, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    /// Loads unsafe channel by fetching temporary key form Cloud
    /// - Parameters:
    ///   - asCreator: Bool to specify wether caller is creator of channel or not
    ///   - identity: identity of participant
    open func loadUnsafeChannel(asCreator: Bool, with identity: String) -> GenericOperation<UnsafeChannel> {
        return CallbackOperation { _, completion in
            do {
                let unsafeManager = try self.getUnsafeManager()

                guard identity != self.identity else {
                    throw UnsafeChannelError.selfChannelIsForbidden
                }

                let unsafeChannel = try unsafeManager.loadFromCloud(asCreator: asCreator, with: identity)

                completion(unsafeChannel, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    /// Returns cached unsafe channel
    /// - Parameter identity: identity of participant
    open func getUnsafeChannel(with identity: String) throws -> UnsafeChannel? {
        let unsafeManager = try self.getUnsafeManager()

        return try unsafeManager.getLocalChannel(with: identity)
    }

    /// Deletes unsafe channel from cloud (if user is creator) and local storage
    /// - Parameter identity: identity of participant
    open func deleteUnsafeChannel(with identity: String) -> GenericOperation<Void> {
        return CallbackOperation { _, completion in
            do {
                try self.getUnsafeManager().delete(with: identity)

                completion((), nil)
            } catch {
                completion(nil, error)
            }
        }
    }
}
