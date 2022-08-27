# BetWei Contracts

Crear el archivo `.env` en el directorio principal del proyecto. Puede copiar el archivo `.env.example`
  ```
    cp .env.example .env
  ```

### Commands hardhat
  ```shell
    npx hardhat help
    npx hardhat test
    GAS_REPORT=true npx hardhat test
    npx hardhat node
    npx hardhat run scripts/deploy.ts
  ```

#### Verify contract
  ```sh
    npx hardhat verify --network {network} {contract_address} {...contract_args}
  ```
