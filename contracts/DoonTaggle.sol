pragma solidity ^0.5.0;


//Requirement: Use a library - supports ownership features
import "./Ownable.sol";


/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
    event Pause();
    event Unpause();

    bool public paused = false;


    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!paused, "The function may be called only when the contract is not paused.");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(paused, "The function may be called only when the contract is paused.");
        _;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() public onlyOwner whenNotPaused {
        paused = true;
        emit Pause();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() public onlyOwner whenPaused {
        paused = false;
        emit Unpause();
    }
}


/**
 * @title DoonTaggle - Contract for recording driver behaviors and locations associated with License Tags
 */
contract DoonTaggle is Pausable {

    mapping (bytes10 => Tag) private tags; //mapping key is of the form 2-letter state code and 8 alphacharacter plateno
    uint private numTags; //count of the number of tags

    enum Behaviors { None, Aggressive, Speeding, Proximity, Erratic, Hazard }

    struct DriverReport {
        Behaviors behavior;
        address reportedBy;
        uint entryTime; //time code of entry of the driver report
        int longitude;
        int latitude;
    }

    struct Tag {
        bytes8 plateNo;
        bytes2 state;
        uint numReports;
        mapping (uint => DriverReport) driverReports;
        bool bExists; //So that we can tell if this tag in the mapping namespace is initialized
        uint driverScore; //The total Driver Score
    }

    //Events
    event LogReported (address reportedBy, bytes8 plateNo, bytes2 state, Behaviors behavior);
    event LogNewTag (bytes10 tagID, uint numTags);
    event LogPlateAccess (bytes10 tagID);

    //Const
    uint constant private MAX_RETURN = 10;
    int constant private UPPER_BOUND_GEO = 90*1e5;
    int constant private LOWER_BOUND_GEO = -90*1e5;

    // Driver Score weightings related to the behavior types
    uint constant private WT_AGGRESSIVE = 10;
    uint constant private WT_SPEEDING = 8;
    uint constant private WT_PROXIMITY = 5;
    uint constant private WT_ERRATIC = 6;
    uint constant private WT_HAZARD = 4;

    /**
     * @notice File a DriverReport on a specified Tag
     * @dev File a DriverReport on a specified Tag
     * @param _tagID The TagID of the vehicle's tag. BYTES10 composite of two-letter state code and up to 8 letter plate number
     * @param _plateNo The plate number of the vehicle's tag - BYTES8
     * @param _state The state of the vehicle's tag - BYTES2
     * @param _behavior The reported behavior category - from BEHAVIORS enum
     * @param _latitude The latitude of the geolocation of the report (converted to integer at 1e5 precision)
     * @param _longitude The longitude of the geolocation of the report (converted to integer at 1e5 precision)
     * @return key The TagID of the key in the mapping
     * @return numReports The number of reports against this tag
     */
    function fileReport (bytes10 _tagID, bytes8 _plateNo, bytes2 _state, Behaviors _behavior, int _latitude, int _longitude)
    external whenNotPaused
    returns (bytes10 tag, uint) {

        //Validate PlateNo and State using Library
        require(SafeLicenseTags.validatePlateNoInternal(_plateNo)==true, "Invalid Plate No");
        require(SafeLicenseTags.validateStateInternal(_state)==true, "Invalid State Code");

        //Rather than failing, fix the latitude and longitude to zero if they are out of bounds
        int latitude;
        int longitude;
        if (_latitude > UPPER_BOUND_GEO || _latitude < LOWER_BOUND_GEO || _longitude > UPPER_BOUND_GEO || _longitude < LOWER_BOUND_GEO) {
            latitude = 0;
            longitude = 0;
        } else {
            latitude = _latitude;
            longitude = _longitude;
        }

        //Check to see if tag is already initialized.
        //If not, set the tag data
        //Then add the driver report to the tag
        bytes10 key = _tagID;
        emit LogPlateAccess (key);

        if (!(tags[key].bExists)) {
            tags[key].plateNo = _plateNo;
            tags[key].state = _state;
            tags[key].driverScore = 0;
            tags[key].bExists = true;
            numTags++;
            emit LogNewTag (_tagID, numTags);
        }
        tags[key].numReports++;

        //Note: only using "now" for approximate entryTime, not for fine-grained calculations
        tags[key].driverReports[tags[key].numReports] = DriverReport(
            {behavior: _behavior, reportedBy: msg.sender, entryTime: now, latitude: latitude, longitude: longitude});

        //Add the behavior weight to the composite score
        tags[key].driverScore += _getBehaviorWeight(_behavior);

        emit LogReported (msg.sender, _plateNo, _state, _behavior);
        return (key, tags[key].numReports);
    }

    /**
     * @notice Get the most recent DriverReports about a specified Tag
     * @dev Returns the most recent (up to MAX_RETURN (or less)) reports in LIFO order
     * @param tagID the TagID of the vehicle's tag
     * @return numReturned - the number of records returned
     * @return arrays of length MAX_RETURN - reportNo, addresses, behaviors, timestamp, latitude, longitude
     */
    function getRecentDriverReports(bytes10 tagID) external view whenNotPaused
    returns (
    uint numReturned,
    uint[MAX_RETURN] memory reportNo,
    address[MAX_RETURN] memory addresses,
    Behaviors[MAX_RETURN] memory behaviors,
    uint[MAX_RETURN] memory timeReport,
    int[MAX_RETURN] memory latitude,
    int[MAX_RETURN] memory longitude ) {

        uint nR = tags[tagID].numReports;
        uint loopCount = 0;

        //Return the Driver reports in reverse entry order
        for (uint i = nR; (i > 0 && loopCount < MAX_RETURN); i--) {
            DriverReport memory dr = tags[tagID].driverReports[i];
            reportNo[loopCount] = i;
            addresses[loopCount] = dr.reportedBy;
            behaviors[loopCount] = dr.behavior;
            timeReport[loopCount] = dr.entryTime;
            latitude[loopCount] = dr.latitude;
            longitude[loopCount] = dr.longitude;

            loopCount++;
        }
        return (loopCount, reportNo, addresses, behaviors, timeReport, latitude, longitude);
    }

    /**
     * @notice Get the driver score based on weighted composite of a Tag's associated Driver Reports.
     * @dev Score is based on severity weighting of all the driver reports.
     * @param _tagID The tagID of the vehicles tag (i.e., STATE code + PlateNo)
     * @return uint Driver Score value of driver.
     */
    function getDriverScore(bytes10 _tagID) external view whenNotPaused returns (uint) {
        return tags[_tagID].driverScore;
    }

    /**
     * @notice Return the weight value of a behavior
     * @dev Based on constants
     * @param _behavior Behavior type from Behaviors enum
     * @return uint Returns the Behavior weight
     */
    function _getBehaviorWeight(Behaviors _behavior) internal pure returns (uint) {
        if (_behavior == Behaviors.Aggressive) {
            return WT_AGGRESSIVE;
        } else if (_behavior == Behaviors.Speeding) {
            return WT_SPEEDING;
        } else if (_behavior == Behaviors.Proximity) {
            return WT_PROXIMITY;
        } else if (_behavior == Behaviors.Erratic) {
            return WT_ERRATIC;
        } else if (_behavior == Behaviors.Hazard) {
            return WT_HAZARD;
        } else {
            return 0;
        }
    }

    /**
     * @notice Get the total number of Tags
     * @dev Accessor function for the private state variable numTags
     * @return uint Number of Tags in the DriveAudit registry.
     */
    function getTagCount() external view whenNotPaused returns (uint) {
        return numTags;
    }

    /**
     * @notice Get the total number of DriverReports in the specified Tag.
     * @dev TagID in BYTES10 form.
     * @param _tagID the TagID of the vehicle's tag.
     * @return numReports Number of reports on this Tag.
     */
    function getReportCount(bytes10 _tagID) external view whenNotPaused
    returns (uint) {
        return tags[_tagID].numReports;
    }

    /**
     * @notice Get a specific DriverReport about a specified Tag
     * @param _tagID the TagID of the vehicle's tag
     * @param _index the number of the driver report
     * @return the members of the DriverReport struct
     */
    function getDriverReportByIndex(bytes10 _tagID, uint _index) external view whenNotPaused
    returns (Behaviors, address, uint, int, int) {
        DriverReport memory dr = tags[_tagID].driverReports[_index];
        return (dr.behavior, dr.reportedBy, dr.entryTime, dr.latitude, dr.longitude);
    }

    /**
     * @notice Kill the contract and send funds to owner
     * @dev Can only be called by owner, when paused
     */
/*    function terminateContract() public onlyOwner whenPaused {
        selfdestruct(owner);
    }
*/
    /**
     * @notice DriverReport fallback function
     * @dev  Fallback function, called if other functions don't match call or Ether is sent without data.
     * @dev Ether sent to this contract is reverted to sender.
     * @dev Typically, called when invalid data is sent.
     */
    function () external {
        revert("Fallback function - reverted any Ether to sender");
    }
}


/**
 * @title SafeLicenseTags validation library for validating the form of License Tag data
 * @notice Validates that a Plate No. and State of Issuance are valid entries
 */
library SafeLicenseTags {
    /**
     * @notice Check if PlateNo input is reasonable choice.
     * @param _plateNo the plate number to check in BYTES8
     * @return True IFF `_plateNo` meets the criteria below, or false otherwise:
        ///   no fewer than 1 character
        ///   - no more than 8 characters
        ///   - no characters other than:
        ///     - "roman" alphabet letters (A-Z and a-z)
        ///     - western digits (0-9)
        ///     - "safe" punctuation: ! ( ) - . _ SPACE
        /// Note that we deliberately exclude characters which may cause
        /// security problems for websites and databases if escaping is
        /// not performed correctly, such as < > " and '.
        /// Apologies for the lack of non-English language support.
     */
    function validatePlateNoInternal(bytes8 _plateNo)
    internal pure
    returns (bool allowed) {
        bytes8 nameBytes = _plateNo;
        uint lengthBytes = nameBytes.length;
        bool ok = true;
        if (lengthBytes < 1 || lengthBytes > 8) {
            ok = false;
        } else {
/*            for (uint i = 0; i < lengthBytes; i++) {
                //byte b = nameBytes[i];
                uint b = nameBytes[i];
                if (!((b >= 48 && b <= 57) || // 0 - 9
                    (b >= 65 && b <= 90) || // A - Z
                    (b >= 97 && b <= 122) ||   // a - z
                    b == 32 || // space
                    b == 33 || // !
                    b == 45 ||  // -
                    b == 46 ||    // .
                    b == 0
                )) {
                    ok = false;
                    break;
                }
            } */
        }
        return ok;
    }

    /**
     * @notice Check if state input is reasonable choice.
     * @param _state the plate's state of issueance to check in BYTES2
     * @return True if-and-only-if `_state` meets the criteria below, or false otherwise:
        ///     - no characters other than:
        ///     - "roman" alphabet letters, capitalized (A-Z)
     */
    function validateStateInternal (bytes2 _state)
    internal pure
    returns (bool allowed) {
        bool ok = true;
/*        for (uint i = 0; i < 2; i++) {
            byte b = _state[i];
            if (!((b >= 65 && b <= 90))) {
                ok = false;
                break;
            }
        } */
        return ok;
    }
}



