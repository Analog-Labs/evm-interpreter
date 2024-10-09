// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import {Interpreter, InterpreterUtils} from "./InterpreterUtils.sol";

/**
 * @dev Utilities for branchless operations, useful when a constant gas cost is required.
 */
abstract contract Executor {
    using InterpreterUtils for Interpreter;

    Interpreter internal immutable INTERPRETER;

    constructor(address interpreter) {
        INTERPRETER = Interpreter.wrap(interpreter);
    }

    /**
     * @dev perform a staticcall to the interpreter contract.
     * obs: SSTORE, TSTORE, CREATE, CREATE2, LOG*, CALL opcodes are disallowed.
     */
    function _execute(bytes memory data) internal returns (bytes memory result) {
        return INTERPRETER.delegatecall(data);
    }

    /**
     * @dev Execute to the interpreter contract.
     */
    function _call(bytes memory data) internal view returns (bytes memory result) {
        return INTERPRETER.call(data);
    }

    /**
     * @dev Encode a PUSH instruction.
     */
    function _sload(bytes32 slot) internal view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    /**
     * @dev Encode a PUSH instruction.
     */
    function _sstore(bytes32 slot, bytes32 value) internal {
        assembly {
            sstore(slot, value)
        }
    }
}
