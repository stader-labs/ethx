import { ethers } from 'hardhat'

async function main() {
  const depositContract = process.env.ETH_DEPOSIT_CONTRACT ?? ''
  const depositContractFactory = await ethers.getContractFactory('DepositContract')
  const depositContractInstance = await depositContractFactory.attach(depositContract)

  const deposit = await depositContractInstance.deposit(
    '0xace47628f3dc6f0130522e7120be9ca19d21b164ebed5e708e17fe8389e9556a64fc7f4772c9db0361c74bf7aaae5dbe',
    '0x00ca24bd4a57ca9cd8738c146f489300747d2d3d53a035ed116890b64f5021e6',
    '0xb165fb155c8b584540822b68e9e3ef96e669161be8d48fa3d9f3395e85fcfddbf87912cd4f0bf30ee31ca20a8e12712d0bda10babc7efa16b79c8c91d4af926430c66051cc5417b4bb9dc03776ad28e0406ad74174ffe8780b9927d7d49be700',
    '0x261fb578c5343084e339f257214835c9db6fd46c549de08868e51fd0d084edd8',
    { value: ethers.utils.parseEther('1') }
  )

  console.log('deposited 1 ETH ')
}

main()
