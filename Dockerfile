FROM ghcr.io/collectivexyz/foundry:latest

RUN python3 -m pip install slither-analyzer --break-system-packages

ARG PROJECT=ethx
WORKDIR /workspaces/${PROJECT}

ENV USER=foundry
USER foundry
ENV PATH=${PATH}:~/.cargo/bin:/usr/local/go/bin

RUN chown -R foundry:foundry .

COPY --chown=foundry:foundry package.json .
COPY --chown=foundry:foundry package-lock.json .
COPY --chown=foundry:foundry tsconfig.json .

RUN npm ci --frozen-lockfile

COPY --chown=foundry:foundry . .

RUN yamlfmt -lint .github/workflows/*.yml

RUN forge install
RUN npm run prettier:check
# RUN slither .
# RUN npm run lint
RUN forge test -v
RUN forge geiger --check contracts/*.sol contracts/*/*.sol
