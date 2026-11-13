// ReferenceToneGoldens.swift — SHA-256 of one loop of every reference-tone fixture variant, catalog
// version 1 (AUD-016-T09; AUD-016-R10; contracts/fixture-catalog.md, "Golden SHA-256").
// Input: the little-endian bytes of the interleaved Float32 samples of frames 0 ..< loopFrames.
// These values may change only together with ReferenceToneCatalog.version.

enum ReferenceToneGoldens {
    static func key(_ id: String, rate: Int, channels: Int) -> String { "\(id)@\(rate)/\(channels)" }

    static let sha256: [String: String] = [
        "sine-1k@44100/1": "ec6f232d35067a7623c03115c22d994723405477b3d4c152e891dd4aa7b3bdf2",
        "sine-1k@44100/2": "a12d3d8c78a50595b99818f931879a0cc969e9cb9142a3aba4cbeec41453502e",
        "sine-1k@48000/1": "e3ae450e8d1e94bb6efcfc4af0d89cc00e9a4cb3fc76d9a42b3ec55ce83ea8fd",
        "sine-1k@48000/2": "b130d3f298b73f17b2ca56598f2a37ca0012789f42b527ddc187156ef7f4cc57",
        "sine-100@44100/1": "7a783f028fd6bd701bfb4f53ab21c38e4dbc62adadad58089e4e9042f2dde7e5",
        "sine-100@44100/2": "c14d421beba274e2717a34eeb2b1c7ceb4ca6ac2c3e5eff280c9e690512907ef",
        "sine-100@48000/1": "8713580aa23eafdf1fe3fbfdcb4d6e3350107290919cbbd3873ac209ef6e4987",
        "sine-100@48000/2": "5244ab55cf6321c5750f5c3bb602a1477bc21f79d980447638d4be72961b0517",
        "sine-1500@44100/1": "03647fcd2c1c361a401f5e415fbb0956621753ada10582b5cec243f2ccf1af2f",
        "sine-1500@44100/2": "f453584fb20ccf8720ad99e8658876828ee5f9cb6e77439bb861b54032913427",
        "sine-1500@48000/1": "7e21fbe4ee2418bfac37125e3d61d38069ba8a03ec6c9c510947628dfa067e13",
        "sine-1500@48000/2": "7434d3ca5f235855e9d158f130a74b4a920e560ba36483b6b9e7d1e62336a6b9",
        "sine-split@44100/2": "7003ea65fa73cd1d46ba331020eeebe69f3d8444b00dc1b96f49b7b957f8fe90",
        "sine-split@48000/2": "41aa73526e6a53076d7a2840fa7154c75b4a04fd71a22ddee840d59bd6c47f2a",
        "sweep-log@44100/1": "42e8113fed498703fb14bed525da016b6a67729cf0848d5a1363e3be0a56be45",
        "sweep-log@44100/2": "40f7e528dc3b0e0a65b956e249c1fbf9ec91f3a410a5a4d839532d1ff1ed43dc",
        "sweep-log@48000/1": "e0399c2b5fda8611f63c2a94cca390456a0b76fabc022ca0054545bc45770dcd",
        "sweep-log@48000/2": "75f981861d9980861f927800d357d92a5007e54ff006e7737e0013c2baa09685",
        "sweep-linear@44100/1": "032af5ce5fa086383cba7a1ee273690d22fb5a79a79ae3e84cfa0a79f9260c2a",
        "sweep-linear@44100/2": "aa047413f72bccfa4755f0f276a8f517f0705a87862bb9b8f8614f43edcd75c3",
        "sweep-linear@48000/1": "338762b662c3a7c862ce8fd2fdbf15a623f7e461f549a7864ccbe6b355065daa",
        "sweep-linear@48000/2": "5c3b89e84ef376dfdcb35510d4c03101a9434aaca5e41e6f7407cc3f7c05c144",
        "pulse-120@44100/1": "693a5c53843e7035485c7563ef46663166f309500eea95fb6194e3b79fa5882c",
        "pulse-120@44100/2": "dc1c28718756e5ca40d197063cb93627b1fb3571f5fd89035f2225af8bc63d80",
        "pulse-120@48000/1": "246506d85d7ff031affadeae816b12567eab39448d549b60a30dc49c0591eb4e",
        "pulse-120@48000/2": "83e409263246d3b3a7d282b796224e9e96f733f13070e856ca969b384db99329",
        "pulse-120-accent@44100/1": "37e275e3bb90bd9e358fa323f5f74308dea7fb3c0d38300245488bfc583c6f2c",
        "pulse-120-accent@44100/2": "7f0cc535ecdc42658d0aaea6651f35bbf667642e37f631c80a050f5c687d6716",
        "pulse-120-accent@48000/1": "bc8147321bb2ba4975b18a4989b4376d82824cb4829bb801d78316d894b69c9c",
        "pulse-120-accent@48000/2": "9b3e351e473688e31f99bf0d554b5f4f2fcc61c102f277c0e53d07af47909666",
        "pulse-132@44100/1": "142dac944b046fd70dea397c87462b3179fcea106aebd2a9c5788dd0db9aae28",
        "pulse-132@44100/2": "f4e1435570a782804d6c89f59ce7ef46523b01397db788fc4c28a6015e80d635",
        "pulse-132@48000/1": "774ddfbd8f57e8c0e275ff8842998b77e07fa0c7abd91aa305ff177e54d4b01f",
        "pulse-132@48000/2": "6c3e269ac1e0aac92c89204af643d38d611bb5ee095b595f3324b7c53660179d",
        "silence@44100/1": "2b1f63df409bdeac3c7d15e9a3d30a8ed77d35d1a8397848bb14cadac59affdf",
        "silence@44100/2": "2a30c57a4d9493dee87b67431a6df0c02af11468bf0ef3e0f952dff48c24df53",
        "silence@48000/1": "124617c1f65e92d3bc895fbd869e4bb16a30754b198f59e6e973949b9aaa1b01",
        "silence@48000/2": "81beb57ba94e8afbf61c796a8a2438ff11c5e05c6fc156e7425b391c81369516",
    ]
}
