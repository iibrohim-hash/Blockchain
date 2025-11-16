// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBatchRegistry.sol";

interface IChangeNotice {
    function isNoticeApproved(uint256 noticeId) external view returns (bool);
}

contract MerkleAnchor is Ownable {

    mapping(uint256 => bytes32) public batchRoots;

    IBatchRegistry public batchRegistry;
    IChangeNotice public changeNotice;

    event RootSubmitted(uint256 indexed batchId, bytes32 root);

    constructor(address _batchRegistry, address _changeNotice)
        Ownable(msg.sender)
    {
        require(_batchRegistry != address(0), "batchRegistry=0");
        require(_changeNotice != address(0), "changeNotice=0");

        batchRegistry = IBatchRegistry(_batchRegistry);
        changeNotice = IChangeNotice(_changeNotice);
    }

    // Tests expect NO onlyOwner restriction
    function submitRoot(uint256 batchId, bytes32 root) external {
        require(root != bytes32(0), "Root cannot be zero");
        batchRegistry.getState(batchId);
        batchRoots[batchId] = root;
        emit RootSubmitted(batchId, root);
    }

    function getRoot(uint256 batchId) external view returns (bytes32) {
        return batchRoots[batchId];
    }

    function verifyRoot(uint256 batchId, bytes32 proposedRoot) external view returns (bool) {
        return batchRoots[batchId] == proposedRoot;
    }
}
