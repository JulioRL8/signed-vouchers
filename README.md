# Signed Vouchers

An ETH vault that accepts single-use, expiring EIP-712 vouchers authorized by an immutable signer.

## How it works

1. Deploy with an EOA signer and fund the vault at deployment or by sending ETH later.
2. The signer authorizes a `Voucher(address recipient,uint256 amount,uint256 nonce,uint256 deadline)` using EIP-712. The domain uses name `SignedVouchers`, version `1`, the chain ID and the vault address.
3. Anyone can relay `redeem(voucher, v, r, s)`. Only the signed recipient receives ETH, and a successful redemption consumes the nonce globally in that vault.

The deadline is inclusive. The signer should assign a distinct nonce to every voucher and account for outstanding commitments. This implementation supports EOA signatures with canonical low-s values.

## Build and test

Install [Foundry](https://getfoundry.sh/) and run these commands from this directory. Forge selects Solidity 0.8.36 from `foundry.toml`. The project has no third-party Solidity dependencies.

```bash
forge build
forge test -vv
forge coverage --exclude-tests
```

## Local deployment

Start a fresh `anvil` node in a separate terminal. Deploy with the first unlocked account on that local node.

```bash
export RPC_URL=http://127.0.0.1:8545
export ANVIL_ACCOUNT=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
forge create src/SignedVouchers.sol:SignedVouchers --rpc-url "$RPC_URL" --from "$ANVIL_ACCOUNT" --unlocked --broadcast --value 1ether --constructor-args "$ANVIL_ACCOUNT"
```

## Local example

Set `CONTRACT` to the address printed by `forge create` and keep using the same terminal. This example signs the typed-data digest using the default Anvil development mnemonic.

```bash
export ETH_RPC_URL="$RPC_URL"
CONTRACT=0x... # Replace with your deployed address.
RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
DEADLINE=$(($(date +%s) + 3600))
VOUCHER="($RECIPIENT,100000000000000000,7,$DEADLINE)"
DIGEST=$(cast call "$CONTRACT" 'digest((address,uint256,uint256,uint256))(bytes32)' "$VOUCHER")
DEMO_MNEMONIC="test test test test test test test test test test test junk"
SIGNATURE=$(cast wallet sign --mnemonic "$DEMO_MNEMONIC" --no-hash "$DIGEST")
R="0x${SIGNATURE:2:64}"
S="0x${SIGNATURE:66:64}"
V=$(cast to-dec "0x${SIGNATURE:130:2}")
cast send "$CONTRACT" 'redeem((address,uint256,uint256,uint256),uint8,bytes32,bytes32)' \
  "$VOUCHER" "$V" "$R" "$S" --from "$ANVIL_ACCOUNT" --unlocked
cast call "$CONTRACT" 'used(uint256)(bool)' 7
```

Sign the voucher with the configured signer using typed data. The resulting `r`, `s`, and `v` values go into `redeem((address,uint256,uint256,uint256),uint8,bytes32,bytes32)`, in the order `voucher, v, r, s`. Normalize `v` to 27 or 28 if the signing library returns 0 or 1.

## Test cases

Foundry reports 7 passing tests and 100% coverage on contract lines, statements, branches and functions.

- Independent EIP-712 digest fixture, relayed payment and nonce replay protection.
- Wrong signers, contract and chain separation, expiry and canonical signature checks.
- Failed transfers preserve the nonce and permit retry after funding.
