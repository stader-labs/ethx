const { SSVKeys, KeyShares } = require('ssv-keys');
const path = require('path');
const fsp = require('fs').promises;

// These would probably come from your DApp
const operatorKeys = ["LS0tLS1CRUdJTiBSU0EgUFVCTElDIEtFWS0tLS0tCk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBc3BNREoxTWlPMFFmYWtGeTVqSzYKZDNnd1BOajN6WG1yMmtQS1U3R3VVb0pyQUF2NEI2d1RmZnJtdlFwY2JjczAwc0o4ZWtsb1NwME8wK0xJcHUrZgphVkRuUm5tK1ZBSFI4VTB4NWRPT2p1RzVybE1RaUJrQjE5ekErOTJSTDBOT2FiR1dMUUN6R0NVYnpCcnNJTXNVCnNrbUhBRHFabEY5RWI3a1ZWNVVNaEF1cUhGRkJwODJqMHRCZ1JOK0pUeU5NVGlMa2dIZzZSZ1AzSDIxOXVxNDYKb0lCVmk2ZllXZ3JEM0FDS2JVdEVxL1ZGVE1zWUhWakYvQTdFMDg1R2VhUnNnVmJKdzlSSjVJUkRKMGFpcStPOAplOU5QU3JYd2c5Uit1WEJGSWFrYkYwc0ZENE9nZk84YUFWNlJ1cHIyUFJOOXhpcmZlbTBqVzNQQjVEWjAxNzQrCjJ3SURBUUFCCi0tLS0tRU5EIFJTQSBQVUJMSUMgS0VZLS0tLS0K", 
"LS0tLS1CRUdJTiBSU0EgUFVCTElDIEtFWS0tLS0tCk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBcThoVEFyQVEwYkRxNEI3NjI5SEQKNnBZSUJqSGhsT3RIUTJtTkpBNENTWnVYZVNkRU1wY3l1U3l5VE80MTJSKzlPdWZwdS9QUnpiM2J1YVplWUU4bgpXbnVzQ3NDQUxnNW8wd0dIOFZ0U3FzWmptN0xQeGtpR0NZQnMyZjFxUjZveUM0SXc0ZzlDWHloYmE0T0xuZlBNCk1oaGJKYUl1RTRUazZyVHpXSGQ2YVlmOXY2WjVvMXp5K2ZTUTlnOHRJNnJLNmx6Q20vbkFucDQrblp0NDZzR0kKcTZiWk1WUzM0Q3FDSHFzMmk2dnh0dy9sTHNXMlFzVnEzaVRheFMvR0k5VUZtQmVnUnVnYmNjWVhiNlIrNS94RQpCL0dCTkhxSEFNRjBvd0JGdmVHc21BcXVEZWdpb0t1c2pVTXNmVm5YSTBmdGJPbXQ3NXB1QnNiZDVyNjhNdkdwCkR3SURBUUFCCi0tLS0tRU5EIFJTQSBQVUJMSUMgS0VZLS0tLS0K",
 "LS0tLS1CRUdJTiBSU0EgUFVCTElDIEtFWS0tLS0tCk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBb0Zwcmdmc09tVmNmK085NUR5ODEKUi93YUZoWUJta1BJWVhmdUpFTzdYN2tWUlhXa3BlMWM4dFFveE5zdEJYYm95d1g3aWpmcWZDRjZGd3VVZVN1WApESXZtNGl0aXpMTTJwY3ZsWDNBSTBNLzZoTElDV21YTGsyekxydU9sVGRwMjJYTFVTWU12VEVnRVRMT0NQZ3k0CjM0bXA1Rm5xcXhtb2xQSHhCa3BzOTNHOWswYTFSZGllRVJVZDdqMmpEUjNRaVpwNHkwTDFqRitubzdhbnZOSmUKVUM2SXExMnNWUldscmM0VExOUS9iOHNLejJ4NS9WQnBNalpzQnF2VS9WaE1kc2hacmdlWXNNNm43bHRwaG5NQQpzcS9CNk9IRVg5dXg5MEV0Nmk1TDBnWFZNQ3paN29ZRlBWUk03RjBmdko3cHRQVkhtMTUyZHdHekJNQnVnazFPCkhRSURBUUFCCi0tLS0tRU5EIFJTQSBQVUJMSUMgS0VZLS0tLS0K",
  "LS0tLS1CRUdJTiBSU0EgUFVCTElDIEtFWS0tLS0tCk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBcGtEdGhmc3Zka1JXWFBJdFBWUS8KVTBRVlNzcjBPWEMwWlBYL3NrTjNjbTRDUXN4WDgzL2drNGxoUGRQQys4OTVGcDliWmN3cXZNSnRFRTZvUlVpNgpyWGgrdUN0aUFtVG9EMFFuYld2eER0bEhWZFY3NkdnSDIvZE5ORTVPRDFjamZhVlIvaW9YUWNCZGVlSzB3L2dZCm9NL1pValNya1lDQXNORmx3SHFwYlQxUFM2aGdoY0w1cjN2TEp2RXkrMCt1clYxYjh0blh0MEl1aUxWTU1SRDkKSlptRW9ieUhtMGd6ZnZjOGgyaC8wUDlLbVN5Q3NCSUk3VG5XcUZ6OUFvZWp5K3ltdUZYSHBCcHNlbUQ2VGJRVAppeHpQcm9INkNpQVpjRWlhZFRsemd5dEF2ZXhVQlB1STNlaDhVSmtsYzkza2NGQU1NWCtnejNDYTRrYWM1MlFUCnlRSURBUUFCCi0tLS0tRU5EIFJTQSBQVUJMSUMgS0VZLS0tLS0K"];
const operatorIds = [181, 184, 185, 186];
// These can be either provided by the user (Staking-as-a-Service) or auto-generated (Staking Pool)
const keystore = require('./keystore4.json');
const keystorePassword = '';

// The nonce of the owner within the SSV contract (increments after each validator registration), obtained using the ssv-scanner tool
const TEST_OWNER_NONCE = 3;
// The cluster owner address
const TEST_OWNER_ADDRESS = '0xc97A3092dd785e1b65155Dd56664dD358B981e2d';

const getKeySharesFilePath = () => {
  return `${path.join(process.cwd(), 'data')}${path.sep}keyshares.json`;
};

/**
 * This is more complex example demonstrating usage of SSVKeys SDK together with
 * KeyShares file which can be useful in a different flows for solo staker, staking provider or web developer.
 */
async function main() {
  // 1. Initialize SSVKeys SDK and read the keystore file
  const ssvKeys = new SSVKeys();
  const { publicKey, privateKey } = await ssvKeys.extractKeys(keystore, keystorePassword);

  const operators = operatorKeys.map((operatorKey: any, index: number) => ({
    id: operatorIds[index],
    operatorKey,
  }));
  
  // 2. Build shares from operator IDs and public keys
  const encryptedShares = await ssvKeys.buildShares(privateKey, operators);

  const keyShares = new KeyShares();
  await keyShares.update({ operators });
  await keyShares.update({ ownerAddress: TEST_OWNER_ADDRESS, ownerNonce: TEST_OWNER_NONCE, publicKey });

  // 3. Build final web3 transaction payload and update keyshares file with payload data
  const payload = await keyShares.buildPayload({
    publicKey,
    operators,
    encryptedShares,
  }, {
    ownerAddress: TEST_OWNER_ADDRESS,
    ownerNonce: TEST_OWNER_NONCE,
    privateKey
  });

  console.log('payload is ', payload)

  // Most times, you'd want to save the result in a file
//   await fsp.writeFile(getKeySharesFilePath(4), keyShares.toJson(), { encoding: 'utf-8' });
}

void main();