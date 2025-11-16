// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/ChangeNotice.sol";
import "../src/BatchRegistry.sol";
import "../src/MerkleAnchor.sol";

contract ChangeNoticeTest is Test {

    ChangeNotice notice;
    BatchRegistry registry;
    MerkleAnchor anchor;

    address owner = address(0xA1);
    address regulator = address(0xB2);
    address supplier = address(0xC3);
    address retailer = address(0xD4);
    address random = address(0xE5);

    uint256 batchId;

    function setUp() public {
        vm.startPrank(owner);

        registry = new BatchRegistry(owner);
        anchor = new MerkleAnchor(address(registry), address(0x123123));

        notice = new ChangeNotice(address(registry), regulator, address(anchor));

        notice.setSupplier(supplier, true);
        notice.setRetailer(retailer, true);

        batchId = registry.createBatch(
            keccak256("ext-1"),
            "metadata.json",
            keccak256("hash-1")
        );

        vm.stopPrank();
    }

    // Constructor
    function testConstructorInitializesCorrectly() public {
        assertEq(address(notice.batchRegistry()), address(registry));
        assertEq(notice.regulator(), regulator);
        assertEq(notice.owner(), owner);
    }

    // Role tests
    function testSetSupplier() public {
        vm.prank(owner);
        notice.setSupplier(address(111), true);
        assertTrue(notice.isSupplier(address(111)));
    }

    function testNonOwnerCannotSetSupplier() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(random);
        notice.setSupplier(address(222), true);
    }

    function testSetRegulator() public {
        vm.prank(owner);
        notice.setRegulator(address(777));
        assertEq(notice.regulator(), address(777));
    }

    function testNonOwnerCannotSetRegulator() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(random);
        notice.setRegulator(address(1234));
    }

    // Create notice
    function testCreateNotice() public {
        vm.startPrank(supplier);

        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Major,
            uint48(block.timestamp + 1000),
            "Summary text",
            "ipfs://details",
            keccak256("root123")
        );

        (ChangeNotice.Notice memory n, ) = notice.getNotice(id);
        assertEq(n.batchId, batchId);
        assertEq(n.createdBy, supplier);
        assertEq(n.summary, "Summary text");
        assertEq(uint(n.status), uint(ChangeNotice.Status.Draft));

        vm.stopPrank();
    }

    function testCreateNoticeFailsIfNotSupplier() public {
        vm.startPrank(random);

        vm.expectRevert("Not supplier");
        notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Major,
            uint48(block.timestamp + 1000),
            "Summary text",
            "ipfs://details",
            keccak256("root123")
        );

        vm.stopPrank();
    }

    function testCreateNoticeFailsIfEmptySummary() public {
        vm.startPrank(supplier);

        vm.expectRevert("Empty summary");
        notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Major,
            uint48(block.timestamp + 1000),
            "",
            "ipfs://details",
            keccak256("root123")
        );

        vm.stopPrank();
    }

    // Submit
    function testSubmitSuccess() public {
        vm.startPrank(supplier);

        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Major,
            uint48(block.timestamp),
            "Summary",
            "uri",
            bytes32(0)
        );
        notice.submit(id);

        (ChangeNotice.Notice memory n, ) = notice.getNotice(id);
        assertEq(uint(n.status), uint(ChangeNotice.Status.Submitted));

        vm.stopPrank();
    }

    function testSubmitRevertsIfNotCreator() public {
        vm.startPrank(supplier);
        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Major,
            uint48(block.timestamp),
            "Summary",
            "uri",
            bytes32(0)
        );
        vm.stopPrank();

        vm.startPrank(random);
        vm.expectRevert("Not creator");
        notice.submit(id);
        vm.stopPrank();
    }

    function testSubmitRevertsIfNotDraft() public {
        vm.startPrank(supplier);
        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Major,
            uint48(block.timestamp),
            "Summary",
            "uri",
            bytes32(0)
        );
        notice.submit(id);

        vm.expectRevert("Not draft");
        notice.submit(id);

        vm.stopPrank();
    }

    // Approve
    function testApproveSuccessAndAnchorPushed() public {
        vm.startPrank(supplier);

        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Critical,
            uint48(block.timestamp),
            "Sum",
            "uri",
            keccak256("anchor")
        );
        notice.submit(id);
        vm.stopPrank();

        vm.startPrank(regulator);
        notice.approve(id, "OK");

        (ChangeNotice.Notice memory n, ) = notice.getNotice(id);
        assertEq(uint(n.status), uint(ChangeNotice.Status.Approved));
        assertEq(n.regulatorNote, "OK");

        vm.stopPrank();
    }

    function testApproveRevertsIfNotSubmitted() public {
        vm.startPrank(supplier);
        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Critical,
            uint48(block.timestamp),
            "Sum",
            "uri",
            keccak256("anchor")
        );
        vm.stopPrank();

        vm.startPrank(regulator);
        vm.expectRevert("Not submitted");
        notice.approve(id, "OK");
        vm.stopPrank();
    }

    function testApproveRevertsIfNotRegulator() public {
        vm.startPrank(supplier);
        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Critical,
            uint48(block.timestamp),
            "Sum",
            "uri",
            keccak256("root123")
        );
        notice.submit(id);
        vm.stopPrank();

        vm.startPrank(random);
        vm.expectRevert("Not regulator");
        notice.approve(id, "OK");
        vm.stopPrank();
    }

    // Reject
    function testRejectSuccess() public {
        vm.startPrank(supplier);
        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Minor,
            uint48(block.timestamp),
            "sum",
            "uri",
            bytes32(0)
        );
        notice.submit(id);
        vm.stopPrank();

        vm.startPrank(regulator);
        notice.reject(id, "Bad");

        (ChangeNotice.Notice memory n, ) = notice.getNotice(id);
        assertEq(uint(n.status), uint(ChangeNotice.Status.Rejected));
        assertEq(n.regulatorNote, "Bad");

        vm.stopPrank();
    }

    function testRejectRevertsIfNotSubmitted() public {
        vm.startPrank(supplier);
        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Minor,
            uint48(block.timestamp),
            "sum",
            "uri",
            bytes32(0)
        );
        vm.stopPrank();

        vm.startPrank(regulator);
        vm.expectRevert("Not submitted");
        notice.reject(id, "nope");
        vm.stopPrank();
    }

    // Views
    function testNoticesForBatch() public {
        vm.startPrank(supplier);
        notice.createNotice(batchId, ChangeNotice.NoticeType.Other, ChangeNotice.Severity.Minor, 0, "sum1", "uri", bytes32(0));
        notice.createNotice(batchId, ChangeNotice.NoticeType.Other, ChangeNotice.Severity.Major, 0, "sum2", "uri2", bytes32(0));
        vm.stopPrank();

        uint256[] memory list = notice.noticesForBatch(batchId);
        assertEq(list.length, 2);
        assertEq(list[0], 1);
        assertEq(list[1], 2);
    }

    function testAnchorVerifiedOnMerkleFalseIfNoAnchor() public {
        vm.startPrank(supplier);
        uint256 id = notice.createNotice(
            batchId,
            ChangeNotice.NoticeType.Other,
            ChangeNotice.Severity.Major,
            0,
            "s",
            "uri",
            bytes32(0)
        );
        vm.stopPrank();

        assertFalse(notice.anchorVerifiedOnMerkle(id));
    }
}
