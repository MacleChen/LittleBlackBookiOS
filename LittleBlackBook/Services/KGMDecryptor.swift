import Foundation
import CryptoKit

/// Decrypts Kugou Music encrypted files (.kgm, .kgma, .vpr).
///
/// Algorithm source: unlock-music project (MIT License)
/// https://git.unlock-music.dev/um/cli/src/tag/v0.2.12/algo/kgm
struct KGMDecryptor {

    // MARK: - Magic headers

    /// KGM/KGMA file magic (first 8 bytes are consistent across versions)
    private static let kgmMagicPrefix: [UInt8] = [
        0x7C, 0xD5, 0x32, 0xEB, 0x86, 0x02, 0x7F, 0x4B
    ]
    /// VPR file magic
    private static let vprMagicPrefix: [UInt8] = [
        0x05, 0x28, 0xBC, 0x96, 0xE9, 0xE4, 0x5A, 0x43
    ]

    // MARK: - Slot keys (KGM v3)

    /// Maps CryptoSlot → 4-byte slot key used to derive slotBox via kugouMD5
    private static let slotKeys: [UInt32: [UInt8]] = [
        1: [0x6C, 0x2C, 0x2F, 0x27]
    ]

    // MARK: - Errors

    enum DecryptError: LocalizedError {
        case fileTooSmall
        case invalidMagic
        case unsupportedVersion(UInt32)
        case unknownSlot(UInt32)
        case writeError

        var errorDescription: String? {
            switch self {
            case .fileTooSmall:              return "KGM 文件太小或已损坏"
            case .invalidMagic:              return "不是有效的 KGM / VPR 文件"
            case .unsupportedVersion(let v): return "不支持的 KGM 加密版本 v\(v)，目前仅支持 v3"
            case .unknownSlot(let s):        return "未知的 KGM 密钥槽 \(s)"
            case .writeError:                return "写入临时解密文件失败"
            }
        }
    }

    // MARK: - Public API

    /// Decrypts a KGM/KGMA/VPR file and returns the raw audio data.
    /// - Parameter url: Path to the encrypted file.
    /// - Returns: Decrypted audio bytes (MP3, FLAC, or similar).
    static func decrypt(at url: URL) throws -> Data {
        let raw = try Data(contentsOf: url)
        var bytes = [UInt8](raw)

        guard bytes.count > 64 else { throw DecryptError.fileTooSmall }

        // --- Validate magic (first 8 bytes) ---
        let prefix = Array(bytes[0..<8])
        guard prefix == kgmMagicPrefix || prefix == vprMagicPrefix else {
            throw DecryptError.invalidMagic
        }

        // --- Parse header (all values little-endian uint32) ---
        let audioOffset    = le32(bytes, at: 16)
        let cryptoVersion  = le32(bytes, at: 20)
        let cryptoSlot     = le32(bytes, at: 24)

        guard cryptoVersion == 3 else {
            throw DecryptError.unsupportedVersion(cryptoVersion)
        }
        guard let slotKey = slotKeys[cryptoSlot] else {
            throw DecryptError.unknownSlot(cryptoSlot)
        }

        // CryptoKey occupies the 16 bytes immediately before the audio data.
        let keyStart = Int(audioOffset) - 16
        guard keyStart >= 28, Int(audioOffset) <= bytes.count else {
            throw DecryptError.fileTooSmall
        }
        let cryptoKey = Array(bytes[keyStart ..< Int(audioOffset)])

        // --- Build decryption boxes ---
        // slotBox: 16-byte kugouMD5 of the slot key
        let slotBox = kugouMD5(slotKey)
        // fileBox: 17-byte kugouMD5 of the crypto key + 0x6B trailer
        var fileBox = kugouMD5(cryptoKey)
        fileBox.append(0x6B)

        // --- Decrypt audio data ---
        let start = Int(audioOffset)
        let count = bytes.count - start

        for i in 0 ..< count {
            bytes[start + i] ^= fileBox[i % 17]
            bytes[start + i] ^= bytes[start + i] << 4   // XOR with already-modified nibble
            bytes[start + i] ^= slotBox[i % 16]
            bytes[start + i] ^= xorCollapse(UInt32(i))
        }

        return Data(bytes[start...])
    }

    /// Detects the audio format from the decrypted data header and returns a suitable extension.
    static func audioExtension(for data: Data) -> String {
        let h = [UInt8](data.prefix(12))
        // MP3 with ID3 tag
        if h.prefix(3) == [0x49, 0x44, 0x33] { return "mp3" }
        // MP3 sync word
        if h.prefix(2) == [0xFF, 0xFB] || h.prefix(2) == [0xFF, 0xF3] ||
           h.prefix(2) == [0xFF, 0xF2] { return "mp3" }
        // FLAC
        if h.prefix(4) == [0x66, 0x4C, 0x61, 0x43] { return "flac" }
        // OGG (not natively supported on iOS but we let AVAudioPlayer try)
        if h.prefix(4) == [0x4F, 0x67, 0x67, 0x53] { return "ogg" }
        // MPEG-4 / M4A (ftyp box)
        if h.count >= 8 && h[4...7] == [0x66, 0x74, 0x79, 0x70] { return "m4a" }
        return "mp3"   // default fallback
    }

    // MARK: - Private helpers

    /// Read a little-endian uint32 from bytes at the given byte offset.
    private static func le32(_ b: [UInt8], at offset: Int) -> UInt32 {
        UInt32(b[offset]) |
        UInt32(b[offset + 1]) << 8  |
        UInt32(b[offset + 2]) << 16 |
        UInt32(b[offset + 3]) << 24
    }

    /// Kugou-modified MD5: compute MD5 then reverse byte pairs.
    ///
    /// For i in stride(0, 16, by: 2):
    ///   result[i]   = digest[14 - i]
    ///   result[i+1] = digest[14 - i + 1]
    private static func kugouMD5(_ input: [UInt8]) -> [UInt8] {
        let digest = [UInt8](Insecure.MD5.hash(data: Data(input)))
        var result = [UInt8](repeating: 0, count: 16)
        var i = 0
        while i < 16 {
            result[i]     = digest[14 - i]
            result[i + 1] = digest[14 - i + 1]
            i += 2
        }
        return result
    }

    /// XOR all 4 bytes of a uint32 into a single byte.
    private static func xorCollapse(_ v: UInt32) -> UInt8 {
        UInt8(v & 0xFF) ^ UInt8((v >> 8) & 0xFF) ^ UInt8((v >> 16) & 0xFF) ^ UInt8((v >> 24) & 0xFF)
    }
}
