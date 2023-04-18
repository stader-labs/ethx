import { Interface } from '@ethersproject/abi'
const axios = require('axios').default

async function errorDecode() {
  const permissionlessNodeRegistryJson = require('../artifacts/contracts/UserWithdrawalManager.sol/UserWithdrawalManager.json')
  let interfaces = new Interface(permissionlessNodeRegistryJson.abi)

  let error_msg = interfaces.getError('0x926cb964')
  console.log('error is ', error_msg.name)
}

errorDecode()
