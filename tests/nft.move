#[test_only]
module nft_protocol::fake_witness {
    // TODO: To move to utils
    struct FakeWitness has drop {}

    public fun new(): FakeWitness {
        FakeWitness {}
    }
}

#[test_only]
module nft_protocol::test_nft {
    use nft_protocol::fake_witness::{Self, FakeWitness};
    use nft_protocol::nft::{Self, Nft};
    use nft_protocol::utils;

    use sui::object::{Self, UID};
    use sui::test_scenario::{Self, ctx};
    use sui::transfer::transfer;

    struct Witness has drop {}

    struct Foo has drop {}

    struct DomainA has key, store {
        id: UID
    }

    const OWNER: address = @0xA1C05;
    const FAKE_OWNER: address = @0xA1C11;

    #[test]
    fun creates_nft() {
        let scenario = test_scenario::begin(OWNER);
        let ctx = ctx(&mut scenario);

        let nft = nft::new<Foo, Witness>(&Witness {}, OWNER, ctx);

        assert!(nft::logical_owner(&nft) == OWNER, 0);

        transfer(nft, OWNER);
        test_scenario::end(scenario);
    }

    #[test]
    fun adds_domain() {
        let scenario = test_scenario::begin(OWNER);
        let ctx = ctx(&mut scenario);

        let nft = nft::new(&Witness {}, OWNER, ctx);

        nft::add_domain(&mut nft, DomainA { id: object::new(ctx) }, ctx);

        // If domain does not exist this function call will fail
        nft::borrow_domain<Foo, DomainA>(&nft);

        transfer(nft, OWNER);

        test_scenario::end(scenario);
    }

    #[test]
    fun remove_domain() {
        use sui::transfer;
        let scenario = test_scenario::begin(OWNER);
        let scenarios = &mut scenario;
        let ctx = ctx(scenarios);

        let nft = nft::new(&Witness {}, OWNER, ctx);

        nft::add_domain(&mut nft, DomainA {}, ctx);

        // If domain does not exist this function call will fail
        nft::assert_domain<Foo, DomainA>(&nft);

        // transfer(nft, OWNER);//正常调用时使用，调用流程为将nft传给OWNER，然后使用OWNER进行下一步交易，接着将DomainA从nft移除。用来验证函数中assert_same_module_as_witness<W, D>();D和W写反的问题。正确的应该是assert_same_module_as_witness<D, W>()；
        transfer::share_object<Nft<Foo>>(nft);//正常调用时注释掉，使用情况：当nft为share状态时，无论使用OWNER还是FAKE_OWNER去进行下一步交易，都能将DomainA从nft移除。前提是是remove能正常调用，将assert_same_module_as_witness<W, D>()；D和W改变位置；

        test_scenario::next_tx(scenarios, FAKE_OWNER);//正常调用时改为OWNER，使用OWNER进行下一步交易；当nft为share状态时，可分别使用OWNER和FAKE_OWNER验证能否正常将DomainA从nft移除。


        // let nft = test_scenario::take_from_sender<Nft<Foo>>(scenarios);//正常调用时使用
        let nft = test_scenario::take_shared<Nft<Foo>>(scenarios);//正常调用时注释掉
        let DomainA {} = nft::remove_domain<Foo, Witness, DomainA>(Witness {}, &mut nft);
        nft::assert_no_domain<Foo, DomainA>(&nft);
        // test_scenario::return_to_sender<Nft<Foo>>(scenarios, nft);//正常调用时使用
        test_scenario::return_shared<Nft<Foo>>(nft);//正常调用时注释掉

        test_scenario::end(scenario);
    }

    #[test]
    fun borrows_domain_mut() {
        let scenario = test_scenario::begin(OWNER);
        let ctx = ctx(&mut scenario);

        let nft = nft::new(&Witness {}, OWNER, ctx);

        nft::add_domain(&mut nft, DomainA { id: object::new(ctx) }, ctx);

        nft::borrow_domain_mut<Foo, DomainA, Witness>(
            Witness {}, &mut nft
        );

        transfer(nft, OWNER);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13370001, location = nft_protocol::nft)]
    fun fails_adding_duplicate_domain() {
        let scenario = test_scenario::begin(OWNER);
        let ctx = ctx(&mut scenario);

        let nft = nft::new<Foo, Witness>(&Witness {}, OWNER, ctx);

        nft::add_domain(&mut nft, DomainA { id: object::new(ctx) }, ctx);

        // This second call will fail
        nft::add_domain(&mut nft, DomainA { id: object::new(ctx) }, ctx);

        transfer(nft, OWNER);

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13370002, location = nft_protocol::nft)]
    fun fails_adding_domain_if_not_owner() {
        let scenario = test_scenario::begin(OWNER);

        let nft_id = {
            let ctx = ctx(&mut scenario);

            let nft = nft::new<Foo, Witness>(&Witness {}, OWNER, ctx);

            let nft_id = object::id(&nft);

            transfer(nft, OWNER);
            nft_id
        };

        test_scenario::next_tx(&mut scenario, FAKE_OWNER);

        let nft = test_scenario::take_from_address_by_id<Nft<Foo>>(
            &scenario, OWNER, nft_id,
        );

        let ctx = ctx(&mut scenario);
        nft::add_domain(&mut nft, DomainA { id: object::new(ctx) }, ctx);

        transfer(nft, OWNER);

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13370600, location = nft_protocol::utils)]
    fun fails_borrowing_domain_mut_if_wrong_witness() {
        let scenario = test_scenario::begin(OWNER);
        let ctx = ctx(&mut scenario);


        let nft = nft::new(&Witness {}, OWNER, ctx);

        nft::add_domain(&mut nft, DomainA { id: object::new(ctx) }, ctx);

        nft::borrow_domain<Foo, DomainA>(&nft);


        nft::borrow_domain_mut<Foo, DomainA, FakeWitness>(
            fake_witness::new(), &mut nft
        );

        transfer(nft, OWNER);
        test_scenario::end(scenario);
    }

    #[test]
    fun it_recognizes_nft_type() {
        assert!(utils::is_nft_protocol_nft_type<Nft<sui::object::ID>>(), 0);
        assert!(!utils::is_nft_protocol_nft_type<sui::object::ID>(), 1);
        assert!(!utils::is_nft_protocol_nft_type<utils::Marker<sui::object::ID>>(), 2);
        assert!(!utils::is_nft_protocol_nft_type<nft::MintNftEvent>(), 2);
    }
}
