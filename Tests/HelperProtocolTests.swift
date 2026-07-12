// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Aditya Kar

import Foundation
import Testing

@Suite struct HelperProtocolTests {
    // The daemon verifies an ECDSA signature over exactly these bytes; any drift
    // in the canonical format breaks every privileged write. Pin the byte layout.
    @Test func canonicalMessageByteIdentity() {
        let msg = HelperProtocol.canonicalMessage(ts: 1_752_300_000,
                                                  nonce: "8B4E9C0A-6F1D-4A5B-9E2C-7D3F1A0B5C8D",
                                                  contentB64: "MTI3LjAuMC4xIGxvY2FsaG9zdAo=")
        let expected = Data("hostshelper-v1\n1752300000\n8B4E9C0A-6F1D-4A5B-9E2C-7D3F1A0B5C8D\nMTI3LjAuMC4xIGxvY2FsaG9zdAo=".utf8)
        #expect(msg == expected, "canonical message: byte-identical to the documented v1 format")
    }

    @Test func protocolConstants() {
        #expect(HelperProtocol.version == 1, "protocol version is 1")
        #expect(HelperProtocol.plistName == HelperProtocol.label + ".plist",
                "plist file-name stem must equal the launchd label")
    }
}
