//
//  GeoMMDBBridge.c
//  GeoMMDB
//
//  Created by MagicianQuinn on 2026/2/5.
//

#include "GeoMMDBBridge.h"
#include <maxminddb.h>
#include <arpa/inet.h>
#include <stdlib.h>

typedef struct {
    MMDB_s database;
} forge_mmdb_handle;

forge_mmdb_handle_t forge_mmdb_open(const char *path, int *status)
{
    if (status == NULL)
        return NULL;

    *status = MMDB_SUCCESS;
    if (path == NULL) {
        *status = FORGE_MMDB_STATUS_INVALID_ARGUMENT;
        return NULL;
    }

    forge_mmdb_handle *handle = calloc(1, sizeof(*handle));
    if (handle == NULL) {
        *status = FORGE_MMDB_STATUS_OUT_OF_MEMORY;
        return NULL;
    }

    *status = MMDB_open(path, MMDB_MODE_MMAP, &handle->database);
    if (*status != MMDB_SUCCESS) {
        free(handle);
        return NULL;
    }

    return handle;
}

void forge_mmdb_close(forge_mmdb_handle_t opaque_handle)
{
    forge_mmdb_handle *handle = opaque_handle;
    if (handle == NULL)
        return;

    MMDB_close(&handle->database);
    free(handle);
}

uint16_t forge_mmdb_country_ipv4(forge_mmdb_handle_t opaque_handle, uint32_t ipv4_be)
{
    forge_mmdb_handle *handle = opaque_handle;
    if (handle == NULL)
        return 0;

    struct sockaddr_in sa = {0};
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(ipv4_be);

    int err;
    MMDB_lookup_result_s result =
        MMDB_lookup_sockaddr(&handle->database, (struct sockaddr *)&sa, &err);

    uint16_t country_code = 0;
    
    if (err == MMDB_SUCCESS && result.found_entry) {
        MMDB_entry_data_s data = {0};
        int value_status = MMDB_get_value(&result.entry, &data, "country", "iso_code", NULL);
        if (value_status == MMDB_SUCCESS &&
            data.has_data && data.type == MMDB_DATA_TYPE_UTF8_STRING && data.data_size == 2) {
            const unsigned char *s = (const unsigned char *)data.utf8_string;
            country_code = ((uint16_t)s[0] << 8) | s[1];
        }
    }

    return country_code;
}
