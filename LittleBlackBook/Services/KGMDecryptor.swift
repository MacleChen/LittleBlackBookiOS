import Foundation
import CryptoKit

/// Decrypts Kugou Music encrypted files (.kgm / .vpr).
///
/// Algorithm: KGM v3 — reverse-engineered, open-sourced under MIT by the unlock-music project.
/// Reference: https://git.unlock-music.dev/um/cli/src/tag/v0.2.12/algo/kgm
struct KGMDecryptor {

    // MARK: - Magic headers (exact 16 bytes from unlock-music source)

    private static let kgmMagic: [UInt8] = [
        0x7C, 0xD5, 0x32, 0xEB, 0x86, 0x02, 0x7F, 0x4B,
        0xA8, 0xAF, 0xA6, 0x8E, 0x0F, 0xFF, 0x99, 0x14
    ]
    private static let vprMagic: [UInt8] = [
        0x05, 0x28, 0xBC, 0x96, 0xE9, 0xE4, 0x5A, 0x43,
        0x91, 0xAA, 0xBD, 0xD0, 0x7A, 0xF5, 0x36, 0x31
    ]

    // MARK: - Header layout (from Go source)
    //
    // 0x00–0x0F  MagicHeader  (16 bytes)
    // 0x10–0x13  AudioOffset  (uint32 LE) – typically 0x3C = 60
    // 0x14–0x17  CryptoVersion (uint32 LE) – 3 or 5
    // 0x18–0x1B  CryptoSlot   (uint32 LE)
    // 0x1C–0x2B  CryptoTestData (16 bytes)
    // 0x2C–0x3B  CryptoKey    (16 bytes)
    // 0x3C–     Audio data

    // MARK: - Slot keys for KGM v3

    /// Only slot 1 is known for v3. If CryptoSlot ≠ 1, decryption cannot proceed.
    private static let slotKeys: [UInt32: [UInt8]] = [
        1: [0x6C, 0x2C, 0x2F, 0x27]
    ]

    // MARK: - Errors

    enum DecryptError: LocalizedError {
        case fileTooSmall
        case invalidMagic(prefix: String)
        case unsupportedVersion(UInt32)
        case unknownSlot(UInt32)

        var errorDescription: String? {
            switch self {
            case .fileTooSmall:
                return "KGM 文件太小或已损坏"
            case .invalidMagic(let p):
                return "文件头不匹配，不是有效的 KGM/VPR 文件（文件头: \(p)）"
            case .unsupportedVersion(let v):
                if v == 5 {
                    return "该文件是 KGM v5 加密格式，需要酷狗 PC 客户端的数据库文件才能解密，暂不支持"
                }
                return "不支持的 KGM 加密版本 v\(v)（当前仅支持 v3）"
            case .unknownSlot(let s):
                return "未知的 KGM 密钥槽 \(s)，无法解密"
            }
        }
    }

    // MARK: - Public API

    /// Decrypts a KGM/VPR file, returning the raw audio bytes (MP3, FLAC, etc.).
    static func decrypt(at url: URL) throws -> Data {
        let raw = try Data(contentsOf: url)
        var bytes = [UInt8](raw)

        guard bytes.count >= 64 else { throw DecryptError.fileTooSmall }

        // --- Validate magic (full 16 bytes) ---
        let magic = Array(bytes[0..<16])
        guard magic == kgmMagic || magic == vprMagic else {
            let hexPrefix = bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
            throw DecryptError.invalidMagic(prefix: hexPrefix)
        }

        // --- Parse header ---
        let audioOffset   = le32(bytes, at: 0x10)   // 0x10 = 16
        let cryptoVersion = le32(bytes, at: 0x14)   // 0x14 = 20
        let cryptoSlot    = le32(bytes, at: 0x18)   // 0x18 = 24

        guard cryptoVersion == 3 else {
            throw DecryptError.unsupportedVersion(cryptoVersion)
        }
        guard let slotKey = slotKeys[cryptoSlot] else {
            throw DecryptError.unknownSlot(cryptoSlot)
        }

        // CryptoKey occupies bytes[0x2C..<0x3C] = bytes[44..<60]
        // This also equals bytes[audioOffset-16 ..< audioOffset] when audioOffset == 0x3C.
        let keyStart = Int(audioOffset) - 16
        guard keyStart >= 28, Int(audioOffset) <= bytes.count else {
            throw DecryptError.fileTooSmall
        }
        let cryptoKey = Array(bytes[keyStart ..< Int(audioOffset)])

        // --- Build decryption boxes ---
        let slotBox = kugouMD5(slotKey)       // 16 bytes
        var fileBox = kugouMD5(cryptoKey)     // 16 bytes
        fileBox.append(0x6B)                  // → 17 bytes

        // --- Decrypt audio in-place ---
        // For each byte at audio-relative position i:
        //   b ^= fileBox[i % 17]
        //   b ^= b << 4
        //   b ^= slotBox[i % 16]
        //   b ^= xorCollapse(i)
        let start = Int(audioOffset)
        let count = bytes.count - start

        for i in 0 ..< count {
            let pos = start + i
            var b = bytes[pos]
            b ^= fileBox[i % 17]
            b ^= b << 4
            b ^= slotBox[i % 16]
            b ^= xorCollapse(UInt32(i))
            bytes[pos] = b
        }

        return Data(bytes[start...])
    }

    /// Detects the actual audio format from the decrypted data and returns a file extension.
    static func audioExtension(for data: Data) -> String {
        let h = [UInt8](data.prefix(12))
        // FLAC
        if h.prefix(4) == [0x66, 0x4C, 0x61, 0x43] { return "flac" }
        // OGG
        if h.prefix(4) == [0x4F, 0x67, 0x67, 0x53] { return "ogg" }
        // MPEG-4 / M4A (ftyp box at offset 4)
        if h.count >= 8, Array(h[4..<8]) == [0x66, 0x74, 0x79, 0x70] { return "m4a" }
        // MP3 with ID3 tag
        if h.prefix(3) == [0x49, 0x44, 0x33] { return "mp3" }
        // MP3 sync word
        if h.count >= 2, h[0] == 0xFF, h[1] & 0xE0 == 0xE0 { return "mp3" }
        return "mp3"    // safe default — AVAudioPlayer will validate
    }

    // MARK: - Private helpers

    /// Little-endian uint32 from `bytes` at byte `offset`.
    private static func le32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])       |
        UInt32(bytes[offset + 1]) << 8  |
        UInt32(bytes[offset + 2]) << 16 |
        UInt32(bytes[offset + 3]) << 24
    }

    /// Kugou-modified MD5: compute MD5 then reverse byte-pairs.
    ///
    /// Output[i]   = MD5[14-i]     for i in stride(0, 16, by: 2)
    /// Output[i+1] = MD5[14-i+1]
    ///
    /// Result: [MD5[14], MD5[15], MD5[12], MD5[13], ..., MD5[0], MD5[1]]
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

    /// Fold all 4 bytes of a UInt32 into one byte via XOR.
    private static func xorCollapse(_ v: UInt32) -> UInt8 {
        UInt8(v & 0xFF) ^ UInt8((v >> 8) & 0xFF) ^
        UInt8((v >> 16) & 0xFF) ^ UInt8((v >> 24) & 0xFF)
    }
}
