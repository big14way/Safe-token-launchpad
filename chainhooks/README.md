# Safe Token Launchpad Chainhooks Integration

Real-time event tracking and analytics for the Safe Token Launchpad platform. Monitors token listings, swaps, fair launches, and fee collection using Stacks Chainhooks.

## Features

### Event Tracking

This integration monitors all key Safe Token Launchpad events:

1. **Token Listings** (`list-token`)
   - Tracks new token pool listings
   - Records listing fees (10 STX per listing)
   - Monitors verified vs unverified tokens
   - Captures initial liquidity amounts

2. **Token Swaps**
   - **Buy Events** (`buy-tokens`) - Users buying tokens with STX
   - **Sell Events** (`sell-tokens`) - Users selling tokens for STX
   - Tracks swap fees (0.3% on each transaction)
   - Records protocol fees (0.1% on each transaction)
   - Monitors trading volume (STX and tokens)

3. **Fair Launches**
   - **Launch Creation** (`create-launch`) - New token launches
   - **Contributions** (`contribute-to-launch`) - User contributions to launches
   - **Finalization** (`finalize-launch`) - Launch completion (success/failure)
   - **Claims** (`claim-from-launch`) - Token distributions or refunds

4. **Print Events**
   - Detailed transaction data extraction
   - Real-time fee calculations
   - Volume tracking and analytics

### Analytics Collected

The integration tracks comprehensive metrics:

- **Users**: Unique wallet addresses interacting with the platform
- **Listings**: Total token pools created
- **Swaps**: Total buy/sell transactions
- **Launches**: Fair launch campaigns created
- **Contributions**: Total contributions to launches
- **Fees Collected**:
  - Listing fees: 10 STX per listing
  - Swap fees: 0.3% of transaction value
  - Protocol fees: 0.1% of transaction value
- **Trading Volume**: Total STX and token volume

## Setup

### Prerequisites

- Node.js 18+ and npm
- Access to a Stacks Chainhook node (Hiro Platform or self-hosted)
- The Safe Token Launchpad contract deployed on Stacks testnet/mainnet

### Installation

1. Navigate to the chainhooks directory:
```bash
cd safe-token-launchpad/chainhooks
```

2. Install dependencies:
```bash
npm install
```

3. Copy and configure environment variables:
```bash
cp .env.example .env
```

4. Edit `.env` with your configuration:
```env
# Chainhook Node Configuration
CHAINHOOK_NODE_URL=http://localhost:20456

# Server Configuration
SERVER_HOST=0.0.0.0
SERVER_PORT=3000
SERVER_AUTH_TOKEN=your-secret-token-here
EXTERNAL_BASE_URL=http://localhost:3000

# Contract Configuration
LAUNCHPAD_CONTRACT=ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.safe-launchpad
TOKEN_CONTRACT=ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.sample-token

# Starting block height
START_BLOCK=0

# Network
NETWORK=testnet
```

### Running the Observer

Start the Chainhook observer:

```bash
npm start
```

For development with auto-reload:

```bash
npm run dev
```

## Contract Events

### Monitored Functions

| Function | Description | Fee |
|----------|-------------|-----|
| `list-token` | Create new token pool | 10 STX listing fee |
| `buy-tokens` | Buy tokens with STX | 0.3% swap fee + 0.1% protocol fee |
| `sell-tokens` | Sell tokens for STX | 0.3% swap fee + 0.1% protocol fee |
| `create-launch` | Create fair launch | None |
| `contribute-to-launch` | Contribute STX to launch | None |
| `finalize-launch` | Finalize launch after deadline | None |
| `claim-from-launch` | Claim tokens or refund | None |

### Print Events Tracked

The contract emits detailed print events:

```clarity
{event: "token-listed", pool-id: uint, token: principal, verified: bool, lister: principal}
{event: "tokens-bought", token: principal, buyer: principal, stx-in: uint, tokens-out: uint}
{event: "tokens-sold", token: principal, seller: principal, tokens-in: uint, stx-out: uint}
{event: "launch-created", launch-id: uint, token: principal, creator: principal, tokens-for-sale: uint}
{event: "launch-contribution", launch-id: uint, contributor: principal, amount: uint, total-raised: uint}
{event: "launch-finalized", launch-id: uint, successful: bool, total-raised: uint}
{event: "launch-claim", launch-id: uint, claimer: principal, tokens-received: uint}
{event: "launch-refund", launch-id: uint, claimer: principal, refund: uint}
```

## Analytics Output

Analytics data is saved to `analytics-data.json` in the following format:

```json
{
  "users": ["ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM", "..."],
  "uniqueUsers": 42,
  "totalListings": 15,
  "totalLaunches": 8,
  "totalSwaps": 234,
  "totalContributions": 67,
  "listingFeesCollected": 150000000,
  "swapFeesCollected": 3450000,
  "protocolFeesCollected": 1150000,
  "totalVolumeSTX": 1500000000,
  "totalTokenVolume": 75000000,
  "listings": [
    {
      "lister": "ST...",
      "timestamp": "2024-01-15T10:30:00.000Z",
      "txid": "0x..."
    }
  ],
  "swaps": [
    {
      "buyer": "ST...",
      "type": "buy",
      "timestamp": "2024-01-15T11:00:00.000Z",
      "txid": "0x..."
    }
  ],
  "launches": [...],
  "contributions": [...],
  "claims": [...],
  "timestamp": "2024-01-15T12:00:00.000Z"
}
```

## Key Metrics

### Fee Structure

- **Listing Fee**: 10 STX per token listing (paid upfront)
- **Swap Fee**: 0.3% on each buy/sell transaction
- **Protocol Fee**: 0.1% on each buy/sell transaction
- **Launch Fees**: No fees for creating or participating in launches

### Volume Tracking

- **STX Volume**: Total STX traded through swaps and contributions
- **Token Volume**: Total tokens traded through the platform
- **User Growth**: Unique wallet addresses interacting with contracts

## Use Cases

### Platform Analytics
- Track total value locked (TVL)
- Monitor daily/weekly trading volume
- Analyze user acquisition and retention

### Fee Revenue
- Calculate platform earnings from listing fees
- Monitor swap fee generation
- Track protocol fee accumulation

### Launch Metrics
- Success rate of fair launches
- Average contribution amounts
- Token distribution statistics

### User Insights
- Most active traders
- Token launch participation rates
- Popular trading pairs

## Architecture

The integration uses the Hiro Chainhook Event Observer to:

1. Register predicates for specific contract functions
2. Listen for blockchain events in real-time
3. Parse transaction data and print events
4. Aggregate analytics and store results
5. Provide graceful shutdown with data persistence

## Troubleshooting

### Observer won't start
- Verify Chainhook node URL is accessible
- Check that contract address matches deployed contract
- Ensure START_BLOCK is valid

### Missing events
- Confirm contract is deployed and active
- Verify network setting (testnet/mainnet)
- Check Chainhook node is synced

### Analytics not saving
- Ensure write permissions in directory
- Check disk space availability
- Verify JSON serialization of analytics data

## Production Considerations

For production deployments:

1. **Database Integration**: Replace in-memory storage with PostgreSQL/MongoDB
2. **Error Handling**: Add retry logic and error notification
3. **Monitoring**: Integrate with monitoring services (Datadog, New Relic)
4. **Scaling**: Use message queues for high-volume processing
5. **Security**: Rotate auth tokens, use HTTPS, secure database connections

## Contract Information

- **Contract**: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.safe-launchpad`
- **Token**: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.sample-token`
- **Network**: Stacks Testnet
- **Clarity Version**: 4 (Epoch 3.3)

## Resources

- [Stacks Chainhooks Documentation](https://docs.hiro.so/chainhooks)
- [Safe Token Launchpad Contract](../contracts/safe-launchpad.clar)
- [Hiro Platform](https://platform.hiro.so/)

## License

MIT
