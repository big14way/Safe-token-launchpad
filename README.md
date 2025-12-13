# Safe Token Launchpad

A rug-pull resistant token launchpad using Clarity 4's contract verification features.

## Clarity 4 Features Used

| Feature | Usage | Status |
|---------|-------|--------|
| `contract-hash?` | Verify token contracts match approved templates | ✅ Implemented |
| `stacks-block-time` | Accurate timestamps for launch timing | ✅ Implemented |
| `print` events | Event logging for all major operations | ✅ Implemented |

**Event Logging:** All major operations emit structured events:
- `token-listed`, `tokens-bought`, `tokens-sold`
- `launch-created`, `launch-contribution`, `launch-finalized`
- `launch-claim`, `launch-refund`

## Features

- 🔒 **Hash Verification**: Only tokens matching approved contract templates get "verified" status
- 🚀 **Fair Launch**: Time-limited token sales with min/max raise caps
- 💱 **AMM Swaps**: Constant-product DEX for listed tokens
- 💰 **Fee Collection**: 0.3% swap fee, 0.1% protocol fee
- ⏸️ **Emergency Pause**: Admin can pause all operations
- 🔄 **Refund Mechanism**: Failed launches automatically refund contributors

## How It Works

### Hash Verification System

1. Admin pre-approves known-safe token contract hashes
2. When a token is listed, its contract hash is checked against approved hashes
3. Tokens matching approved templates get a "verified" badge
4. Users can see verification status before trading

### Fair Launch Process

1. Creator deposits tokens for sale with min/max raise targets
2. Contributors send STX during 24-hour launch window
3. After launch ends, anyone can finalize
4. If min raise met: tokens distributed proportionally
5. If min raise not met: contributors can claim full refunds

## Contract Functions

### Admin Functions
- `add-approved-hash` - Add safe token template hash
- `remove-approved-hash` - Remove a hash
- `toggle-pause` - Pause/unpause protocol
- `withdraw-protocol-fees` - Collect accumulated fees

### Token Listing
- `list-token` - List a token with initial liquidity
- `verify-contract-hash` - Get a contract's hash

### Trading
- `buy-tokens` - Swap STX for tokens
- `sell-tokens` - Swap tokens for STX
- `get-swap-quote` - Calculate expected output

### Fair Launch
- `create-launch` - Create a new fair launch
- `contribute-to-launch` - Contribute STX to a launch
- `finalize-launch` - End a launch and determine success
- `claim-from-launch` - Claim tokens or refund

### Read-Only
- `get-token-listing` - Get listing details
- `is-token-verified` - Check if token is from approved template
- `get-launch-pool` - Get launch details
- `get-contribution` - Get user's contribution
- `get-protocol-stats` - Protocol-wide statistics

## Deployment Status

✅ **Ready for Testnet Deployment**

**Deployer Address:** `ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE`

**Deployed Contracts:**
- `ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.sip-010-trait`
- `ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.sample-token`
- `ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.safe-launchpad`


## Getting Started

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) v3.11.0+
- Clarity 4 support (epoch 3.3)

### Installation

```bash
cd safe-token-launchpad
clarinet check
```

### Deploy to Testnet

1. Fund the deployer address with testnet STX from https://explorer.hiro.so/sandbox/faucet?chain=testnet
2. Deploy contracts:
```bash
clarinet deployments apply -p deployments/default.testnet-plan.yaml
```

## Usage Examples

### 1. Add Approved Token Hash (Admin)

```clarity
;; Get hash of a known-safe token contract
(contract-hash? 'SP123...safe-token)
;; Returns: (some 0x...)

;; Add to approved list
(contract-call? .safe-launchpad add-approved-hash 
    0x... ;; hash
    "Standard SIP-010 Token")
```

### 2. List a Token

```clarity
(contract-call? .safe-launchpad list-token 
    .my-token
    u100000000   ;; 100 STX initial liquidity
    u1000000000) ;; 1000 tokens
;; Returns: { pool-id: 1, verified: true/false, hash: 0x... }
```

### 3. Swap Tokens

```clarity
;; Buy tokens
(contract-call? .safe-launchpad buy-tokens 
    .my-token
    u10000000  ;; 10 STX
    u90000000) ;; min 90 tokens out (slippage protection)

;; Sell tokens
(contract-call? .safe-launchpad sell-tokens 
    .my-token
    u100000000 ;; 100 tokens
    u9000000)  ;; min 9 STX out
```

### 4. Create Fair Launch

```clarity
(contract-call? .safe-launchpad create-launch 
    .my-token
    u500000000   ;; 500 tokens for sale
    u50000000    ;; Min raise: 50 STX
    u500000000)  ;; Max raise: 500 STX
```

### 5. Contribute to Launch

```clarity
(contract-call? .safe-launchpad contribute-to-launch 
    u1           ;; launch-id
    u25000000)   ;; 25 STX contribution
```

## Security Model

### Why Contract Hashes Matter

Traditional launchpads can't verify if a token contract is safe. Malicious contracts might:
- Have hidden mint functions
- Allow owner to drain liquidity
- Implement transfer taxes that steal funds

With `contract-hash?`, we can:
1. Audit known-safe token templates
2. Compute their immutable code hashes
3. Only give "verified" status to tokens matching these hashes
4. Users instantly know if a token uses safe, audited code

### Additional Protections

- **Slippage Protection**: All swaps require minimum output amounts
- **Time-Bounded Launches**: 24-hour window prevents manipulation
- **Refund Guarantee**: Failed launches return all contributed STX
- **Emergency Pause**: Admin can halt operations if issues are discovered

## Fee Structure

| Action | Fee |
|--------|-----|
| List Token | 10 STX (one-time) |
| Swap | 0.3% of input |
| Protocol | 0.1% of swaps |

## Project Status

✅ Clarity 4 compatible (epoch 3.3)
✅ All contracts pass `clarinet check`
✅ Comprehensive test suite (12 tests covering all major functions)
✅ Event logging for monitoring
✅ Best practices .gitignore
✅ Ready for testnet deployment
✅ Comprehensive documentation

## Testing

The project includes 12 comprehensive tests covering:
- Hash approval system (admin functions)
- Token listing with verification
- Swap functionality (buy/sell)
- Fair launch creation and contributions
- Launch finalization and claims
- Pause functionality
- Edge cases and error handling

Tests verify Clarity 4 features including `contract-hash?` verification.

## Repository

**GitHub:** https://github.com/big14way/Safe-token-launchpad.git

## License

MIT License
