// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// =============================================================================
// StepVerifier.sol — REFERENCE SNIPPET ONLY
//
// Thin wrapper around the canonical RISC0 Groth16 verifier that the
// cartesi-machine v0.20.0 release packages alongside the RISC0 zkVM
// integration. Patterned after the verifier used by cartesi/dave for fraud
// proofs. NOT meant to be deployed as-is from this repo.
//
// Pinned to cartesi/dave @ a4249a58080ef713177e18a5b37af7c2af96d8ae (2026-03-10) —
// verifier interface above is copied verbatim from
// risc0/risc0-ethereum @ 3aa137844818f0f44e6b2962b6eb958f26d04be7 (2026-05-12),
// contracts/src/IRiscZeroVerifier.sol. Reconnaissance note: cartesi/dave at
// this commit does NOT ship a RISC0 Solidity verifier — dave implements the
// PRT (Permissionless Refereed Tournament) interactive fraud-proof protocol
// (see prt/contracts/src/state-transition/RiscVStateTransition.sol). The
// "ZK fallback" path discussed in the slides (cartesi/machine-emulator
// v0.20.0, PR #343) reuses RISC Zero's canonical IRiscZeroVerifier interface,
// which is what we vendor here.
//
// The contract intentionally has *no* business logic; its sole job is to:
//   1. Forward the receipt (`seal`) + journal digest into the RISC0 verifier
//      address baked in at deploy time.
//   2. Insist that the journal commits to (pre_state_hash, post_state_hash)
//      matching what the caller supplies.
//
// This shape mirrors how DEAAP's Multi-BU Cartesi rollup would consume
// state-transition proofs once the zkRollup option is wired in.
// =============================================================================

import {IRiscZeroVerifier} from "./IRiscZeroVerifier.sol";

contract StepVerifier {
    /// @notice Canonical RISC Zero verifier deployed once per chain
    ///         (e.g. 0x... for Ethereum mainnet; see RISC Zero deployment docs).
    IRiscZeroVerifier public immutable RISC_ZERO_VERIFIER;

    /// @notice Image id of cartesi-risc0-guest-step-prover.bin
    ///         (constant; matches the .txt asset shipped in v0.20.0 release).
    bytes32 public immutable STEP_PROVER_IMAGE_ID;

    constructor(IRiscZeroVerifier verifier, bytes32 imageId) {
        RISC_ZERO_VERIFIER = verifier;
        STEP_PROVER_IMAGE_ID = imageId;
    }

    /// @notice Verify that a single Cartesi-machine mcycle step transitioned
    ///         from `preStateHash` to `postStateHash`.
    /// @dev    Reverts via the RISC Zero verifier if the seal does not check
    ///         out, or via `JournalMismatch` if the journal commitment is
    ///         inconsistent with the supplied pre/post hashes.
    function verifyStep(
        bytes calldata seal,
        bytes32 preStateHash,
        bytes32 postStateHash
    ) external view returns (bool) {
        // The Cartesi guest commits keccak256(abi.encode(pre, post)) into its
        // journal. This must match the digest we hand to the RISC0 verifier.
        bytes32 journalDigest = sha256(abi.encode(preStateHash, postStateHash));

        RISC_ZERO_VERIFIER.verify(seal, STEP_PROVER_IMAGE_ID, journalDigest);

        return true;
    }
}
