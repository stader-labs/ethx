import deposit from '../../scripts/deposits/deposit0.json'

export async function registerValidator(staderStakePoolInstance: any) {
  await staderStakePoolInstance.depositEthToDepositContract(
    '0x' + deposit.pubkey,
    '0x' + deposit.withdrawal_credentials,
    '0x' + deposit.signature,
    '0x' + deposit.deposit_data_root
  )
}
