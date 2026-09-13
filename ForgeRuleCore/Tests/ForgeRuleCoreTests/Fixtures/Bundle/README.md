# Bundle contract fixtures

- `geosite-valid.json` is the byte-identical ForgeRules golden fixture from
  `testdata/golden/geosite.json` at ForgeRules merge
  `88f616066bec5d516076c166ae41ff44749d690b`. It exercises full, suffix, and
  keyword entries through the bundle assembly path. Its SHA-256 is
  `0f224dfb0a0ef20db3033aeb588523c733518d6c82d06f8f393bc967e1d212e3`.
  The fixture contains only IANA-reserved `.test` names and synthetic data.
- `geosite-malformed.json` is valid JSON but omits the required `domains` field.
- `geoip-malformed.mmdb` is deliberately not an MMDB database.

The valid MMDB side of bundle tests reuses the pinned official MaxMind fixture and license recorded one directory above.
