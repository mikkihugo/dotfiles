/**
 * Vercel Serverless Function - Health Check
 * Deploy: vercel --prod
 */

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  return res.status(200).json({
    status: 'healthy',
    service: 'secret-sync-relay',
    timestamp: new Date().toISOString(),
    provider: 'vercel',
    region: process.env.VERCEL_REGION || 'unknown'
  });
}