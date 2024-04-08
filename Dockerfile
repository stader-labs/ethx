FROM ghcr.io/collectivexyz/foundry:latest

ARG PROJECT=ethx
WORKDIR /workspaces/${PROJECT}
RUN chown -R foundry:foundry .
COPY --chown=foundry:foundry . .
ENV USER=foundry
USER foundry
ENV PATH=${PATH}:~/.cargo/bin:/usr/local/go/bin

RUN python3 -m pip install slither-analyzer --break-system-packages

RUN yamlfmt -lint .github/workflows/*.yml

RUN npm ci --frozen-lockfile
RUN npm run prettier:check
# RUN slither .
# RUN npm run lint
RUN forge test -v
RUN forge geiger --check contracts/*.sol contracts/*/*.sol