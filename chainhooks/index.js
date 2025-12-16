import { ChainhookEventObserver } from '@hirosystems/chainhook-client';
import { randomUUID } from 'crypto';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';

dotenv.config();

// Analytics storage (in production, use a database)
const analytics = {
  users: new Set(),
  totalListings: 0,
  totalLaunches: 0,
  totalSwaps: 0,
  totalContributions: 0,
  listingFeesCollected: 0, // 10 STX per listing
  swapFeesCollected: 0, // 0.3% on swaps
  protocolFeesCollected: 0, // 0.1% on swaps
  totalVolumeSTX: 0,
  totalTokenVolume: 0,
  listings: [],
  swaps: [],
  launches: [],
  contributions: [],
  claims: []
};

// Save analytics to JSON file
function saveAnalytics() {
  const data = {
    ...analytics,
    users: Array.from(analytics.users),
    timestamp: new Date().toISOString(),
    uniqueUsers: analytics.users.size
  };

  fs.writeFileSync(
    path.join(process.cwd(), 'analytics-data.json'),
    JSON.stringify(data, null, 2)
  );

  console.log(`📊 Analytics saved - Users: ${data.uniqueUsers}, Listings: ${data.totalListings}, Swaps: ${data.totalSwaps}, Launches: ${data.totalLaunches}`);
}

// Create predicates for launchpad events
function createLaunchpadPredicates() {
  const contractId = process.env.LAUNCHPAD_CONTRACT;
  const startBlock = parseInt(process.env.START_BLOCK) || 0;
  const network = process.env.NETWORK || 'testnet';

  return [
    {
      uuid: randomUUID(),
      name: 'token-listing-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'list-token'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/listing`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'token-buy-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'buy-tokens'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/buy`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'token-sell-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'sell-tokens'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/sell`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'launch-created-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'create-launch'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/launch-created`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'launch-contribution-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'contribute-to-launch'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/contribution`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'launch-finalized-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'finalize-launch'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/launch-finalized`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'launch-claim-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'contract_call',
            contract_identifier: contractId,
            method: 'claim-from-launch'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/claim`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    },
    {
      uuid: randomUUID(),
      name: 'launchpad-print-events',
      version: 1,
      chain: 'stacks',
      networks: {
        [network]: {
          if_this: {
            scope: 'print_event',
            contract_identifier: contractId,
            contains: 'event'
          },
          then_that: {
            http_post: {
              url: `${process.env.EXTERNAL_BASE_URL}/chainhook/print-event`,
              authorization_header: `Bearer ${process.env.SERVER_AUTH_TOKEN}`
            }
          },
          start_block: startBlock
        }
      }
    }
  ];
}

// Parse print event data
function parsePrintEvent(eventValue) {
  try {
    // Handle different event formats
    if (typeof eventValue === 'string') {
      return JSON.parse(eventValue);
    }
    return eventValue;
  } catch (error) {
    console.error('Error parsing print event:', error);
    return null;
  }
}

// Event handler
async function handleChainhookEvent(uuid, payload) {
  console.log(`\n🔔 Event received: ${uuid}`);

  try {
    // Process transactions in the payload
    if (payload.apply && payload.apply.length > 0) {
      for (const block of payload.apply) {
        console.log(`📦 Block ${block.block_identifier.index}`);

        for (const tx of block.transactions) {
          const sender = tx.metadata.sender;
          analytics.users.add(sender);

          // Process contract calls
          if (tx.metadata.kind?.data?.contract_call) {
            const contractCall = tx.metadata.kind.data.contract_call;
            const method = contractCall.function_name;

            console.log(`  → ${sender} called ${method}`);

            switch (method) {
              case 'list-token':
                analytics.totalListings++;
                analytics.listingFeesCollected += 10000000; // 10 STX listing fee
                analytics.listings.push({
                  lister: sender,
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  📋 Token listed - Listing fee: 10 STX`);
                break;

              case 'buy-tokens':
                analytics.totalSwaps++;
                analytics.swaps.push({
                  buyer: sender,
                  type: 'buy',
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  💰 Tokens bought`);
                break;

              case 'sell-tokens':
                analytics.totalSwaps++;
                analytics.swaps.push({
                  seller: sender,
                  type: 'sell',
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  💸 Tokens sold`);
                break;

              case 'create-launch':
                analytics.totalLaunches++;
                analytics.launches.push({
                  creator: sender,
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  🚀 Launch created`);
                break;

              case 'contribute-to-launch':
                analytics.totalContributions++;
                analytics.contributions.push({
                  contributor: sender,
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  🤝 Contribution made to launch`);
                break;

              case 'finalize-launch':
                console.log(`  ✅ Launch finalized`);
                break;

              case 'claim-from-launch':
                analytics.claims.push({
                  claimer: sender,
                  timestamp: new Date().toISOString(),
                  txid: tx.transaction_identifier.hash
                });
                console.log(`  🎁 Tokens claimed from launch`);
                break;
            }
          }

          // Process print events for detailed tracking
          if (tx.metadata.receipt?.events) {
            for (const event of tx.metadata.receipt.events) {
              if (event.type === 'SmartContractEvent') {
                const eventData = parsePrintEvent(event.data.value);

                if (eventData) {
                  // Track specific events from print statements
                  if (eventData.event === 'token-listed') {
                    console.log(`  ℹ️  Token listed: Pool ID ${eventData['pool-id']}, Verified: ${eventData.verified}`);
                  } else if (eventData.event === 'tokens-bought') {
                    const stxIn = eventData['stx-in'] || 0;
                    const tokensOut = eventData['tokens-out'] || 0;
                    const feePaid = eventData['fee-paid'] || 0;

                    analytics.totalVolumeSTX += stxIn;
                    analytics.totalTokenVolume += tokensOut;
                    analytics.swapFeesCollected += feePaid;

                    console.log(`  ℹ️  Buy: ${stxIn / 1000000} STX → ${tokensOut} tokens (Fee: ${feePaid / 1000000} STX)`);
                  } else if (eventData.event === 'tokens-sold') {
                    const tokensIn = eventData['tokens-in'] || 0;
                    const stxOut = eventData['stx-out'] || 0;
                    const feePaid = eventData['fee-paid'] || 0;

                    analytics.totalVolumeSTX += stxOut;
                    analytics.totalTokenVolume += tokensIn;
                    analytics.swapFeesCollected += feePaid;

                    console.log(`  ℹ️  Sell: ${tokensIn} tokens → ${stxOut / 1000000} STX (Fee: ${feePaid / 1000000} STX)`);
                  } else if (eventData.event === 'launch-created') {
                    console.log(`  ℹ️  Launch ID ${eventData['launch-id']} created for ${eventData['tokens-for-sale']} tokens`);
                  } else if (eventData.event === 'launch-contribution') {
                    const amount = eventData.amount || 0;
                    analytics.totalVolumeSTX += amount;
                    console.log(`  ℹ️  Contribution: ${amount / 1000000} STX to launch ${eventData['launch-id']}`);
                  } else if (eventData.event === 'launch-finalized') {
                    console.log(`  ℹ️  Launch ${eventData['launch-id']} finalized - Success: ${eventData.successful}`);
                  }
                }
              }
            }
          }
        }
      }

      // Save analytics after processing
      saveAnalytics();
    }

  } catch (error) {
    console.error('Error processing event:', error);
  }
}

// Start the observer
async function start() {
  console.log('🚀 Starting Safe Token Launchpad Chainhook Observer\n');

  const serverOptions = {
    hostname: process.env.SERVER_HOST,
    port: parseInt(process.env.SERVER_PORT),
    auth_token: process.env.SERVER_AUTH_TOKEN,
    external_base_url: process.env.EXTERNAL_BASE_URL
  };

  const chainhookOptions = {
    base_url: process.env.CHAINHOOK_NODE_URL
  };

  const predicates = createLaunchpadPredicates();

  console.log(`📡 Server: ${serverOptions.external_base_url}`);
  console.log(`🔗 Chainhook Node: ${chainhookOptions.base_url}`);
  console.log(`📋 Monitoring ${predicates.length} event types\n`);
  console.log(`📝 Contract: ${process.env.LAUNCHPAD_CONTRACT}\n`);

  const observer = new ChainhookEventObserver(serverOptions, chainhookOptions);

  try {
    await observer.start(predicates, handleChainhookEvent);
    console.log('✅ Observer started successfully!\n');
    console.log('Tracking:');
    console.log('  - Token listings (10 STX listing fee)');
    console.log('  - Token swaps (0.3% swap fee, 0.1% protocol fee)');
    console.log('  - Fair launches (create, contribute, finalize)');
    console.log('  - Token claims\n');
    console.log('Waiting for events...\n');
  } catch (error) {
    console.error('❌ Failed to start observer:', error.message);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n\n👋 Shutting down gracefully...');
  saveAnalytics();
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('\n\n👋 Shutting down gracefully...');
  saveAnalytics();
  process.exit(0);
});

// Start the observer
start().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
