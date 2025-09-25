/**
 * Netlify Function - Health Check
 * Deploy: netlify deploy --prod
 */

exports.handler = async (event, context) => {
  if (event.httpMethod !== 'GET') {
    return {
      statusCode: 405,
      body: JSON.stringify({ error: 'Method not allowed' })
    };
  }

  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    },
    body: JSON.stringify({
      status: 'healthy',
      service: 'secret-sync-relay',
      timestamp: new Date().toISOString(),
      provider: 'netlify',
      region: process.env.AWS_REGION || 'unknown'
    })
  };
};