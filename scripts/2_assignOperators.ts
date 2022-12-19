export async function assignOperators() {
  const axios = require('axios').default

  const operatorReq = 'https://api.ssv.network/api/v1/operators?page=1&perPage=5&ordering=id%3Aasc'

  const operatorsList = await axios.get(operatorReq)

  const newOperators = []
  let operatorsSet = []

  let operatorCount = 0

  for (const operator of operatorsList.data.operators) {
    if (operatorCount <= 3) {
      operatorsSet.push({
        operatorId: operator.id,
        operatorKey: operator.public_key,
      })
      operatorCount++
    } else {
      operatorCount = 0
      newOperators.push(operatorsSet)
      operatorsSet = []
    }
  }

  return newOperators
}
