#!/usr/bin/env node
/**
 * Create client-cert.json for TEE mTLS client certificates
 * This file contains only the client certificates needed by the TEE
 * Uses tee-client.crt and tee-client.key (specific certificates for TEE)
 * 
 * Usage:
 *   node create-client-cert-json.js
 */

const fs = require('fs');
const path = require('path');

const certDir = __dirname;

// Read certificate files (TEE-specific client certificates)
let clientCert, clientKey, caCert;

try {
  clientCert = fs.readFileSync(path.join(certDir, 'tee-client.crt'), 'utf8');
  clientKey = fs.readFileSync(path.join(certDir, 'tee-client.key'), 'utf8');
  caCert = fs.readFileSync(path.join(certDir, 'ecs-ca.crt'), 'utf8');
} catch (error) {
  console.error('❌ Error reading certificate files:', error.message);
  console.error('   Make sure tee-client.crt, tee-client.key, and ecs-ca.crt exist in the certs directory');
  console.error('   These are TEE-specific client certificates');
  process.exit(1);
}

// Create client certificate JSON (only client certs, no server certs)
const clientCertJson = {
  client_cert: clientCert.trim(),
  client_key: clientKey.trim(),
  ca_cert: caCert.trim(),
};

// Write formatted JSON for easy viewing
const outputFile = path.join(certDir, 'client-cert.json');
fs.writeFileSync(outputFile, JSON.stringify(clientCertJson, null, 2));

console.log('✅ Created client-cert.json');
console.log(`   File: ${outputFile}`);
console.log('');
console.log('This file contains:');
console.log('  - client_cert: TEE client certificate (from tee-client.crt)');
console.log('  - client_key: TEE client private key (from tee-client.key)');
console.log('  - ca_cert: CA certificate to verify server certificate (from ecs-ca.crt)');
console.log('');
console.log('To use with Terraform:');
console.log('  This file will be read by nautilus-enclave/certs.tf');

