import { Router } from 'express';
import { createHmac, timingSafeEqual } from 'crypto';
import { executeMint } from '../blockchain.js';
import { checkCompliance } from '../blockchain.js';
import { config } from '../config.js';
import { addToRetryQueue } from '../services/retry.js';

const router = Router();

/**
 * Verify M-PESA webhook signature
 */
function verifyMpesaSignature(payload, signature, timestamp) {
  const message = JSON.stringify(payload) + timestamp.toString();
  const hmac = createHmac('sha256', config.secrets.mpesaWebhookSecret);
  hmac.update(message);
  const expected = hmac.digest('hex');

  try {
    const signatureBuffer = Buffer.from(signature, 'hex');
    const expectedBuffer = Buffer.from(expected, 'hex');

    if (signatureBuffer.length !== expectedBuffer.length) {
      return false;
    }

    return timingSafeEqual(signatureBuffer, expectedBuffer);
  } catch (error) {
    return false;
  }
}

/**
 * POST /callbacks/mpesa
 * Handle M-PESA payment confirmation webhook
 */
router.post('/callbacks/mpesa', async (req, res) => {
  try {
    const signature = req.headers['x-mpesa-signature'];
    const timestamp = parseInt(req.headers['x-timestamp'], 10);

    // Verify signature
    if (!signature || !timestamp) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Missing signature or timestamp',
      });
    }

    if (!verifyMpesaSignature(req.body, signature, timestamp)) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Invalid signature',
      });
    }

    const { intentId, txRef, userAddress, amount } = req.body;

    if (!intentId || !txRef || !userAddress) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'Missing required fields: intentId, txRef, userAddress',
      });
    }

    // Check user compliance before executing (with retry on failure)
    let isCompliant;
    try {
      isCompliant = await checkCompliance(userAddress);
    } catch (error) {
      // RPC failure during compliance check - add to retry queue
      console.error('Failed to check compliance:', error.message);

      addToRetryQueue(intentId, 'execute', {
        intentId,
        txRef,
        userAddress,
        amount,
      });

      return res.status(202).json({
        status: 'queued',
        message: 'Compliance check failed, queued for retry',
        intentId,
      });
    }

    if (!isCompliant) {
      console.log(`User ${userAddress} is not compliant, skipping mint execution`);

      return res.status(200).json({
        status: 'rejected',
        message: 'User is not compliant',
        intentId,
      });
    }

    // Execute mint with retry on failure
    try {
      const result = await executeMint(intentId);

      res.status(200).json({
        status: 'success',
        intentId,
        txHash: result.txHash,
      });
    } catch (error) {
      // RPC failure or mint execution error - add to retry queue
      console.error('Failed to execute mint:', error.message);

      addToRetryQueue(intentId, 'execute', {
        intentId,
        txRef,
        userAddress,
        amount,
      });

      res.status(202).json({
        status: 'queued',
        message: 'Execution queued for retry',
        intentId,
      });
    }
  } catch (error) {
    console.error('Error processing M-PESA callback:', error);

    res.status(500).json({
      error: 'Internal Server Error',
      message: 'Failed to process callback',
    });
  }
});

export default router;
