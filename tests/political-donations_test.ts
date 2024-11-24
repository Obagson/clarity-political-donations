import {
    Clarinet,
    Tx,
    Chain,
    Account,
    types
} from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Ensures only contract owner can register candidates",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;

        let block = chain.mineBlock([
            Tx.contractCall('political-donations', 'register-candidate',
                [types.ascii("John Doe"), types.ascii("Independent")],
                deployer.address
            ),
            Tx.contractCall('political-donations', 'register-candidate',
                [types.ascii("Jane Smith"), types.ascii("Independent")],
                wallet1.address
            )
        ]);

        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectErr(types.uint(100));
    }
});

Clarinet.test({
    name: "Ensures donations work correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('political-donations', 'register-candidate',
                [types.ascii("John Doe"), types.ascii("Independent")],
                deployer.address
            ),
            Tx.contractCall('political-donations', 'make-donation',
                [
                    types.principal(deployer.address),
                    types.uint(2000000),
                    types.some(types.utf8("Support!"))
                ],
                wallet1.address
            )
        ]);

        block.receipts[0].result.expectOk();
        block.receipts[1].result.expectOk();
    }
});
