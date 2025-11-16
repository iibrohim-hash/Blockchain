// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBatchRegistry {
    function getState(uint256 batchId) external view returns (uint8);
}
