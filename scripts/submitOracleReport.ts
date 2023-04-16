import { ethers } from 'hardhat'

async function main() {
  const staderOracle = process.env.STADER_ORACLE ?? ''
  const staderOracleFactory = await ethers.getContractFactory('StaderOracle')
  const staderOracleInstance = await staderOracleFactory.attach(staderOracle)

  interface WithdrawnValidatorsStruct {
    reportingBlockNumber: number
    nodeRegistry: string
    sortedPubkeys: string[]
  }

  const input: WithdrawnValidatorsStruct = {
    reportingBlockNumber: 8840650,
    nodeRegistry: '0x7a9F54B8B6Bb1DBED83e16Bb34257397358752df',
    sortedPubkeys: [
      '0xa7354412be74304f5627a2883c16eae488b92612a21692d5e9fc3ada31281f83a5303e646157434962d3b2cec49503b2',
    ],
  }

  const addKeyTx = await staderOracleInstance.submitWithdrawnValidators(input)

  console.log('submitted oracle report')
}
main()
