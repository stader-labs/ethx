export async function onboardPermissionLessValidator(
  staderPermissionLessPoolInstance: any,
  rewardsAddress: any,
  id: any,
  amount: any
) {
  const deposit = require(`../../scripts/deposits/deposit${id}.json`)

  await staderPermissionLessPoolInstance.nodeDeposit(
    '0x' + deposit.pubkey,
    '0x' + deposit.signature,
    '0x' + deposit.deposit_data_root,
    rewardsAddress,
    'dummyPermissionLessNode',
    0,
    { value: ethers.utils.parseEther(amount) }
  )
}
