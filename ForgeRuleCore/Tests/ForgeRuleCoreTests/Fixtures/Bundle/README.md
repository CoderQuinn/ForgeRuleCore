# Bundle contract fixtures

- `geosite-valid.json` is a small on-disk example of the JSON schema emitted by ForgeRules (`geosites` → `country_code` → `domains`). It exercises full, suffix, and keyword entries through the bundle assembly path.
- `geosite-malformed.json` is valid JSON but omits the required `domains` field.
- `geoip-malformed.mmdb` is deliberately not an MMDB database.

The valid MMDB side of bundle tests reuses the pinned official MaxMind fixture and license recorded one directory above.
