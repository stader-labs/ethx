export async function onboardPermissionedValidator(staderStakePoolInstance: any, rewardsAddress: any, id: any) {
  const deposit = require(`../../scripts/deposits/deposit${id}.json`)

  await staderStakePoolInstance.registerPermissionValidator(
    '0x' + deposit.pubkey,
    '0x' + deposit.signature,
    '0x' + deposit.deposit_data_root,
    rewardsAddress,
    'dummyNode',
    1
  )
}
