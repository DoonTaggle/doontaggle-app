pragma solidity ^0.4.17;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/DoonTaggle.sol";

// Requirement: Create at least 5 tests for each smart contract and write a sentence or two
// explaining what the tests are covering, and explain why you wrote those tests

// This is the actual testing contract for DoonTaggle
contract TestDoonTaggle {
    DoonTaggle da = DoonTaggle(DeployedAddresses.DoonTaggle());

    //The Tag info and Reported Behavior being tested
    bytes10 TAGID1 = "FLSOL-TEST";
    bytes10 TAGID2 = "FLSOLTEST2";
    bytes8 EXPECTED_PLATENO = "SOL-TEST";
    bytes8 EXPECTED_PLATENO2 = "SOLTEST2";
    bytes2 EXPECTED_STATE = "FL";
    DoonTaggle.Behaviors EXPECTED_BEHAVIOR = DoonTaggle.Behaviors.Speeding;

    // Test #1
    // Testing the FileReport() function by filing a Report on a first Tag
    // and checking to ensure the tag numbers and number of reports are accurate after filing
    function testFileReport1() public {
        bytes10 tag;
        uint numReports;

        (tag, numReports) = da.fileReport(TAGID1, EXPECTED_PLATENO, EXPECTED_STATE, EXPECTED_BEHAVIOR, 0, 0);
        Assert.equal(tag, TAGID1, "The tag should be SOL-TEST");
        Assert.equal(numReports, 1, "The report count should be 1");
        Assert.equal(da.getTagCount(), 1, "There should be 1 tags");
    }

    // Test #2
    // Testing the FileReport() function by filing a second Report on a first Tag
    // and checking to ensure the tag numbers and number of reports are accurate after filling
    function testFileReport2() public {
        bytes10 tag;
        uint numReports;
        (tag, numReports) = da.fileReport(TAGID1, EXPECTED_PLATENO, EXPECTED_STATE, EXPECTED_BEHAVIOR, 29*1e5, -82*1e5);
        Assert.equal(tag, TAGID1, "The tag should be SOL-TEST");
        Assert.equal(numReports, 2, "The report count should be 2");
    }

    // Test #3
    // Testing the FileReport() function by filing a Report on a second Tag
    // and checking to ensure the tag numbers and number of reports are accurate after filing
    function testFileReportSecondTag() public {
        bytes10 tag;
        uint numReports;
        (tag, numReports) = da.fileReport(TAGID2, EXPECTED_PLATENO2, EXPECTED_STATE, EXPECTED_BEHAVIOR, 0, 0);
        Assert.equal(tag, TAGID2, "The tag should be SOLTEST2");
        Assert.equal(numReports, 1, "The report count should be 1");
        Assert.equal(da.getTagCount(), 2, "There should be two tags");
    }

    // Test #4
    // Test ensures that after new reports are filed on the Tag, the report count is incremented.
    function testNumberofReports() public {
        uint expected = 2; //filed two reports above
        uint returned = da.getReportCount(TAGID1);

        Assert.equal(returned, expected, "The report count for SOL-TEST should be 2");
    }

    // Test #5
    // Test reads the single DriverReport for TAG2 by index and verifies that it has the value that was entered when testFileReport was called
    function testDriverReportbyIndex() public {
        //Grab the last report number key
        uint lastReportNum = da.getReportCount(TAGID2);

        DoonTaggle.Behaviors behavior;
        address reportedBy;
        uint timestamp;
        int latitude;
        int longitude;

        (behavior, reportedBy, timestamp, latitude, longitude) = da.getDriverReportByIndex(TAGID2, lastReportNum);

        Assert.equal(uint(behavior), uint(EXPECTED_BEHAVIOR), "The reported behavior does not match");
        Assert.isNotZero(reportedBy, "The address of the reporter is improper");
        Assert.equal(reportedBy, this, "The address of the reporter does not match the address of the test contract");
        Assert.isAtMost(timestamp, now, "Timestamp is in error");
        Assert.equal(latitude,0, "Latitude does not match");
        Assert.equal(longitude,0, "longitude does not match");
    }

    // Test #6
    // Test reads the most recent driver reports from FIRST TAG entered
    // Verifies that it the value that was entered when testFileReport1 was called
    function testRecentReports() public {
        uint[10] memory reportNo;
        DoonTaggle.Behaviors[10] memory behavior;
        address[10] memory reportedBy;
        uint[10] memory timestamp;
        int[10] memory latitude;
        int[10] memory longitude;
        uint numReturned;

        (numReturned, reportNo, reportedBy, behavior, timestamp, latitude, longitude) = da.getRecentDriverReports(TAGID1);
        Assert.equal(reportNo[0], 2, "This should be the second report on FIRST TAG");
        Assert.equal(uint(behavior[0]), uint(EXPECTED_BEHAVIOR), "The reported behavior does not match");
        Assert.isNotZero(reportedBy[0], "The address of the reporter is improper");
        Assert.equal(reportedBy[0], this, "The address of the reporter does not match the address of the test contract");
        Assert.isAtMost(timestamp[0], now, "Timestamp is in error");
        Assert.equal(latitude[0],29*1e5, "Latitude does not match");
        Assert.equal(longitude[0],-82*1e5, "longitude does not match");
    }

    // Test #7
    // Test reads the Driver Score of the FIRST TAG entered to determine if it matches
    function testDriverScore() public {
        uint score;
        uint expected = 16;

        score = da.getDriverScore(TAGID1);

        Assert.equal(score, expected, "The Driver Score does not match the expected value");
    }

    // Test #8
    // Test for the circuit breaker to make sure terminateContract can only be called when in PAUSED state
    // @dev It actually tests for the revert so that the test can pass (using the TestProxy)
    // @dev Be aware - uses a lot of gas!
    function testPauseAssert() public {
        DoonTaggle tempDA = new DoonTaggle();
        ThrowProxy throwProxy = new ThrowProxy(address(tempDA));
        //IMPORTANT: Currently only works if function is void return type - https://github.com/trufflesuite/truffle/issues/1001
        DoonTaggle(address(throwProxy)).terminateContract();
        bool r = throwProxy.execute.gas(200000)();
        Assert.isFalse(r, "Should be false, as it it should revert when we attempt to terminate contract when it is not paused");
    }

}

// Proxy contract for testing whether ASSERTS that should fail, do indeed fail
contract ThrowProxy {
    address public target;
    bytes data;

    constructor (address _target) public {
        target = _target;
    }

    //prime the data using the fallback function.
    function() public {
        data = msg.data;
    }

    function execute() public returns (bool) {
        return target.call(data);
    }
}