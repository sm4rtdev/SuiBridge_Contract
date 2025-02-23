module flowx_v2::pair {
    public struct LP<phantom T0, phantom T1> has drop {
        dummy_field: bool,
    }
    
    public struct PairMetadata<phantom T0, phantom T1> has store, key {
        id: 0x2::object::UID,
        reserve_x: 0x2::coin::Coin<T0>,
        reserve_y: 0x2::coin::Coin<T1>,
        k_last: u128,
        lp_supply: 0x2::balance::Supply<LP<T0, T1>>,
        fee_rate: u64,
    }

    public fun get_reserves<T0, T1>(arg0: &PairMetadata<T0, T1>) : (u64, u64) {
        (0x2::coin::value<T0>(&arg0.reserve_x), 0x2::coin::value<T1>(&arg0.reserve_y))
    }
    
    public fun get_lp_name<T0, T1>() : 0x1::string::String {
        let mut v0 = 0x1::string::utf8(b"LP-");
        0x1::string::append(&mut v0, flowx_v2::type_helper::get_type_name<T0>());
        0x1::string::append_utf8(&mut v0, b"-");
        0x1::string::append(&mut v0, flowx_v2::type_helper::get_type_name<T1>());
        v0
    }
}