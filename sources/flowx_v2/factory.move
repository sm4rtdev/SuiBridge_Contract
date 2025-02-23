module flowx_v2::factory {
    public struct Container has key {
        id: 0x2::object::UID,
        pairs: 0x2::bag::Bag,
        treasury: flowx_v2::treasury::Treasury,
    }

    public fun borrow_pair<T0, T1>(arg0: &Container) : &flowx_v2::pair::PairMetadata<T0, T1> {
        assert!(flowx_v2::swap_utils::is_ordered<T0, T1>(), 1);
        0x2::bag::borrow<0x1::string::String, flowx_v2::pair::PairMetadata<T0, T1>>(&arg0.pairs, flowx_v2::pair::get_lp_name<T0, T1>())
    }
}