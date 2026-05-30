// Copyright 2025 RISC Zero, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// SPDX-License-Identifier: Apache-2.0

// -----------------------------------------------------------------------------
// Vendored verbatim from risc0/risc0-ethereum @ 3aa137844818f0f44e6b2962b6eb958f26d04be7
// (2026-05-12) — contracts/src/IRiscZeroSelectable.sol
// Dependency of RiscZeroGroth16Verifier.sol; cartesi/dave @ a4249a58 pin
// context is documented in StepVerifier.sol.
// -----------------------------------------------------------------------------

pragma solidity ^0.8.9;

/// @notice Selectable interface for RISC Zero verifier.
interface IRiscZeroSelectable {
    /// @notice A short key attached to the seal to select the correct verifier implementation.
    /// @dev The selector is taken from the hash of the verifier parameters. If two
    ///      receipts have different selectors (i.e. different verifier parameters), then it can
    ///      generally be assumed that they need distinct verifier implementations. This is used as
    ///      part of the RISC Zero versioning mechanism.
    ///
    ///      A selector is not intended to be collision resistant, in that it is possible to find
    ///      two preimages that result in the same selector. This is acceptable since it's purpose
    ///      to route a request among a set of trusted verifiers, and to make errors of sending a
    ///      receipt to a mismatching verifiers easier to debug. It is analogous to the ABI
    ///      function selectors.
    function SELECTOR() external view returns (bytes4);
}
