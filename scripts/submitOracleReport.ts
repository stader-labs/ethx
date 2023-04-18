import { ethers } from 'hardhat'

async function main() {
  const staderOracle = process.env.STADER_ORACLE ?? ''
  const staderOracleFactory = await ethers.getContractFactory('StaderOracle')
  const staderOracleInstance = await staderOracleFactory.attach(staderOracle)

  interface WithdrawnValidatorsStruct {
    reportingBlockNumber: number
    index: number
    pageNumber: number
    sortedPubkeys: string[]
  }

  const input: WithdrawnValidatorsStruct = {
    reportingBlockNumber: 8843200,
    index: 3,
    pageNumber:3,
    sortedPubkeys: ['0xa7354412be74304f5627a2883c16eae488b92612a21692d5e9fc3ada31281f83a5303e646157434962d3b2cec49503b2'],
  }

  const addKeyTx = await staderOracleInstance.submitMissedAttestationPenalties(input)

  console.log('submitted oracle report')
}
main()
