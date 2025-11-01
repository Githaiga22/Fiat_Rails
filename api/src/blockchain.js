import { ethers } from 'ethers';
import { config } from './config.js';

// Contract ABIs (minimal - only functions we need)
const MINT_ESCROW_ABI = [
  'function submitIntent(uint256 amount, bytes32 countryCode, bytes32 txRef) external returns (bytes32 intentId)',
  'function executeMint(bytes32 intentId) external',
  'function refundIntent(bytes32 intentId, string reason) external',
  'function getIntent(bytes32 intentId) external view returns (tuple(address user, uint256 amount, bytes32 countryCode, bytes32 txRef, uint256 timestamp, uint8 status))',
  'event MintIntentSubmitted(bytes32 indexed intentId, address indexed user, uint256 amount, bytes32 indexed countryCode, bytes32 txRef)',
  'event MintExecuted(bytes32 indexed intentId, address indexed user, uint256 amount, bytes32 indexed countryCode, bytes32 txRef)',
  'event MintRefunded(bytes32 indexed intentId, address indexed user, uint256 amount, string reason)',
];

const USER_REGISTRY_ABI = [
  'function isCompliant(address user) external view returns (bool)',
  'function getRiskScore(address user) external view returns (uint8)',
];

let provider = null;
let wallet = null;
let contracts = {};

/**
 * Initialize blockchain provider and contracts
 */
export function initBlockchain() {
  // Create provider with timeout
  provider = new ethers.JsonRpcProvider(
    config.chain.rpcUrl,
    config.chain.chainId,
    { timeout: config.timeouts.rpcTimeoutMs }
  );

  // Create wallet for signing transactions
  wallet = new ethers.Wallet(config.executorPrivateKey, provider);

  // Initialize contract instances
  contracts.mintEscrow = new ethers.Contract(
    config.contracts.mintEscrow,
    MINT_ESCROW_ABI,
    wallet
  );

  contracts.userRegistry = new ethers.Contract(
    config.contracts.userRegistry,
    USER_REGISTRY_ABI,
    provider
  );

  console.log('Blockchain initialized:', {
    chainId: config.chain.chainId,
    executor: wallet.address,
    mintEscrow: config.contracts.mintEscrow,
  });

  return { provider, wallet, contracts };
}

/**
 * Get blockchain instances
 */
export function getBlockchain() {
  if (!provider || !wallet || !contracts.mintEscrow) {
    throw new Error('Blockchain not initialized. Call initBlockchain() first.');
  }
  return { provider, wallet, contracts };
}

/**
 * Check if user is compliant
 */
export async function checkCompliance(userAddress) {
  const { contracts } = getBlockchain();
  return await contracts.userRegistry.isCompliant(userAddress);
}

/**
 * Submit mint intent on-chain
 */
export async function submitMintIntent(amount, countryCode, txRef) {
  const { contracts } = getBlockchain();

  const tx = await contracts.mintEscrow.submitIntent(
    amount,
    ethers.encodeBytes32String(countryCode),
    ethers.encodeBytes32String(txRef)
  );

  const receipt = await tx.wait();

  // Extract intentId from event
  const event = receipt.logs.find(
    (log) => log.topics[0] === ethers.id('MintIntentSubmitted(bytes32,address,uint256,bytes32,bytes32)')
  );

  const intentId = event?.topics[1];

  return { intentId, txHash: receipt.hash };
}

/**
 * Execute mint for a given intent
 */
export async function executeMint(intentId) {
  const { contracts } = getBlockchain();

  const tx = await contracts.mintEscrow.executeMint(intentId);
  const receipt = await tx.wait();

  return { txHash: receipt.hash };
}

/**
 * Refund a mint intent
 */
export async function refundMintIntent(intentId, reason) {
  const { contracts } = getBlockchain();

  const tx = await contracts.mintEscrow.refundIntent(intentId, reason);
  const receipt = await tx.wait();

  return { txHash: receipt.hash };
}

/**
 * Get intent details
 */
export async function getIntent(intentId) {
  const { contracts } = getBlockchain();
  return await contracts.mintEscrow.getIntent(intentId);
}
