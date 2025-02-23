module bridge::checkdot_bridge_v1 {
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::hash;
    use sui::bcs;

    use std::string::{Self, String};
    use std::u256;

    use cdtToken::cdt::CDT;

    const ERR_NOT_INITIALIZED: u64 = 100;
    const ERR_NOT_OWNER: u64 = 200;
    const ERR_NOT_OWNER_OR_PROGRAM: u64 = 201;
    const ERR_NOT_ACTIVED: u64 = 300;
    const ERR_ZERO_DIVISION: u64 = 400;
    const ERR_INSUFFICIENT_QUANTITY: u64 = 500;
    const ERR_PAYMENT_ABORTED: u64 = 501;
    const ERR_NOT_EXISTS: u64 = 502;
    const ERR_OUT_OF_BOUNDS: u64 = 503;
    const ERR_INSUFFICIENT_BALANCE: u64 = 504;
    const ERR_MINIMUM_LOCEKD_PERIOD: u64 = 505;
    const ERR_MAXIMUM_LOCKED_PERIOD: u64 = 506;

    public struct Transfer has copy, store {
        hash: vector<u8>,
        from: address,
        quantity: u64,
        fromChain: String,
        toChain: String,
        fees_in_cdt: u64,
        fees_in_sui: u64,
        block_timestamp: u64,
        block_number: u64,
        data: String
    }

    public struct Bridge has key {
        id: UID,
        cdt_coin: Balance<CDT>,
        chain: String,
        fees_in_dollar: u64,
        fees_in_cdt_percentage: u64,
        minimum_transfer_quantity: u64,
        bridge_fees_in_cdt: u64,
        lock_ask_duration: u64,
        unlock_ask_duration: u64,
        unlock_ask_time: u64,
        transfers: vector<Transfer>,
        transfers_indexs: Table<vector<u8>, u64>,
        transfers_hashs: Table<vector<u8>, vector<u8>>,
        owner: address,
        program: address,
        paused: bool,
        sui_coin: Balance<SUI>
    }

    fun init(ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        let bridge = Bridge {
            id: object::new(ctx),
            cdt_coin: balance::zero<CDT>(),
            chain: string::utf8(b"sui"),
            fees_in_dollar: 0,
            fees_in_cdt_percentage: 0,
            minimum_transfer_quantity: 100000000,
            bridge_fees_in_cdt: 0,
            lock_ask_duration: (((86400 * 1000) * 2) * 1000), // 2 days
            unlock_ask_duration: (((86400 * 1000) * 15) * 1000), // 15 days
            unlock_ask_time: 0,
            transfers: vector::empty(),
            transfers_indexs: table::new(ctx),
            transfers_hashs: table::new(ctx),
            owner: addr,
            program: addr,
            paused: false,
            sui_coin: balance::zero<SUI>()
        };

        transfer::share_object(bridge);
    }

    public fun assert_is_owner(bridge: &Bridge, addr: address) {
        assert!(addr == bridge.owner, ERR_NOT_OWNER);
    }

    public fun assert_is_owner_or_program(bridge: &Bridge, addr: address) {
        assert!(addr == bridge.owner || addr == bridge.program, ERR_NOT_OWNER_OR_PROGRAM);
    }

    public fun assert_is_actived(bridge: &Bridge) {
        assert!(!bridge.paused, ERR_NOT_ACTIVED);
    }

    public entry fun set_fees_in_dollar(bridge: &mut Bridge, cost: u64, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        bridge.fees_in_dollar = cost;
    }

    public entry fun set_fees_in_cdt_percentage(bridge: &mut Bridge, fees: u64, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        bridge.fees_in_cdt_percentage = fees;
    }

    public entry fun set_paused(bridge: &mut Bridge, stat: bool, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        bridge.paused = stat;
    }

    public entry fun set_minimum_transfer_quantity(bridge: &mut Bridge, quantity: u64, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        bridge.minimum_transfer_quantity = quantity;
    }

    public entry fun set_owner(bridge: &mut Bridge, owner: address, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        bridge.owner = owner;
    }

    public entry fun set_program(bridge: &mut Bridge, program: address, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        bridge.program = program;
    }

    public entry fun ask_withdraw(bridge: &mut Bridge, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        bridge.unlock_ask_time = tx_context::epoch_timestamp_ms(ctx);
    }

    public entry fun init_transfer<USD>(bridge: &mut Bridge, container: &mut flowx_v2::factory::Container, fee: Coin<SUI>, quantity: Coin<CDT>, to_chain: String, data: String, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_actived(bridge);

        assert!(quantity.value() >= bridge.minimum_transfer_quantity, ERR_INSUFFICIENT_QUANTITY);

        let transfer_sui_fees = fee.value();
        let fees_sui = fees_in_sui<USD>(container, bridge);
        assert!(transfer_sui_fees >= fees_sui, ERR_PAYMENT_ABORTED);

        let quantity_value = quantity.value();

        coin::put(&mut bridge.sui_coin, fee);

        coin::put<CDT>(&mut bridge.cdt_coin, quantity);

        let transfer_fees_in_cdt = fees_in_cdt_by_quantity(bridge, quantity_value);

        let transfer_quantity = quantity_value - transfer_fees_in_cdt;

        *(&mut bridge.bridge_fees_in_cdt) = bridge.bridge_fees_in_cdt + transfer_fees_in_cdt;
        let index = vector::length<Transfer>(&bridge.transfers);
        let transfer_hash = get_hash(addr, ctx);

        vector::push_back<Transfer>(&mut bridge.transfers, Transfer {
            hash: transfer_hash,
            from: addr,
            quantity: transfer_quantity,
            fromChain: bridge.chain,
            toChain: to_chain,
            fees_in_cdt: transfer_fees_in_cdt,
            fees_in_sui: transfer_sui_fees,
            block_timestamp: tx_context::epoch_timestamp_ms(ctx),
            block_number: tx_context::epoch(ctx),
            data: data
        });

        table::add(&mut bridge.transfers_hashs, transfer_hash, transfer_hash);
        table::add(&mut bridge.transfers_indexs, transfer_hash, index);
    }
    
    public entry fun add_transfers_from(bridge: &mut Bridge, _memory: String/* fromChain */, transfers_address: address, amount: u64, _transfers_hash: vector<u8>, ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);
        assert_is_owner_or_program(bridge, admin);

        assert!(bridge.cdt_coin.value() >= amount, ERR_INSUFFICIENT_BALANCE);
        
        let coin = coin::take<CDT>(&mut bridge.cdt_coin, amount, ctx);
        transfer::public_transfer(coin, ctx.sender());
    }

    public entry fun collect_cdt_fees(bridge: &mut Bridge, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        assert!(bridge.cdt_coin.value() >= bridge.bridge_fees_in_cdt, ERR_INSUFFICIENT_BALANCE);

        let coin = coin::take<CDT>(&mut bridge.cdt_coin, bridge.bridge_fees_in_cdt, ctx);
        transfer::public_transfer(coin, ctx.sender());

        bridge.bridge_fees_in_cdt = 0;
    }

    public entry fun deposit(bridge: &mut Bridge, coin: Coin<CDT>, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        coin::put(&mut bridge.cdt_coin, coin);
    }

    public entry fun withdraw(bridge: &mut Bridge, quantity: u64, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        let cur_timestamp = tx_context::epoch_timestamp_ms(ctx);
        assert!(bridge.unlock_ask_time < cur_timestamp - bridge.lock_ask_duration, ERR_MINIMUM_LOCEKD_PERIOD);
        assert!(bridge.unlock_ask_time > cur_timestamp - bridge.unlock_ask_duration, ERR_MAXIMUM_LOCKED_PERIOD);

        assert!(bridge.cdt_coin.value() >= quantity, ERR_INSUFFICIENT_BALANCE);

        let coin = coin::take<CDT>(&mut bridge.cdt_coin, quantity, ctx);
        transfer::public_transfer(coin, ctx.sender());
    }

    public entry fun deposit_sui(bridge: &mut Bridge, coin: Coin<SUI>, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        coin::put(&mut bridge.sui_coin, coin);
    }

    public entry fun withdraw_sui(bridge: &mut Bridge, quantity: u64, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        assert_is_owner(bridge, addr);

        assert!(bridge.sui_coin.value() >= quantity, ERR_INSUFFICIENT_BALANCE);

        let coin = coin::take<SUI>(&mut bridge.sui_coin, quantity, ctx);
        transfer::public_transfer(coin, ctx.sender());
    }

    public fun balance(bridge: &Bridge): u64 {
        bridge.sui_coin.value()
    }

    public fun balance_CDT(bridge: &Bridge): u64 {
        balance::value<CDT>(&bridge.cdt_coin)
    }

    public fun transfer_exists(bridge: &Bridge, transfer_hash: vector<u8>): bool {
        table::contains(&bridge.transfers_hashs, transfer_hash)
    }

    public fun get_transfer(bridge: &Bridge, transfer_hash: vector<u8>): Transfer {
        assert!(table::contains(&bridge.transfers_indexs, transfer_hash), ERR_NOT_EXISTS);

        let index: &u64 = table::borrow(&bridge.transfers_indexs, transfer_hash);

        let transfer: &Transfer = vector::borrow(&bridge.transfers, *index);

        return *transfer
    }

    public fun get_transfers(bridge: &Bridge, page: u64, page_size: u64): vector<Transfer> {
        let len = vector::length(&bridge.transfers);
        assert!(len >= page * page_size, ERR_OUT_OF_BOUNDS);
        let start_id = len - page * page_size;
        let end_id = if(start_id >= page_size) {
            start_id - page_size
        } else {
            0
        };
        let mut current_id = start_id;
        assert!(current_id <= len, ERR_OUT_OF_BOUNDS);
        let mut transfers: vector<Transfer> = vector::empty<Transfer>();

        while(current_id > end_id) {
            let transfer = vector::borrow(&bridge.transfers, current_id - 1);
            vector::push_back(&mut transfers, *transfer);
            current_id = current_id - 1;
        };

        transfers
    }

    public fun get_last_transfers(bridge: &Bridge, size: u64): vector<Transfer> {
        let len = vector::length(&bridge.transfers);
        let mut start = if(len > size) {
            len - size
        } else {
            0
        };
        let mut transfers: vector<Transfer> = vector::empty<Transfer>();

        while(start < len) {
            let transfer = vector::borrow(&bridge.transfers, start);
            vector::push_back(&mut transfers, *transfer);
            start = start + 1;
        };

        transfers
    }

    public fun get_transfer_length(bridge: &Bridge): u64 {
        vector::length(&bridge.transfers)
    }
    
    public fun get_fees_in_sui<USD>(container: &flowx_v2::factory::Container, bridge: &Bridge): u64 {
        fees_in_sui<USD>(container, bridge)
    }

    public fun get_fees_in_dollar(bridge: &Bridge): u64 {
        bridge.fees_in_dollar
    }

    public fun get_fees_in_cdt_by_quantity(bridge: &Bridge, quantity: u64): u64 {
        quantity * bridge.fees_in_cdt_percentage / 100
    }

    public fun is_paused(bridge: &Bridge): bool {
        bridge.paused
    }


    fun fees_in_sui<USD>(container: &flowx_v2::factory::Container, bridge: &Bridge): u64 {

        let fees_in_dollar = bridge.fees_in_dollar;

        let pair = flowx_v2::factory::borrow_pair<SUI, USD>(container);
        let (x_res, y_res) = flowx_v2::pair::get_reserves<SUI, USD>(pair);

        assert!(y_res > 0, ERR_ZERO_DIVISION);

        let fees = (fees_in_dollar as u256) * (u256::pow(10, 6)) / (u256::pow(10, 9)) * (x_res as u256) / (y_res as u256);

        (fees as u64)
    }

    fun fees_in_cdt_by_quantity(bridge: &Bridge, quantity: u64): u64 {

        quantity * bridge.fees_in_cdt_percentage / 100
    }

    fun get_hash(addr: address, ctx: &TxContext): vector<u8> {
        let t = tx_context::epoch_timestamp_ms(ctx);
        let mut t_vec:vector<u8> = bcs::to_bytes<u64>(&t);
        let addr_vec:vector<u8> = bcs::to_bytes<address>(&addr);

        vector::append(&mut t_vec, addr_vec);

        return hash::keccak256(&t_vec)
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx)
    }
}
