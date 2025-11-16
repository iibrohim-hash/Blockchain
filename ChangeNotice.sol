// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBatchRegistry.sol";

interface IMerkleAnchor {
    function submitRoot(uint256 batchId, bytes32 root) external;
    function getRoot(uint256 batchId) external view returns (bytes32);
    function verifyRoot(uint256 batchId, bytes32 proposedRoot) external view returns (bool);
}

contract ChangeNotice is Ownable {
    address public regulator;

    mapping(address => bool) public isSupplier;
    mapping(address => bool) public isRetailer;

    IBatchRegistry public batchRegistry;
    IMerkleAnchor public merkleAnchor;

    modifier onlySupplier() {
        require(isSupplier[msg.sender], "Not supplier");
        _;
    }

    modifier onlyRegulator() {
        require(msg.sender == regulator, "Not regulator");
        _;
    }

    modifier onlyRetailer() {
        require(isRetailer[msg.sender], "Not retailer");
        _;
    }

    enum NoticeType { CompositionChange, LabelingChange, ProcessChange, SupplierChange, SafetyAdvisory, Other }
    enum Severity { Minor, Major, Critical }
    enum Status { Draft, Submitted, Approved, Rejected, Superseded, Closed }

    struct Notice {
        uint256 id;
        uint256 batchId;
        address createdBy;
        uint48 createdAt;
        NoticeType noticeType;
        Severity severity;
        Status status;
        uint48 effectiveFrom;
        string summary;
        string detailsURI;
        bytes32 anchor;
        string regulatorNote;
    }

    uint256 public nextId = 1;
    mapping(uint256 => Notice) public notices;
    mapping(uint256 => uint256[]) private noticesByBatch;
    mapping(uint256 => mapping(address => bool)) public acknowledged;
    mapping(uint256 => uint256) public ackCount;

    event RoleUpdated(string role, address indexed account, bool enabled);
    event RegulatorChanged(address indexed newRegulator);
    event NoticeCreated(uint256 indexed id, uint256 indexed batchId, address indexed by);
    event NoticeSubmitted(uint256 indexed id, uint256 indexed batchId);
    event NoticeApproved(uint256 indexed id, uint256 indexed batchId, string regulatorNote);
    event NoticeRejected(uint256 indexed id, uint256 indexed batchId, string regulatorNote);
    event AnchorPushed(uint256 indexed id, uint256 indexed batchId, bytes32 anchor);

    constructor(address _batchRegistry, address _regulator, address _merkleAnchor)
        Ownable(msg.sender)
    {
        require(_batchRegistry != address(0), "batchRegistry=0");
        require(_regulator != address(0), "regulator=0");

        batchRegistry = IBatchRegistry(_batchRegistry);
        regulator = _regulator;

        if (_merkleAnchor != address(0)) {
            merkleAnchor = IMerkleAnchor(_merkleAnchor);
        }
    }

    function setRegulator(address _regulator) external {
    require(msg.sender == owner(), "Ownable: caller is not the owner");
    require(_regulator != address(0), "regulator=0");
    regulator = _regulator;
    emit RegulatorChanged(_regulator);
    }


    function setSupplier(address account, bool enabled) external {
    require(msg.sender == owner(), "Ownable: caller is not the owner");
    isSupplier[account] = enabled;
    emit RoleUpdated("SUPPLIER", account, enabled);
}


    function setRetailer(address account, bool enabled) external onlyOwner {
        isRetailer[account] = enabled;
        emit RoleUpdated("RETAILER", account, enabled);
    }

    function setMerkleAnchor(address _merkleAnchor) external onlyOwner {
        merkleAnchor = IMerkleAnchor(_merkleAnchor);
    }

    function createNotice(
        uint256 batchId,
        NoticeType noticeType,
        Severity severity,
        uint48 effectiveFrom,
        string calldata summary,
        string calldata detailsURI,
        bytes32 anchor
    ) external onlySupplier returns (uint256 id) {
        batchRegistry.getState(batchId);
        require(bytes(summary).length > 0, "Empty summary");

        id = nextId++;
        Notice storage n = notices[id];

        n.id = id;
        n.batchId = batchId;
        n.createdBy = msg.sender;
        n.createdAt = uint48(block.timestamp);
        n.noticeType = noticeType;
        n.severity = severity;
        n.status = Status.Draft;
        n.effectiveFrom = effectiveFrom;
        n.summary = summary;
        n.detailsURI = detailsURI;
        n.anchor = anchor;

        noticesByBatch[batchId].push(id);
        emit NoticeCreated(id, batchId, msg.sender);
    }
	 

    function submit(uint256 id) external {
    	Notice storage n = notices[id];
    	require(n.id == id, "Missing");

    	require(n.createdBy == msg.sender, "Not creator");
    	require(isSupplier[msg.sender], "Not supplier");
    	require(n.status == Status.Draft, "Not draft");

    	n.status = Status.Submitted;
    	emit NoticeSubmitted(id, n.batchId);
	}



    function approve(uint256 id, string calldata regulatorNote) external onlyRegulator {
        Notice storage n = notices[id];
        require(n.status == Status.Submitted, "Not submitted");

        n.status = Status.Approved;
        n.regulatorNote = regulatorNote;

        if (address(merkleAnchor) != address(0) && n.anchor != bytes32(0)) {
            merkleAnchor.submitRoot(n.batchId, n.anchor);
            emit AnchorPushed(id, n.batchId, n.anchor);
        }

        emit NoticeApproved(id, n.batchId, regulatorNote);
    }

    function reject(uint256 id, string calldata regulatorNote) external onlyRegulator {
        Notice storage n = notices[id];
        require(n.status == Status.Submitted, "Not submitted");
        n.status = Status.Rejected;
        n.regulatorNote = regulatorNote;

        emit NoticeRejected(id, n.batchId, regulatorNote);
    }

    function noticesForBatch(uint256 batchId) external view returns (uint256[] memory) {
        return noticesByBatch[batchId];
    }

    function getNotice(uint256 id) external view returns (Notice memory, uint256) {
        return (notices[id], ackCount[id]);
    }

    function anchorVerifiedOnMerkle(uint256 id) external view returns (bool) {
        Notice storage n = notices[id];
        if (address(merkleAnchor) == address(0) || n.anchor == bytes32(0)) return false;
        return merkleAnchor.verifyRoot(n.batchId, n.anchor);
    }
}
