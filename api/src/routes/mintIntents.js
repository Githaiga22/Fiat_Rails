import { Router } from 'express';
import { submitMintIntent } from '../blockchain.js';
import { config } from '../config.js';
import { hmacVerification } from '../middleware/hmacVerification.js';
import { idempotency } from '../middleware/idempotency.js';
import { addToRetryQueue } from '../services/retry.js';

const router = Router();

/**
 * POST /mint-intents
 * Submit a new mint intent
 */
router.post(
  '/mint-intents',
  hmacVerification,
  idempotency,
  async (req, res) => {
    try {
      const { amount, countryCode, txRef, userAddress } = req.body;

      // Validate request body
      if (!amount || !countryCode || !txRef || !userAddress) {
        return res.status(400).json({
          error: 'Bad Request',
          message: 'Missing required fields: amount, countryCode, txRef, userAddress',
        });
      }

      // Validate amount is within limits
      const amountBigInt = BigInt(amount);
      if (amountBigInt < config.limits.minMintAmount) {
        return res.status(400).json({
          error: 'Bad Request',
          message: `Amount below minimum: ${config.limits.minMintAmount}`,
        });
      }

      if (amountBigInt > config.limits.maxMintAmount) {
        return res.status(400).json({
          error: 'Bad Request',
          message: `Amount exceeds maximum: ${config.limits.maxMintAmount}`,
        });
      }

      // Validate country code
      if (countryCode !== 'KES') {
        return res.status(400).json({
          error: 'Bad Request',
          message: 'Invalid country code. Only KES is supported.',
        });
      }

      // Submit to blockchain with retry on failure
      let result;
      try {
        result = await submitMintIntent(amountBigInt, countryCode, txRef);
      } catch (error) {
        // RPC failure - add to retry queue
        console.error('Failed to submit mint intent:', error.message);

        addToRetryQueue(
          txRef, // Use txRef as temporary ID
          'submit',
          { amount, countryCode, txRef, userAddress }
        );

        return res.status(202).json({
          status: 'queued',
          message: 'Request queued for retry due to RPC error',
          txRef,
        });
      }

      // Success
      res.status(201).json({
        status: 'success',
        intentId: result.intentId,
        txHash: result.txHash,
        amount,
        countryCode,
        txRef,
      });
    } catch (error) {
      console.error('Error processing mint intent:', error);

      res.status(500).json({
        error: 'Internal Server Error',
        message: 'Failed to process mint intent',
      });
    }
  }
);

export default router;
