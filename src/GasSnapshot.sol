// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";

contract GasSnapshot is Script {
    error GasMismatch(uint256 oldGas, uint256 newGas);

    /// @notice if this environment variable is true, we revert on gas mismatch
    string public constant CHECK_ENV_VAR = "FORGE_SNAPSHOT_CHECK";
    /// @notice save gas snapshots in this dir
    string public constant SNAP_DIR = ".forge-snapshots/";
    /// @notice temporary env variable to help with string parsing
    string private constant TEMP_ENV_VAR = "_forge_snapshot_temp_gas";
    /// @notice if true, revert on gas mismatch, else overwrite with new values
    bool internal check;

    /// @notice Transient variable for the start gas
    uint256 internal cachedGas;
    /// @notice Transient variable for the snapshot name
    string internal cachedName;

    constructor() {
        _mkdirp(SNAP_DIR);
        try vm.envBool(CHECK_ENV_VAR) returns (bool _check) {
            check = _check;
        } catch {
            check = false;
        }
    }

    /// @notice Start a snapshot with the given name
    /// @dev The next call to `snapEnd` will end the snapshot
    function snapStart(string memory name) internal {
        cachedName = name;
        cachedGas = gasleft() - 22100; // subtract sstore cost
    }

    /// @notice End the current snapshot
    /// @dev Must be called after a call to `snapStart`, else reverts with underflow
    function snapEnd() internal {
        uint256 newGasLeft = gasleft();
        uint256 gasUsed = cachedGas - newGasLeft;
        // reset to 0 so all writes are cold for consistent overhead handling
        cachedGas = 0;

        if (check) {
            _checkSnapshot(gasUsed, cachedName);
        } else {
            _writeSnapshot(cachedName, gasUsed);
        }
    }

    /// @notice Check the gas usage against the snapshot. Revert on mismatch
    function _checkSnapshot(uint256 gasUsed, string memory name) internal {
        uint256 oldGasUsed = _readSnapshot(name);
        if (oldGasUsed != gasUsed) {
            revert GasMismatch(oldGasUsed, gasUsed);
        }
    }

    /// @notice Read the last snapshot value from the file
    function _readSnapshot(string memory name) private returns (uint256 res) {
        string[] memory getSnapshot = new string[](2);
        getSnapshot[0] = "cat";
        getSnapshot[1] = _getSnapFile(name);
        string memory oldValue = string(vm.ffi(getSnapshot));
        // hack to use forge string uint parsing
        vm.setEnv(TEMP_ENV_VAR, oldValue);
        res = vm.envUint(TEMP_ENV_VAR);
    }

    /// @notice Write the new snapshot value to file
    function _writeSnapshot(string memory name, uint256 gasUsed) private {
        string[] memory writeSnapshot = new string[](3);
        writeSnapshot[0] = "sh";
        writeSnapshot[1] = "-c";
        writeSnapshot[2] = string(
            abi.encodePacked("echo -n ", vm.toString(gasUsed), " > ", _getSnapFile(name))
        );
        vm.ffi(writeSnapshot);
    }

    /// @notice Make the directory for snapshots
    function _mkdirp(string memory dir) private {
        string[] memory mkdirp = new string[](3);
        mkdirp[0] = "mkdir";
        mkdirp[1] = "-p";
        mkdirp[2] = dir;
        vm.ffi(mkdirp);
    }

    /// @notice Get the snapshot file name
    function _getSnapFile(string memory name)
        private
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(SNAP_DIR, name, ".snap"));
    }
}