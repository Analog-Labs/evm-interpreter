## EVM Interpreter

**Optimized on-chain EVM interpreter, run arbitrary code without deploying a contract!**

This is an EVM-interpreter written in pure EVM assembly, this is useful for the following:

-   **Extract Runtime Bytecode**: Run the `type(Contract).creationCode` on-chain to extract the `type(Contract).runtimeCode`, useful when the contract has immutables.
-   **Dynamic Contracts**: Upgrade specific parts of a smart-contract, without having to deploy a new contract.
-   **Account Abstraction**: Create a proxy that delegates the call to this interpreter with additional ownership verification, and use it instead your EOA account!

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
