import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals, assertExists } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

// Test hash (32 bytes)
const TEST_HASH = '0x' + 'a'.repeat(64);

Clarinet.test({
    name: "Admin can add approved hash",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'add-approved-hash', [
                types.buff(TEST_HASH),
                types.ascii("Standard SIP-010 Token")
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk().expectBool(true);
        
        // Verify hash was added
        let hashResult = chain.callReadOnlyFn(
            'safe-launchpad',
            'is-hash-approved',
            [types.buff(TEST_HASH)],
            deployer.address
        );
        
        hashResult.result.expectBool(true);
    }
});

Clarinet.test({
    name: "Non-admin cannot add approved hash",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'add-approved-hash', [
                types.buff(TEST_HASH),
                types.ascii("Malicious Token")
            ], wallet1.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(100); // ERR_NOT_AUTHORIZED
    }
});

Clarinet.test({
    name: "Admin can remove approved hash",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'add-approved-hash', [
                types.buff(TEST_HASH),
                types.ascii("Standard SIP-010 Token")
            ], deployer.address),
            Tx.contractCall('safe-launchpad', 'remove-approved-hash', [
                types.buff(TEST_HASH)
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectOk();
        
        // Verify hash was removed
        let hashResult = chain.callReadOnlyFn(
            'safe-launchpad',
            'is-hash-approved',
            [types.buff(TEST_HASH)],
            deployer.address
        );
        
        hashResult.result.expectBool(false);
    }
});

Clarinet.test({
    name: "Can list token with initial liquidity",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'list-token', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(100000000), // 100 STX
                types.uint(1000000000) // 1000 tokens
            ], deployer.address)
        ]);
        
        // Should succeed (though token won't be "verified" unless hash is pre-approved)
        block.receipts[0].result.expectOk();
        
        // Check listing exists
        let listingResult = chain.callReadOnlyFn(
            'safe-launchpad',
            'get-token-listing',
            [types.principal(deployer.address + '.sample-token')],
            deployer.address
        );
        
        assertExists(listingResult.result);
    }
});

Clarinet.test({
    name: "Cannot list same token twice",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'list-token', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(100000000),
                types.uint(1000000000)
            ], deployer.address),
            Tx.contractCall('safe-launchpad', 'list-token', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(100000000),
                types.uint(1000000000)
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectErr().expectUint(102); // ERR_TOKEN_ALREADY_LISTED
    }
});

Clarinet.test({
    name: "Can get swap quote",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        // First list the token
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'list-token', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(100000000), // 100 STX
                types.uint(1000000000) // 1000 tokens
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk();
        
        // Get buy quote
        let quoteResult = chain.callReadOnlyFn(
            'safe-launchpad',
            'get-swap-quote',
            [
                types.principal(deployer.address + '.sample-token'),
                types.uint(10000000), // 10 STX
                types.bool(true) // buying
            ],
            deployer.address
        );
        
        quoteResult.result.expectOk();
    }
});

Clarinet.test({
    name: "Can create a fair launch",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'create-launch', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(500000000), // 500 tokens for sale
                types.uint(50000000),  // Min raise: 50 STX
                types.uint(500000000)  // Max raise: 500 STX
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk();
        
        // Verify launch was created
        let launchResult = chain.callReadOnlyFn(
            'safe-launchpad',
            'get-launch-pool',
            [types.uint(1)],
            deployer.address
        );
        
        assertExists(launchResult.result);
    }
});

Clarinet.test({
    name: "Can contribute to launch",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            // Create launch
            Tx.contractCall('safe-launchpad', 'create-launch', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(500000000),
                types.uint(50000000),
                types.uint(500000000)
            ], deployer.address),
            // Contribute
            Tx.contractCall('safe-launchpad', 'contribute-to-launch', [
                types.uint(1),
                types.uint(25000000) // 25 STX
            ], wallet1.address)
        ]);
        
        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectOk();
        
        // Check contribution
        let contribResult = chain.callReadOnlyFn(
            'safe-launchpad',
            'get-contribution',
            [types.uint(1), types.principal(wallet1.address)],
            wallet1.address
        );
        
        const contrib = contribResult.result.expectSome().expectTuple();
        assertEquals(contrib['amount'], types.uint(25000000));
    }
});

Clarinet.test({
    name: "Cannot exceed max raise",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            // Create launch with low max
            Tx.contractCall('safe-launchpad', 'create-launch', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(500000000),
                types.uint(10000000),  // Min: 10 STX
                types.uint(20000000)   // Max: 20 STX
            ], deployer.address),
            // Try to contribute more than max
            Tx.contractCall('safe-launchpad', 'contribute-to-launch', [
                types.uint(1),
                types.uint(50000000) // 50 STX - exceeds max
            ], wallet1.address)
        ]);
        
        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectErr().expectUint(106); // ERR_SLIPPAGE_TOO_HIGH
    }
});

Clarinet.test({
    name: "Protocol stats are tracked correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'list-token', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(100000000),
                types.uint(1000000000)
            ], deployer.address),
            Tx.contractCall('safe-launchpad', 'create-launch', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(500000000),
                types.uint(50000000),
                types.uint(500000000)
            ], deployer.address)
        ]);
        
        let statsResult = chain.callReadOnlyFn(
            'safe-launchpad',
            'get-protocol-stats',
            [],
            deployer.address
        );
        
        const stats = statsResult.result.expectTuple();
        assertEquals(stats['total-pools'], types.uint(1));
        assertEquals(stats['total-launches'], types.uint(1));
    }
});

Clarinet.test({
    name: "Admin can toggle pause",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'toggle-pause', [], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk().expectBool(true);
        
        // Verify paused
        let statsResult = chain.callReadOnlyFn(
            'safe-launchpad',
            'get-protocol-stats',
            [],
            deployer.address
        );
        
        const stats = statsResult.result.expectTuple();
        assertEquals(stats['paused'], types.bool(true));
    }
});

Clarinet.test({
    name: "Cannot list token when paused",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'toggle-pause', [], deployer.address),
            Tx.contractCall('safe-launchpad', 'list-token', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(100000000),
                types.uint(1000000000)
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectErr().expectUint(100); // ERR_NOT_AUTHORIZED
    }
});

Clarinet.test({
    name: "Verify contract hash function works",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let hashResult = chain.callReadOnlyFn(
            'safe-launchpad',
            'verify-contract-hash',
            [types.principal(deployer.address + '.sample-token')],
            deployer.address
        );
        
        // Should return a hash (32 bytes)
        hashResult.result.expectOk();
    }
});

Clarinet.test({
    name: "Cannot list with zero amounts",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('safe-launchpad', 'list-token', [
                types.principal(deployer.address + '.sample-token'),
                types.uint(0), // Zero STX
                types.uint(1000000000)
            ], deployer.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(107); // ERR_ZERO_AMOUNT
    }
});
