import Testing
import libmaxminddb

// C-MMDB-BYTE-ORDER: exercise the linked vendor decoder, not a host-side conversion.
@Test func mmdb_decodes_network_order_float_and_double() {
    // MMDB control bytes followed by IEEE-754 big-endian representations of 1.5.
    let records: [[UInt8]] = [
        [0x04, 0x08, 0x3f, 0xc0, 0x00, 0x00],
        [0x68, 0x3f, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    ]
    for (index, record) in records.enumerated() {
        record.withUnsafeBufferPointer { bytes in
            var database = MMDB_s()
            database.data_section = bytes.baseAddress
            database.data_section_size = UInt32(bytes.count)
            withUnsafePointer(to: &database) { pointer in
                var entry = MMDB_entry_s(mmdb: pointer, offset: 0)
                var value = MMDB_entry_data_s()
                let path: [UnsafePointer<CChar>?] = [nil]
                let status = path.withUnsafeBufferPointer {
                    MMDB_aget_value(&entry, &value, $0.baseAddress)
                }
                #expect(status == MMDB_SUCCESS)
                #expect(value.has_data)
                if index == 0 {
                    #expect(value.type == MMDB_DATA_TYPE_FLOAT)
                    #expect(value.float_value == 1.5)
                } else {
                    #expect(value.type == MMDB_DATA_TYPE_DOUBLE)
                    #expect(value.double_value == 1.5)
                }
            }
        }
    }
}
