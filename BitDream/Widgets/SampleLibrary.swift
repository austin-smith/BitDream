import Foundation

/// Shared demo and preview data with verified torrent file metadata.
/// This small catalog also ships in the widget for its system gallery preview.
enum SampleLibrary {
    static let referenceDate = Date(timeIntervalSince1970: 1_741_089_600)
    static let serverID = "sample-demo-server"
    static let serverName = "Demo Server"
    static let downloadDirectory = "/Volumes/Downloads"
    static let sessionDownloaded = items.reduce(Int64(0)) { $0 + $1.completed }
    static let sessionUploaded = items.reduce(Int64(0)) { $0 + $1.uploaded }

    struct File: Sendable {
        let name: String
        let length: Int64
    }

    struct Item: Sendable {
        let id: Int
        let name: String
        let files: [File]
        let pieceSize: Int64
        var size: Int64 { files.reduce(0) { $0 + $1.length } }
        let completed: Int64
        let status: Int
        let labels: [String]
        let mimeType: String
        var uploaded: Int64 = 0
        var isStalled: Bool = false
        var downloadSpeed: Int64 = 0
        var uploadSpeed: Int64 = 0
        var peerCount: Int = 0
    }

    // File paths, lengths, and piece sizes match the original torrents. Transfer activity is simulated.
    static let items: [Item] = [
        Item(id: 1, name: "Big Buck Bunny", files: [
                 File(name: "Big Buck Bunny/Big Buck Bunny.en.srt", length: 140),
                 File(name: "Big Buck Bunny/Big Buck Bunny.mp4", length: 276_134_947),
                 File(name: "Big Buck Bunny/poster.jpg", length: 310_380)
             ], pieceSize: 262_144, completed: 276_445_467, status: 6, labels: ["movie"], mimeType: "video/mp4",
             uploaded: 234_900_000, uploadSpeed: 1_840_000, peerCount: 8),
        Item(id: 2, name: "Charlie_Chaplin_Mabels_Strange_Predicament.avi", files: [
                 File(name: "Charlie_Chaplin_Mabels_Strange_Predicament.avi", length: 170_835_968)
             ], pieceSize: 131_072, completed: 116_900_000, status: 4, labels: ["movie"], mimeType: "video/x-msvideo",
             uploaded: 64_600_000, downloadSpeed: 64_000, peerCount: 3),
        Item(id: 3, name: "Fedora-KDE-Live-x86_64-40", files: [
                 File(name: "Fedora-KDE-Live-x86_64-40/Fedora-KDE-Live-x86_64-40-1.14.iso", length: 2_645_645_312),
                 File(name: "Fedora-KDE-Live-x86_64-40/Fedora-Spins-40-1.14-x86_64-CHECKSUM", length: 2_582)
             ], pieceSize: 262_144, completed: 734_200_000, status: 4, labels: ["linux", "software"], mimeType: "application/x-iso9660-image",
             uploaded: 301_000_000, isStalled: true),
        Item(id: 4, name: "Mozart Keyboard Sheet Music - Public Domain", files: [
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Fantasies/Fantasy in d, K 397.pdf", length: 214_479),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Music for 2 Pianos/Adagio for 2 Pianos in c, K 426.pdf", length: 253_179),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Music for 2 Pianos/Fugue for 2 Pianos in c, K 426.pdf", length: 418_917),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Music for 2 Pianos/Sonata for 2 Pianos in D, K 448.pdf", length: 2_094_759),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 12.pdf", length: 436_322),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 13.pdf", length: 165_194),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 14.pdf", length: 88_803),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 15.pdf", length: 249_462),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 16.pdf", length: 206_890),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 17.pdf", length: 286_399),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 18.pdf", length: 222_095),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 19.pdf", length: 174_607),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 20.pdf", length: 542_140),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 23.pdf", length: 105_259),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 27.pdf", length: 165_713),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Cadenzas/Piano Concerto No 9.pdf", length: 323_762),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 1 in F, K 37.pdf", length: 2_374_621),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 10 in Eb, K 365 (2 Piano).pdf", length: 3_416_746),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 10 in Eb, K 365.pdf", length: 4_138_578),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 11 in F, K 413.pdf", length: 2_469_535),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 12 in A, K 414 (2 Piano).pdf", length: 2_217_290),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 12 in A, K 414.pdf", length: 2_495_582),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 13 in C, K 415.pdf", length: 3_492_464),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 14 in Eb, K 449.pdf", length: 2_815_941),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 15 in Bb, K 450 (2 Piano).pdf", length: 3_862_149),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 15 in Bb, K 450.pdf", length: 3_655_666),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 16 in D, K 451 (2 Piano).pdf", length: 1_919_265),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 16 in D, K 451.pdf", length: 4_519_215),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 17 in G, K 453.pdf", length: 3_491_174),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 18 in Bb, K 456.pdf", length: 4_119_945),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 19 in F, K 459.pdf", length: 3_877_888),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 2 in Bb, K 39.pdf", length: 2_223_935),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 20 in d, K 466 (2 Piano).pdf", length: 3_823_111),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 20 in d, K 466.pdf", length: 3_742_156),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 21 in C, K 467 (2 Piano).pdf", length: 3_625_625),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 21 in C, K 467.pdf", length: 3_659_355),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 22 in Eb, K 482 (2 Piano).pdf", length: 4_277_635),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 22 in Eb, K 482.pdf", length: 4_146_616),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 23 in A, K 488 (2 Piano).pdf", length: 2_706_485),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 23 in A, K 488.pdf", length: 4_301_596),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 24 in c, K 491 (2 Piano).pdf", length: 3_119_863),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 24 in c, K 491.pdf", length: 4_912_802),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 25 in C, K 503 (2 Piano).pdf", length: 3_346_981),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 25 in C, K 503.pdf", length: 4_911_638),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 26 in D, K 537 (2 Piano).pdf", length: 3_396_314),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 26 in D, K 537.pdf", length: 5_056_512),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 27 in Bb, K 595 (2 Piano).pdf", length: 3_501_481),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 27 in Bb, K 595.pdf", length: 4_178_147),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 3 in D, K 40.pdf", length: 2_316_319),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 4 in G, K 41.pdf", length: 1_965_181),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 5 in D, K 175.pdf", length: 2_812_624),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 6 in Bb, K 238.pdf", length: 2_593_220),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 7 in F, K 242 (2 Piano).pdf", length: 2_625_914),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 7 in F, K 242.pdf", length: 5_830_095),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 8 in C, K 246.pdf", length: 2_644_844),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 9 in Eb, K 271 (2 Piano).pdf", length: 4_399_004),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Piano Concerto No 9 in Eb, K 271.pdf", length: 4_168_952),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Piano with Orchestra/Rondo in D, K 382.pdf", length: 1_139_018),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 1 in C, K 279.pdf", length: 605_853),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 10 in C, K 330.pdf", length: 711_670),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 11 in A, K 331.pdf", length: 677_381),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 12 in F, K 332.pdf", length: 928_337),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 13 in Bb, K 333.pdf", length: 841_241),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 14 (and Fantasy) in c, K 475, 457.pdf", length: 1_245_964),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 15 in F, K 533.pdf", length: 1_135_991),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 16 in C, K 545.pdf", length: 442_434),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 17 in F, K 547a.pdf", length: 487_853),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 18 in Bb, K 570.pdf", length: 624_181),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 19 in D, K 576.pdf", length: 732_568),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 2 in F, K 280.pdf", length: 501_867),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 3 in Bb, K 281.pdf", length: 622_816),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 4 in Eb, K 282.pdf", length: 361_878),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 5 in G, K 283.pdf", length: 606_317),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 6 in D, K 284.pdf", length: 1_055_791),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 7 in C, K 309.pdf", length: 846_618),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 8 in a, K 310.pdf", length: 818_570),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Sonatas/Piano Sonata No 9 in D, K 311.pdf", length: 841_799),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/10 Variations, K 455.pdf", length: 662_672),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/10 Variations, K 460.pdf", length: 555_272),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/12 Variations on Ah! Vous-dirai-je maman, K 265.pdf", length: 436_472),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/12 Variations, K 179.pdf", length: 685_068),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/12 Variations, K 353.pdf", length: 439_644),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/12 Variations, K 354.pdf", length: 685_271),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/12 Variations, K 500.pdf", length: 396_015),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/6 Variations, K 137.pdf", length: 415_224),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/6 Variations, K 180.pdf", length: 268_685),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/6 Variations, K 398.pdf", length: 596_374),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/6 Variations, K 54.pdf", length: 277_110),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/7 Variations, K 25.pdf", length: 307_364),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/8 Variations, K 24.pdf", length: 315_018),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/8 Variations, K 352.pdf", length: 360_296),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/8 Variations, K 613.pdf", length: 792_912),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/9 Variations, K 264.pdf", length: 698_283),
                 File(name: "Mozart Keyboard Sheet Music - Public Domain/Variations/9 Variations, K 573.pdf", length: 614_579)
             ], pieceSize: 262_144, completed: 172_834_850, status: 6, labels: ["music"], mimeType: "application/pdf",
             uploaded: 214_300_000, uploadSpeed: 420_000, peerCount: 6),
        Item(id: 5, name: "The WIRED CD - Rip. Sample. Mash. Share", files: [
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/01 - Beastie Boys - Now Get Busy.mp3", length: 1_964_275),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/02 - David Byrne - My Fair Lady.mp3", length: 3_610_523),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/03 - Zap Mama - Wadidyusay.mp3", length: 2_759_377),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/04 - My Morning Jacket - One Big Holiday.mp3", length: 5_816_537),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/05 - Spoon - Revenge!.mp3", length: 2_106_421),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/06 - Gilberto Gil - Oslodum.mp3", length: 3_347_550),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/07 - Dan The Automator - Relaxation Spa Treatment.mp3", length: 2_107_577),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/08 - Thievery Corporation - Dc 3000.mp3", length: 3_108_130),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/09 - Le Tigre - Fake French.mp3", length: 3_051_528),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/10 - Paul Westerberg - Looking Up In Heaven.mp3", length: 3_270_259),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/11 - Chuck D - No Meaning No (feat. Fine Arts Militia).mp3", length: 3_263_528),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/12 - The Rapture - Sister Saviour (Blackstrobe Remix).mp3", length: 6_380_952),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/13 - Cornelius - Wataridori 2.mp3", length: 6_550_396),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/14 - DJ Danger Mouse - What U Sittin' On (feat. Jemini, Cee Lo And Tha Alkaholiks).mp3", length: 3_034_692),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/15 - DJ Dolores - Oslodum 2004.mp3", length: 3_854_611),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/16 - Matmos - Action At A Distance.mp3", length: 1_762_120),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/README.md", length: 4_071),
                 File(name: "The WIRED CD - Rip. Sample. Mash. Share/poster.jpg", length: 78_163)
             ], pieceSize: 65_536, completed: 56_070_710, status: 0, labels: ["music"], mimeType: "audio/mpeg", uploaded: 65_100_000),
        Item(id: 6, name: "enwiki-20250301-pages-articles-multistream.xml.bz2", files: [
                 File(name: "enwiki-20250301-pages-articles-multistream.xml.bz2", length: 24_749_684_048)
             ], pieceSize: 16_777_216, completed: 1_570_000_000, status: 4, labels: [], mimeType: "application/x-bzip2",
             uploaded: 879_200_000, downloadSpeed: 14_900_000, uploadSpeed: 730_000, peerCount: 17),
        Item(id: 7, name: "ubuntu-22.04-desktop-amd64.iso", files: [
                 File(name: "ubuntu-22.04-desktop-amd64.iso", length: 3_654_957_056)
             ], pieceSize: 262_144, completed: 175_700_000, status: 0, labels: ["linux", "software"], mimeType: "application/x-iso9660-image",
             uploaded: 48_800_000)
    ]

    // https://webtorrent.io/torrents/sintel.torrent
    static let addedItem = Item(id: 8, name: "Sintel", files: [
                 File(name: "Sintel/Sintel.de.srt", length: 1_652),
                 File(name: "Sintel/Sintel.en.srt", length: 1_514),
                 File(name: "Sintel/Sintel.es.srt", length: 1_554),
                 File(name: "Sintel/Sintel.fr.srt", length: 1_618),
                 File(name: "Sintel/Sintel.it.srt", length: 1_546),
                 File(name: "Sintel/Sintel.mp4", length: 129_241_752),
                 File(name: "Sintel/Sintel.nl.srt", length: 1_537),
                 File(name: "Sintel/Sintel.pl.srt", length: 1_536),
                 File(name: "Sintel/Sintel.pt.srt", length: 1_551),
                 File(name: "Sintel/Sintel.ru.srt", length: 2_016),
                 File(name: "Sintel/poster.jpg", length: 46_115)
             ], pieceSize: 131_072, completed: 0, status: 4, labels: ["movie"], mimeType: "video/mp4")

    static func widgetSnapshot(
        serverName: String = serverName,
        timestamp: Date = referenceDate,
        paused: Bool = false
    ) -> SessionOverviewSnapshot {
        SessionOverviewSnapshot(
            serverId: serverID, serverName: serverName,
            active: paused ? 0 : items.filter { $0.status != 0 }.count,
            paused: paused ? items.count : items.filter { $0.status == 0 }.count,
            total: items.count, totalCount: items.count,
            downloadingCount: paused ? 0 : items.filter { $0.status == 4 && !$0.isStalled }.count,
            completedCount: items.filter { (paused || $0.status == 0) && $0.completed == $0.size }.count,
            downloadSpeed: paused ? 0 : items.reduce(0) { $0 + $1.downloadSpeed },
            uploadSpeed: paused ? 0 : items.reduce(0) { $0 + $1.uploadSpeed },
            ratio: Double(sessionUploaded) / Double(sessionDownloaded), timestamp: timestamp
        )
    }
}
