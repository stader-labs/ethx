import deposit from '../../scripts/deposits/deposit0.json'

export async function onboardPermissionedValidator(staderStakePoolInstance: any) {
  await staderStakePoolInstance.registerPermissionValidator(
    '0x' + deposit.pubkey,
    '0x' + deposit.signature,
    '0x' + deposit.deposit_data_root,
    staderStakePoolInstance.address,
    'dummyNode',
    10
  )
}
