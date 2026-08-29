//
//  GeoMMDBBridge.h
//  GeoMMDB
//
//  Created by MagicianQuinn on 2026/2/5.
//

#ifndef GeoMMDBBridge_h
#define GeoMMDBBridge_h

#include <stdint.h>

typedef void *forge_mmdb_handle_t;

enum {
    FORGE_MMDB_STATUS_INVALID_ARGUMENT = -1,
    FORGE_MMDB_STATUS_OUT_OF_MEMORY = -2,
};

/* Returns an independently owned handle, or NULL with status set to a nonzero error code. */
forge_mmdb_handle_t forge_mmdb_open(const char *path, int *status);

/* NULL-safe. Closes only the supplied handle. */
void forge_mmdb_close(forge_mmdb_handle_t handle);

/* return packed ISO alpha2 in BE order, 0 if not found */
uint16_t forge_mmdb_country_ipv4(forge_mmdb_handle_t handle, uint32_t ipv4_be);

#endif /* GeoMMDBBridge_h */
