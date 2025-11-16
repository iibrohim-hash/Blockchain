// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract BatchRegistry {
    enum State {
        Registered, // 0
        InTransit,  // 1
        InStorage, // 2
        ForSale, // 3
        Sold,  // 4
        Recalled, // 5
        Expired // 6
    }

    struct Batch {
        address creator;
        uint64 createdAt;
        State state;
        string metadataURI;
        bytes32 metadataHash;
        bytes32 externalId;   // keccak256(ULID string) probably double check
        bool exists;
    }

    event CreateBatch(
        uint256 indexed batchId,
        address indexed creator,
        bytes32 indexed externalId,
        string metadataURI,
        bytes32 metadataHash
    );
    event Advance(uint256 indexed batchId, State from, State to);
    event Recall(uint256 indexed batchId, string reason);
    event MetadataUpdated(uint256 indexed batchId, string oldURI, bytes32 oldHash, string newURI, bytes32 newHash);

    error NotFound();
    error InvalidTransition(State from, State to);
    error AlreadyTerminal(State s);
    error Unauthorized();
    error ExternalIdUsed();
    error MetadataHashUsed();
    error BadInput();


    uint256 private nextId; // nextId for batches
    mapping(uint256 => Batch) private batches; // batches

    // uniqueness checks
    mapping(bytes32 => bool) private usedExternalId;
    mapping(bytes32 => bool) private usedContentHash;

    address public owner;
    address public operator; // allowed to advance/recall/update metadata

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    modifier onlyOperator() {
        if (msg.sender != operator) revert Unauthorized();
        _;
    }

    constructor(address initialOperator) {
        owner = msg.sender;
        operator = (initialOperator == address(0)) ? msg.sender : initialOperator;
    }

    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert BadInput();
        operator = newOperator;
    }

    function createBatch(
        bytes32 externalId,
        string calldata metadataURI,
        bytes32 metadataHash
    ) external returns (uint256 batchId) {
        if (externalId == bytes32(0) || metadataHash == bytes32(0)) revert BadInput();
        if (bytes(metadataURI).length == 0) revert BadInput();
        if (usedExternalId[externalId]) revert ExternalIdUsed();
        if (usedContentHash[metadataHash]) revert MetadataHashUsed();

        usedExternalId[externalId] = true;
        usedContentHash[metadataHash] = true;

        batchId = nextId++;
        batches[batchId] = Batch({
            creator: msg.sender,
            createdAt: uint64(block.timestamp),
            state: State.Registered,
            metadataURI: metadataURI,
            metadataHash: metadataHash,
            externalId: externalId,
            exists: true
        });

        emit CreateBatch(batchId, msg.sender, externalId, metadataURI, metadataHash);
    }

    function advanceLifecycle(uint256 batchId, State newState) external onlyOperator {
        Batch storage b = _mustGet(batchId);

        State from = b.state;
        if (_isTerminal(from)) revert AlreadyTerminal(from);
        if (from == newState) revert InvalidTransition(from, newState);
        if (!_validTransition(from, newState)) revert InvalidTransition(from, newState);

        b.state = newState;
        emit Advance(batchId, from, newState);
    }

    function recall(uint256 batchId, string calldata reason) external onlyOperator {
        Batch storage b = _mustGet(batchId);
        State from = b.state;
        if (_isTerminal(from)) revert AlreadyTerminal(from);

        b.state = State.Recalled;
        emit Recall(batchId, reason);
        emit Advance(batchId, from, State.Recalled);
    }

    /// Optional: if you must re-point the file, update both URI and hash atomically.
    function updateMetadata(
        uint256 batchId,
        string calldata newURI,
        bytes32 newHash
    ) external onlyOperator {
        if (bytes(newURI).length == 0 || newHash == bytes32(0)) revert BadInput();
        if (usedContentHash[newHash]) revert MetadataHashUsed();

        Batch storage b = _mustGet(batchId);
        (string memory oldURI, bytes32 oldHash) = (b.metadataURI, b.metadataHash);

        b.metadataURI = newURI;
        b.metadataHash = newHash;
        usedContentHash[newHash] = true;

        emit MetadataUpdated(batchId, oldURI, oldHash, newURI, newHash);
    }

    function getBatch(uint256 batchId)
        external
        view
        returns (
            address creator,
            uint64 createdAt,
            State state,
            string memory metadataURI,
            bytes32 metadataHash,
            bytes32 externalId,
            bool exists
        )
    {
        Batch storage b = batches[batchId];
        return (b.creator, b.createdAt, b.state, b.metadataURI, b.metadataHash, b.externalId, b.exists);
    }

    function isTerminalState(uint256 batchId) external view returns (bool) {
        return _isTerminal(_mustGet(batchId).state);
    }

    function _mustGet(uint256 batchId) internal view returns (Batch storage b) {
        b = batches[batchId];
        if (!b.exists) revert NotFound();
    }

    function _isTerminal(State s) internal pure returns (bool) {
        return (s == State.Sold || s == State.Recalled || s == State.Expired);
    }

    function _validTransition(State from, State to) internal pure returns (bool) {
        if (to == State.Expired) return true; // allow expiry from any non-terminal
        if (from == State.Registered) return (to == State.InTransit || to == State.InStorage);
        if (from == State.InTransit)  return (to == State.InStorage);
        if (from == State.InStorage)  return (to == State.ForSale);
        if (from == State.ForSale)    return (to == State.Sold);
        return false;
    }

    function getState(uint256 batchId) external view returns (uint8) {
         return uint8(_mustGet(batchId).state);
    }
}