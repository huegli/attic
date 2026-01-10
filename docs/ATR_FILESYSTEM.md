# ATR File System Specification

## Overview

ATR is the standard disk image format for Atari 8-bit computers. This document covers the ATR container format and the Atari DOS 2.x file system structure within.

## ATR File Format

### Header (16 bytes)

| Offset | Size | Description |
|--------|------|-------------|
| 0 | 2 | Magic number: $96 $02 |
| 2 | 2 | Disk size in paragraphs (low word) |
| 4 | 2 | Sector size (128 or 256) |
| 6 | 1 | Disk size high byte |
| 7 | 4 | CRC (optional, usually 0) |
| 11 | 4 | Unused |
| 15 | 1 | Flags |

### Size Calculation

```
Total paragraphs = (header[6] << 16) | (header[3] << 8) | header[2]
Disk size in bytes = paragraphs * 16
Sector count = (disk size) / (sector size)
```

### Common Disk Sizes

| Type | Sectors | Sector Size | Total Size | Paragraphs |
|------|---------|-------------|------------|------------|
| Single Density (SS/SD) | 720 | 128 | 92,160 | 5,760 |
| Enhanced Density | 1,040 | 128 | 133,120 | 8,320 |
| Double Density (SS/DD) | 720 | 256 | 184,320 | 11,520 |
| Quad Density (DS/DD) | 1,440 | 256 | 368,640 | 23,040 |

### Sector Layout in ATR

**Single/Enhanced Density (128-byte sectors):**
```
Offset 16:     Sector 1 (128 bytes)
Offset 144:    Sector 2 (128 bytes)
Offset 272:    Sector 3 (128 bytes)
...
```

**Double Density (256-byte sectors):**
Note: First 3 sectors are still 128 bytes for boot compatibility.
```
Offset 16:     Sector 1 (128 bytes)
Offset 144:    Sector 2 (128 bytes)  
Offset 272:    Sector 3 (128 bytes)
Offset 400:    Sector 4 (256 bytes)
Offset 656:    Sector 5 (256 bytes)
...
```

### Sector Offset Calculation

```swift
func sectorOffset(_ sector: Int, sectorSize: Int) -> Int {
    precondition(sector >= 1)
    
    if sectorSize == 128 {
        return 16 + (sector - 1) * 128
    } else {
        // First 3 sectors are always 128 bytes
        if sector <= 3 {
            return 16 + (sector - 1) * 128
        } else {
            return 16 + 3 * 128 + (sector - 4) * 256
        }
    }
}
```

## Atari DOS 2.x File System

### Disk Layout

| Sectors | Contents |
|---------|----------|
| 1-3 | Boot sectors |
| 4-359 | Data sectors (single density) |
| 360 | VTOC (Volume Table of Contents) |
| 361-368 | Directory (8 sectors) |
| 369-720 | Data sectors (single density) |

### Boot Sectors (1-3)

| Offset | Size | Description |
|--------|------|-------------|
| 0 | 1 | Flags |
| 1 | 1 | Number of sectors to load |
| 2 | 2 | Load address |
| 4 | 2 | Init address |
| 6 | 122 | Boot code |

### VTOC (Sector 360)

| Offset | Size | Description |
|--------|------|-------------|
| 0 | 1 | DOS code (0 = DOS 2.0, 2 = DOS 2.5) |
| 1 | 2 | Total sectors (little-endian) |
| 3 | 2 | Free sectors (little-endian) |
| 10 | 90 | Bitmap of sectors 0-719 |
| 100 | 28 | Bitmap extension (enhanced density) |

### Sector Bitmap

Each bit represents one sector:
- Bit = 1: Sector is free
- Bit = 0: Sector is in use

Bit ordering within bytes is MSB first:
- Byte 10, bit 7 = Sector 0
- Byte 10, bit 6 = Sector 1
- ...

```swift
func isSectorFree(_ sector: Int, vtoc: [UInt8]) -> Bool {
    let byteIndex = 10 + (sector / 8)
    let bitIndex = 7 - (sector % 8)
    return (vtoc[byteIndex] & (1 << bitIndex)) != 0
}

func setSectorUsed(_ sector: Int, vtoc: inout [UInt8]) {
    let byteIndex = 10 + (sector / 8)
    let bitIndex = 7 - (sector % 8)
    vtoc[byteIndex] &= ~(1 << bitIndex)
}

func setSectorFree(_ sector: Int, vtoc: inout [UInt8]) {
    let byteIndex = 10 + (sector / 8)
    let bitIndex = 7 - (sector % 8)
    vtoc[byteIndex] |= (1 << bitIndex)
}
```

### Directory Sectors (361-368)

Each directory sector holds 8 file entries (16 bytes each).

### Directory Entry (16 bytes)

| Offset | Size | Description |
|--------|------|-------------|
| 0 | 1 | Flags |
| 1 | 2 | Sector count (little-endian) |
| 3 | 2 | Starting sector (little-endian) |
| 5 | 8 | Filename (padded with spaces) |
| 13 | 3 | Extension (padded with spaces) |

### Directory Flags

| Bit | Meaning when set |
|-----|------------------|
| 7 | Entry in use (deleted if clear) |
| 6 | File is open for write |
| 5 | DOS 2.5 extended |
| 4-2 | Reserved |
| 1 | Locked (read-only) |
| 0 | Entry never used |

Common flag values:
- $00: Never used
- $42: Normal file in use
- $43: Normal file in use, locked
- $80: Deleted file
- $03: Open for write

### File Data Sectors

Each data sector has a 3-byte link at the end:

**128-byte sectors:**
| Offset | Size | Description |
|--------|------|-------------|
| 0-124 | 125 | File data |
| 125 | 1 | File ID (high 6 bits) + sector count (low 2 bits) |
| 126 | 2 | Next sector (little-endian), or bytes in last sector |

**256-byte sectors:**
| Offset | Size | Description |
|--------|------|-------------|
| 0-252 | 253 | File data |
| 253 | 1 | File ID |
| 254 | 2 | Next sector / bytes in last sector |

### Last Sector Detection

In the link bytes:
- If next sector = 0, this is the last sector
- Byte 126 (or 254) contains count of valid data bytes in this sector

```swift
struct SectorLink {
    let fileID: UInt8
    let nextSector: UInt16
    let isLast: Bool
    let bytesInSector: Int
    
    init(bytes: [UInt8], sectorSize: Int) {
        let linkOffset = sectorSize - 3
        
        self.fileID = bytes[linkOffset] >> 2
        
        let nextLow = UInt16(bytes[linkOffset + 1])
        let nextHigh = UInt16(bytes[linkOffset] & 0x03) << 8
        let next = nextHigh | nextLow
        
        if next == 0 {
            self.isLast = true
            self.nextSector = 0
            self.bytesInSector = Int(bytes[linkOffset + 1])
        } else {
            self.isLast = false
            self.nextSector = next
            self.bytesInSector = sectorSize - 3
        }
    }
}
```

## File Operations

### Reading a File

```swift
func readFile(entry: DirectoryEntry, disk: ATRImage) -> Data {
    var data = Data()
    var sector = entry.startSector
    
    while sector != 0 {
        let sectorData = disk.readSector(sector)
        let link = SectorLink(bytes: sectorData, sectorSize: disk.sectorSize)
        
        let dataBytes = sectorData[0..<link.bytesInSector]
        data.append(contentsOf: dataBytes)
        
        sector = link.nextSector
    }
    
    return data
}
```

### Writing a File

```swift
func writeFile(name: String, ext: String, data: Data, disk: inout ATRImage) throws {
    // 1. Find free directory entry
    guard let entryIndex = disk.findFreeDirectoryEntry() else {
        throw DOSError.directoryFull
    }
    
    // 2. Calculate sectors needed
    let dataPerSector = disk.sectorSize - 3
    let sectorsNeeded = (data.count + dataPerSector - 1) / dataPerSector
    
    // 3. Allocate sectors
    let sectors = try disk.allocateSectors(count: sectorsNeeded)
    
    // 4. Write data to sectors
    var offset = 0
    for (index, sector) in sectors.enumerated() {
        var sectorData = [UInt8](repeating: 0, count: disk.sectorSize)
        
        let bytesThisSector = min(dataPerSector, data.count - offset)
        sectorData[0..<bytesThisSector] = data[offset..<(offset + bytesThisSector)]
        
        // Write link bytes
        let linkOffset = disk.sectorSize - 3
        if index < sectors.count - 1 {
            // Not last sector
            let nextSector = sectors[index + 1]
            sectorData[linkOffset] = UInt8((entryIndex << 2) | ((nextSector >> 8) & 0x03))
            sectorData[linkOffset + 1] = UInt8(nextSector & 0xFF)
            sectorData[linkOffset + 2] = 0
        } else {
            // Last sector
            sectorData[linkOffset] = UInt8(entryIndex << 2)
            sectorData[linkOffset + 1] = UInt8(bytesThisSector)
            sectorData[linkOffset + 2] = 0
        }
        
        disk.writeSector(sector, data: sectorData)
        offset += bytesThisSector
    }
    
    // 5. Create directory entry
    var entry = DirectoryEntry()
    entry.flags = 0x42
    entry.sectorCount = UInt16(sectorsNeeded)
    entry.startSector = sectors[0]
    entry.filename = name.padding(toLength: 8, withPad: " ")
    entry.extension = ext.padding(toLength: 3, withPad: " ")
    
    disk.writeDirectoryEntry(at: entryIndex, entry: entry)
    
    // 6. Update VTOC
    disk.updateVTOC()
}
```

### Deleting a File

```swift
func deleteFile(entry: DirectoryEntry, at index: Int, disk: inout ATRImage) {
    // 1. Free all sectors in chain
    var sector = entry.startSector
    while sector != 0 {
        let sectorData = disk.readSector(sector)
        let link = SectorLink(bytes: sectorData, sectorSize: disk.sectorSize)
        
        disk.freeSector(sector)
        sector = link.nextSector
    }
    
    // 2. Mark directory entry as deleted
    var modifiedEntry = entry
    modifiedEntry.flags = 0x80
    disk.writeDirectoryEntry(at: index, entry: modifiedEntry)
    
    // 3. Update VTOC
    disk.updateVTOC()
}
```

## ATRImage Class

```swift
class ATRImage {
    let url: URL
    private var data: Data
    let sectorSize: Int
    let sectorCount: Int
    var isModified: Bool = false
    
    init(url: URL) throws {
        self.url = url
        self.data = try Data(contentsOf: url)
        
        // Parse header
        guard data[0] == 0x96 && data[1] == 0x02 else {
            throw ATRError.invalidMagic
        }
        
        self.sectorSize = Int(data[4]) | (Int(data[5]) << 8)
        
        let paragraphs = Int(data[2]) | (Int(data[3]) << 8) | (Int(data[6]) << 16)
        let diskSize = paragraphs * 16
        
        // Calculate sector count accounting for first 3 sectors being 128 bytes
        if sectorSize == 256 {
            self.sectorCount = 3 + (diskSize - 3 * 128) / 256
        } else {
            self.sectorCount = diskSize / 128
        }
    }
    
    func readSector(_ sector: Int) -> [UInt8] {
        let offset = sectorOffset(sector)
        let size = (sector <= 3 && sectorSize == 256) ? 128 : sectorSize
        return Array(data[offset..<(offset + size)])
    }
    
    func writeSector(_ sector: Int, data sectorData: [UInt8]) {
        let offset = sectorOffset(sector)
        for (i, byte) in sectorData.enumerated() {
            data[offset + i] = byte
        }
        isModified = true
    }
    
    func save() throws {
        try data.write(to: url)
        isModified = false
    }
    
    private func sectorOffset(_ sector: Int) -> Int {
        // As described in ATR format section
    }
}
```

## Directory Parsing

```swift
struct DirectoryEntry {
    var flags: UInt8
    var sectorCount: UInt16
    var startSector: UInt16
    var filename: String  // 8 chars
    var ext: String       // 3 chars
    
    var isInUse: Bool { (flags & 0x80) != 0 && (flags & 0x80) != 0x80 }
    var isDeleted: Bool { flags == 0x80 }
    var isLocked: Bool { (flags & 0x02) != 0 }
    var neverUsed: Bool { (flags & 0x01) != 0 || flags == 0 }
    
    var fullName: String {
        let name = filename.trimmingCharacters(in: .whitespaces)
        let ext = self.ext.trimmingCharacters(in: .whitespaces)
        return ext.isEmpty ? name : "\(name).\(ext)"
    }
    
    init(bytes: [UInt8]) {
        flags = bytes[0]
        sectorCount = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        startSector = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)
        filename = String(bytes: bytes[5..<13], encoding: .ascii) ?? ""
        ext = String(bytes: bytes[13..<16], encoding: .ascii) ?? ""
    }
}

func readDirectory(disk: ATRImage) -> [DirectoryEntry] {
    var entries: [DirectoryEntry] = []
    
    for dirSector in 361...368 {
        let sectorData = disk.readSector(dirSector)
        
        for i in 0..<8 {
            let offset = i * 16
            let entryBytes = Array(sectorData[offset..<(offset + 16)])
            let entry = DirectoryEntry(bytes: entryBytes)
            
            if !entry.neverUsed {
                entries.append(entry)
            }
        }
    }
    
    return entries
}
```

## Creating New ATR Images

```swift
func createATR(at url: URL, type: DiskType) throws {
    var data = Data()
    
    // Header
    data.append(0x96)  // Magic
    data.append(0x02)
    
    let (paragraphs, sectorSize) = type.parameters
    data.append(UInt8(paragraphs & 0xFF))
    data.append(UInt8((paragraphs >> 8) & 0xFF))
    data.append(UInt8(sectorSize & 0xFF))
    data.append(UInt8((sectorSize >> 8) & 0xFF))
    data.append(UInt8((paragraphs >> 16) & 0xFF))
    
    // Padding to 16 bytes
    data.append(contentsOf: [UInt8](repeating: 0, count: 9))
    
    // Sectors
    let diskSize = paragraphs * 16
    data.append(contentsOf: [UInt8](repeating: 0, count: diskSize))
    
    try data.write(to: url)
}

enum DiskType {
    case singleDensity    // 90K
    case enhancedDensity  // 130K
    case doubleDensity    // 180K
    
    var parameters: (paragraphs: Int, sectorSize: Int) {
        switch self {
        case .singleDensity:   return (5760, 128)
        case .enhancedDensity: return (8320, 128)
        case .doubleDensity:   return (11520, 256)
        }
    }
}
```

## Format/Initialize Disk

```swift
func formatDisk(_ disk: inout ATRImage) {
    // Clear all sectors
    for sector in 1...disk.sectorCount {
        let emptyData = [UInt8](repeating: 0, count: disk.sectorSize)
        disk.writeSector(sector, data: emptyData)
    }
    
    // Initialize VTOC
    var vtoc = [UInt8](repeating: 0, count: 128)
    vtoc[0] = 2  // DOS 2.5
    vtoc[1] = UInt8(disk.sectorCount & 0xFF)
    vtoc[2] = UInt8((disk.sectorCount >> 8) & 0xFF)
    
    // Mark all data sectors as free
    let freeSectors = disk.sectorCount - 3 - 1 - 8  // Minus boot, VTOC, directory
    vtoc[3] = UInt8(freeSectors & 0xFF)
    vtoc[4] = UInt8((freeSectors >> 8) & 0xFF)
    
    // Initialize bitmap - mark boot, VTOC, and directory sectors as used
    for i in 10..<100 {
        vtoc[i] = 0xFF  // All free initially
    }
    
    // Mark boot sectors (1-3) as used
    vtoc[10] &= 0b00011111
    
    // Mark VTOC (360) as used
    vtoc[10 + 360/8] &= ~(1 << (7 - (360 % 8)))
    
    // Mark directory (361-368) as used
    for sector in 361...368 {
        vtoc[10 + sector/8] &= ~(1 << (7 - (sector % 8)))
    }
    
    disk.writeSector(360, data: vtoc)
    
    // Initialize directory sectors
    for sector in 361...368 {
        disk.writeSector(sector, data: [UInt8](repeating: 0, count: 128))
    }
}
```
