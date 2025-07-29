const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const testApiHealth = async function () {
    const postData = {
        "query": "${test_query}",
        "session_id": "health-check-" + Date.now()
    };

    let requestOptionsStep = {
        hostname: '${api_endpoint}'.replace('https://', '').replace('http://', ''),
        method: 'POST',
        path: '/query',
        port: 443,
        protocol: 'https:',
        body: JSON.stringify(postData),
        headers: {
            'Content-Type': 'application/json',
            'User-Agent': synthetics.getCanaryUserAgentString()
        }
    };

    requestOptionsStep['headers']['Content-Length'] = Buffer.byteLength(requestOptionsStep.body);

    let stepConfig = {
        includeRequestHeaders: true,
        includeResponseHeaders: true,
        restrictedHeaders: [],
        includeRequestBody: true,
        includeResponseBody: true
    };

    await synthetics.executeHttpStep('testApiHealth', requestOptionsStep, function (res) {
        return new Promise((resolve) => {
            if (res.statusCode < 200 || res.statusCode >= 300) {
                throw new Error("Failed API health check with status: " + res.statusCode);
            }
            
            let responseBody = '';
            res.on('data', (chunk) => {
                responseBody += chunk;
            });
            
            res.on('end', () => {
                log.info('Health check successful');
                log.info('Response: ' + responseBody);
                resolve();
            });
        });
    }, stepConfig);
};

exports.handler = async () => {
    return await synthetics.executeStep('testApiHealth', testApiHealth);
};