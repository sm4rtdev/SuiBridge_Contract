module bridge::checkdot_bridge_v1_tests {
    use bridge::checkdot_bridge_v1::{Self, Bridge};
    use sui::test_scenario::{Self, next_tx, ctx};
    use sui::test_utils;
    use sui::coin;
    use sui::sui::SUI;

    use std::debug;

    #[test]
    fun set_fees_in_dollar() {
        let addr = @0xA;
        let mut scenario = test_scenario::begin(addr);

        {
            checkdot_bridge_v1::test_init(ctx(&mut scenario));
        };

        next_tx(&mut scenario, addr);
        {
            let mut bridge = test_scenario::take_shared<Bridge>(&scenario);
            let sui = coin::mint_for_testing<SUI>(1 * 100, ctx(&mut scenario));
            checkdot_bridge_v1::deposit_sui(&mut bridge, sui, ctx(&mut scenario));
            let mut balance = checkdot_bridge_v1::balance(&bridge);
            test_utils::assert_eq(balance, 100);

            checkdot_bridge_v1::withdraw_sui(&mut bridge, 10, ctx(&mut scenario));
            balance = checkdot_bridge_v1::balance(&bridge);
            test_utils::assert_eq(balance, 90);
            // fees_in_dollar = checkdot_bridge_v1::get_fees_in_dollar(&bridge);
            // test_utils::assert_eq(fees_in_dollar, 100);

            test_scenario::return_shared(bridge);
        };

        test_scenario::end(scenario);
    }
}