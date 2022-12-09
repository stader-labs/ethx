import { encode } from 'js-base64'

export async function assignOperators() {
  const axios = require('axios').default

  // const operatorReq =
  //   "https://api.ssv.network/api/v1/operators?page=1&perPage=5&ordering=id%3Aasc";

  // const operatorsList = await axios.get(operatorReq);

  const newOperators = []
  let operatorsSet = []

  // let operatorCount = 0;

  // for (const operator of operatorsList.data.operators) {
  //   if (operatorCount <= 3) {
  //     operatorsSet.push({
  //       operatorId: operator.id,
  //       operatorKey: operator.public_key,
  //     });
  //     operatorCount++;
  //   } else {
  //     operatorCount = 0;
  //     newOperators.push(operatorsSet);
  //     operatorsSet = [];
  //   }
  // }
  operatorsSet.push({
    operatorId: 1,
    operatorKey:
      'LS0tLS1CRUdJTiBSU0EgUFVCTElDIEtFWS0tLS0tCk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBMVg2MUFXY001QUNLaGN5MTlUaEIKby9HMWlhN1ByOVUralJ5aWY5ZjAyRG9sd091V2ZLLzdSVUlhOEhEbHBvQlVERDkwRTVQUGdJSy9sTXB4RytXbwpwQ2N5bTBpWk9UT0JzNDE5bEh3TzA4bXFja1JsZEg5WExmbmY2UThqWFR5Ym1yYzdWNmwyNVprcTl4U0owbHR1CndmTnVTSzNCZnFtNkQxOUY0aTVCbmVaSWhjRVJTYlFLWDFxbWNqYnZFL2cyQko4TzhaZUgrd0RzTHJiNnZXQVIKY3BYWG1uelE3Vlp6ZklHTGVLVU1CTTh6SW0rcXI4RGZ4SEhSeVU1QTE3cFU4cy9MNUp5RXE1RGJjc2Q2dHlnbQp5UE9BYUNzWldVREI3UGhLOHpUWU9WYi9MM1lnSTU4bjFXek5IM0s5cmFreUppTmUxTE9GVVZzQTFDUnhtQ2YzCmlRSURBUUFCCi0tLS0tRU5EIFJTQSBQVUJMSUMgS0VZLS0tLS0K',
  })
  operatorsSet.push({
    operatorId: 2,
    operatorKey:
      'LS0tLS1CRUdJTiBSU0EgUFVCTElDIEtFWS0tLS0tCk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBeUtVWTVEUmZZREljengzcjhVY0UKTlpFMFdIQXFuV2FIRjZYRlUydVdObjVOVE94Zkt4ZmZaLzkyeVE1citQVkJPRmQrcHhILzI2QXJVT3dNL1lBRQpRbDZ0VzBtc1FqdUtIU1Q4aUtvTDRTNUt0aDNoeTBqeFRHR1ZZaWdjWG1vRURjd2YxaG8wdWRxRmlEN3dFWXN1CmZHa2E2U1ZQNnBab1NMaU9HZFRKUWVzVDI5WEVCdDZnblhMaFB1MER2K0xsQUJJQ1pqWEFTZWtpSFVKUHRjYlgKRjZFL0lScGpkWHVNSmUyOXZDcmZudXhWWk93a1ptdzJXdGljYlNDOVJpSFRYWUQ1dnVGakZXRHNZMERHUDhzOAoyc1haVHdsNWl4dEhlUWM2N1lLRFN6YU1MNnY1VUVZblhUTzZzNHFVSWVnTXJwZjd3S0xGVWxqRTMwbnNIaVBUCjBRSURBUUFCCi0tLS0tRU5EIFJTQSBQVUJMSUMgS0VZLS0tLS0K',
  })
  operatorsSet.push({
    operatorId: 3,
    operatorKey:
      'LS0tLS1CRUdJTiBSU0EgUFVCTElDIEtFWS0tLS0tCk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBNWVUNUwwV0h6ZTdyTWZPb2xtVHMKdWtIQ2E4K3dtbUw2OTFJQ1RpREE1UkJ1TkxqSVQ2WkE0YzMxcVRIY3FBVHl5eVkwLzk3R3lKZ2doYnlFR2RoZQovalh6aWVTOXJ2RytJVGF1QjhMVlhkekxGYVQxWEZWeFlnN2x2TlB4OURPL1ZoRkhkWWxnT3I2d0RtV3FjRGo3ClhWUWFOWEFtRng3NjVQNTlXNXZzVGRXVWFHRWxXSm93SkZKdnc2UlRISkZ1TVhjSzZVaWJ0cUZMSmJwOW5kdUgKQjlLSzNWcmYrZmtJOWRBZ2txRDFHOElxQ0tKMVl3bjUyeGxxbTRCNitOOGZUZE1MS1JucWpFZmRzV1dwMFVzMQpLTW9vSXcyc3BoaXAzUFpNYnJaaU0wNjJ2ZUo0U3ovYjBObWdPTnhTd0JJTnNxcG54QjhFUVQxSTNjNklqNXhhCm5RSURBUUFCCi0tLS0tRU5EIFJTQSBQVUJMSUMgS0VZLS0tLS0K',
  })
  operatorsSet.push({
    operatorId: 4,
    operatorKey:
      'LS0tLS1CRUdJTiBSU0EgUFVCTElDIEtFWS0tLS0tCk1JSUJJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBdXZleUpUMURwM21mQ3FRTUora2YKZHdhV0d1bkRURUFaWmNTOHdtUTJBcjU1bE5venl5cHRwb1lGSTgxaW1RSmpwdVV0akR2am15RDRQSmt1SzFXRQovZG9TSzFraWlTSEYvZFBaeE5ZT2swMlRiTGIvTXBjMG12VE1nZmRsVDBoTlVOWDZIMnJzZzNlc2NEOStENEdDCmxtZGpCdmdxUDQydXdDbFlQUVhuN3Z6OWlOOEpXdEFtd1JkQ25USkZ6M2tYSEFPVGMyMjJGYXp4ZGJVNEVPYkIKVmJNejd2UXRmMWtNSGtacEh5UXNpL3F0WmhQaThtTlNQTWpMTDBtcmc4Ly9xVjIyeEVPNENmSHFKZkZOWEhKVwpEbU85M2h2QXE2dDFZOGN5UVZkSGZ2WEp5VzRxR29MY25HZzV1S2ZSYWVCSSt1aXFSeExOL2dtTnA2RzdpZVNkCkl3SURBUUFCCi0tLS0tRU5EIFJTQSBQVUJMSUMgS0VZLS0tLS0K',
  })
  newOperators.push(operatorsSet)

  return newOperators
}
