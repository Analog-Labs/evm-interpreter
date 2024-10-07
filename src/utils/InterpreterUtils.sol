// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

type Interpreter is address;

/**
 * @dev Utilities for interact with the EVM interpreter.
 */
library InterpreterUtils {

    /**
     * @dev Error is thown when the gas left is insufficient to perform an
     * operation like check for EIP1153 supported.
     */
    error InsufficientGasLeft();

    /**
     * @dev Execute the interpreter in the context of the current contract.
     */
    function delegatecall(Interpreter interpreter, bytes memory data) internal returns (bytes memory result) {
        bool success;
        (success, result) = Interpreter.unwrap(interpreter).delegatecall(data);

        // Revert if the call failed.
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    /**
     * @dev Same as `execute`, except it uses staticcall instead delegate call, so the opcodes SSTORE,
     * TSTORE, CREATE, CREATE2, LOG*, etc, are disallowed.
     */
    function call(Interpreter interpreter, bytes memory data) internal view returns (bytes memory result) {
        bool success;
        (success, result) = Interpreter.unwrap(interpreter).staticcall(data);

        // Revert if the call failed.
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    /**
     * @dev Use the interpreter to check if the EVM supports EIP1153 transient storage.
     * obs: This cost 270 when the chains supports EIP1153, and 500 when it doesn't.
     */
    function supportsEIP1153(Interpreter interpreter) internal view returns (bool supported) {
        // Check of the gas left is enough to perform the operation, otherwise it
        // may return an false negative.
        if (gasleft() < 800) {
            revert InsufficientGasLeft();
        }
        assembly {
            // Executes: RETURNDATASIZE TLOAD
            mstore(0, 0x3d5c)
            supported := staticcall(500, interpreter, 0x1e, 0x02, 0, 0)
        }
    }

    /**
     * @dev Store in the interpreter, useful to bootstrap the interpreter before calling `compute`.
     */
    function sstore(Interpreter interpreter, bytes32 slot, bytes32 value) internal {
        // This call can be expensive if the slot empty, and interpreter address is cold.
        if (gasleft() < 30000) {
            revert InsufficientGasLeft();
        }
        assembly {
            // BUILD the following bytecode: PUSH32 <value> PUSH32 <slot> SSTORE
            mstore8(0, 0x7f)
            mstore(0x01, value)
            mstore8(0x21, 0x7f)
            mstore(0x22, slot)
            mstore8(0x42, 0x55)

            // Execute the bytecode
            let success := call(30000, interpreter, 0, 0, 0x43, 0, 0)
            if iszero(success) {
                revert(0, 0)
            }

            // cleanup first 3 bytes of free memory pointer at 0x40
            mstore(0x23, 0)
        }
    }

    /**
     * @dev Store an value in the current contract, useful to bootstrap the interpreter before executing it.
     */
    function sload(Interpreter interpreter, bytes32 slot) internal view returns (bytes32 value) {
        // This call can be expensive if the slot and interpreter are cold.
        if (gasleft() < 10000) {
            revert InsufficientGasLeft();
        }
        assembly {
            // BUILD the following code: PUSH32 <slot> SLOAD RETURNDATASIZE MSTORE PUSH1 0x20 RETURNDATASIZE RETURN
            mstore8(0, 0x7f)
            mstore(0x08, 0x543d5260203df3)
            mstore(0x01, slot)

            // Execute the code
            let success := staticcall(10000, interpreter, 0, 0x28, 0, 0x20)
            if iszero(success) {
                revert(0, 0)
            }
            value := mload(0)
        }
    }
}


