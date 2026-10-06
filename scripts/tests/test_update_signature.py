import base64
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "verify-update.swift"


class UpdateSignatureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture = subprocess.check_output([
            "swift", "-e", '''
import CryptoKit
import Foundation
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 1, count: 32))
let other = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 2, count: 32))
let data = Data("candidate archive".utf8)
let fixture = ["public": key.publicKey.rawRepresentation.base64EncodedString(),
               "other": other.publicKey.rawRepresentation.base64EncodedString(),
               "signature": try key.signature(for: data).base64EncodedString()]
print(String(data: try JSONSerialization.data(withJSONObject: fixture), encoding: .utf8)!)
''',
        ], text=True)
        cls.fixture = json.loads(fixture)

    def verify(self, data, public_key=None, signature=None):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "update.zip"
            archive.write_bytes(data)
            return subprocess.run([
                "swift", str(SCRIPT), public_key or self.fixture["public"], str(archive),
                signature or self.fixture["signature"],
            ], capture_output=True, text=True)

    def test_valid_archive_is_accepted(self):
        result = self.verify(b"candidate archive")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_corrupted_archive_is_rejected(self):
        self.assertNotEqual(self.verify(b"corrupted archive").returncode, 0)

    def test_wrong_bundle_key_is_rejected(self):
        self.assertNotEqual(self.verify(b"candidate archive", self.fixture["other"]).returncode, 0)

    def test_missing_archive_signature_is_rejected(self):
        self.assertNotEqual(self.verify(b"candidate archive", signature=base64.b64encode(b"invalid").decode()).returncode, 0)


if __name__ == "__main__":
    unittest.main()
