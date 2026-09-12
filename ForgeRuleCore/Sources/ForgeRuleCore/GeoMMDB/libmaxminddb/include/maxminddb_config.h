#ifndef MAXMINDDB_CONFIG_H
#define MAXMINDDB_CONFIG_H

/* SwiftPM does not run the upstream configure step. Detect the target's byte
 * order (not the build host's), including when cross-compiling for iOS. */
#ifndef MMDB_LITTLE_ENDIAN
#if defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) && defined(__ORDER_BIG_ENDIAN__)
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define MMDB_LITTLE_ENDIAN 1
#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define MMDB_LITTLE_ENDIAN 0
#else
#error "Unsupported target byte order"
#endif
#elif defined(_WIN32)
#define MMDB_LITTLE_ENDIAN 1
#else
#error "Cannot determine target byte order for libmaxminddb"
#endif
#endif

#ifndef MMDB_UINT128_USING_MODE
/* Define as 1 if we use unsigned int __attribute__ ((__mode__(TI))) for uint128 values */
#define MMDB_UINT128_USING_MODE 0
#endif

#ifndef MMDB_UINT128_IS_BYTE_ARRAY
/* Define as 1 if we don't have an unsigned __int128 type */
#undef MMDB_UINT128_IS_BYTE_ARRAY
#endif

#endif                          /* MAXMINDDB_CONFIG_H */
