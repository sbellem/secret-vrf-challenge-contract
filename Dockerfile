FROM rust:1.70.0 as dev

ARG backtrace=1
ENV RUST_BACKTRACE ${backtrace}

RUN apt update && apt install -y \
      binaryen \
      clang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/contract

COPY . .


FROM dev as contract.wasm

RUN --mount=type=cache,target=/root/.cargo/registry \
      cargo clean && RUSTFLAGS='-C link-arg=-s' \
      cargo build --release --target wasm32-unknown-unknown --locked
RUN cp ./target/wasm32-unknown-unknown/release/*.wasm ./contract.wasm

FROM contract.wasm as contract.wasm.gz
RUN --mount=type=cache,target=/root/.cargo/registry \
      wasm-opt -Oz ./target/wasm32-unknown-unknown/release/*.wasm -o ./contract.wasm
RUN cat ./contract.wasm | gzip -n -9 > ./contract.wasm.gz

FROM scratch as artifact

COPY --from=contract.wasm /usr/src/contract/contract.wasm .
COPY --from=contract.wasm.gz /usr/src/contract/contract.wasm.gz .


FROM node:20 as integration-tests-deps
WORKDIR /usr/src/tests
COPY --from=contract.wasm /usr/src/contract/contract.wasm .
COPY --from=contract.wasm.gz /usr/src/contract/contract.wasm.gz .
RUN npm install -g npm@9.7.1
COPY tests .
#RUN npm install && npm install ts-node
RUN npm install


FROM integration-tests-deps as integration-tests
ARG SECRETNODE_HOSTNAME=secretnode
ENV LOCALSECRET "http://${SECRETNODE_HOSTNAME}"
CMD ["npx", "ts-node", "integration.ts"]

#RUN set -eux; \
#      \
#      "RUSTFLAGS='-C link-arg=-s' cargo build --release --target wasm32-unknown-unknown --locked"; \
#      "wasm-opt -Oz ./target/wasm32-unknown-unknown/release/*.wasm -o ./contract.wasm"; \
#      "cat ./contract.wasm | gzip -n -9 > ./contract.wasm.gz"; \
#      "rm -f ./contract.wasm";
